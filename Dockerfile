FROM alpine:3.10

LABEL maintainer="Huang Qixin huangqixin@msn.com"

ARG NGINX_VERSION="1.16.1"
ARG OPENSSL_VERSION="1.1.1d"
ARG PCRE_VERSION="8.43"
ARG GPG_KEYS="B0F4253373F8F6F510D42178520A9993A1C052F8"
RUN CONFIG="\
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-stream \
    --with-stream_ssl_preread_module \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-threads \
    --with-file-aio \
    --with-http_v2_module \
    --add-module=../ngx_brotli \
    --add-module=../ngx_http_geoip2_module \
    --with-openssl=../openssl-${OPENSSL_VERSION} \
    --with-pcre=../pcre-${PCRE_VERSION} \
    --with-pcre-jit \
    --with-zlib=../zlib \
    --without-http_mirror_module \
    --without-http_split_clients_module \
    --without-http_fastcgi_module \
    --without-http_uwsgi_module \
    --without-http_scgi_module \
    --without-http_grpc_module \
    --without-http_memcached_module \
    --without-http_empty_gif_module \
    " \
    && addgroup -S nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
    && apk add --no-cache --virtual .build-deps \
    gcc \
    g++ \
    libc-dev \
    make \
    linux-headers \
    curl \
    gnupg1 \
    libxslt-dev \
    gd-dev \
    geoip-dev \
    git \
    libmaxminddb-dev \
    && curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz -o nginx.tar.gz \
    && curl -fSL https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc  -o nginx.tar.gz.asc \
    && export GNUPGHOME="$(mktemp -d)" \
    && found=''; \
    for server in \
    ha.pool.sks-keyservers.net \
    hkp://keyserver.ubuntu.com:80 \
    hkp://p80.pool.sks-keyservers.net:80 \
    pgp.mit.edu \
    ; do \
    echo "Fetching GPG key $GPG_KEYS from $server"; \
    gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$GPG_KEYS" && found=yes && break; \
    done; \
    test -z "$found" && echo >&2 "error: failed to fetch GPG key $GPG_KEYS" && exit 1; \
    gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
    && rm -rf "$GNUPGHOME" nginx.tar.gz.asc \
    && mkdir -p /usr/src \
    && tar -zxC /usr/src -f nginx.tar.gz \
    && rm nginx.tar.gz \
    && cd /usr/src/ \
    && curl -fSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -o openssl-${OPENSSL_VERSION}.tar.gz \
    && tar xzf openssl-${OPENSSL_VERSION}.tar.gz \
    && curl -fSL https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VERSION}.tar.gz -o pcre-${PCRE_VERSION}.tar.gz \
    && tar xzf pcre-${PCRE_VERSION}.tar.gz \
    && git clone --depth=1 -b gcc.amd64 https://github.com/cloudflare/zlib.git \
    && cd zlib && ./configure && cd .. \
    && git clone --depth=1 --recurse-submodules https://github.com/google/ngx_brotli.git \
    && git clone --depth=1 -b 3.3 https://github.com/leev/ngx_http_geoip2_module.git \
    && cd /usr/src/nginx-$NGINX_VERSION \
    && ./configure $CONFIG \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install \
    && rm -rf /etc/nginx/html/ \
    && mkdir /etc/nginx/conf.d/ \
    && mkdir -p /usr/share/nginx/html/ \
    && install -m644 html/index.html /usr/share/nginx/html/ \
    && install -m644 html/50x.html /usr/share/nginx/html/ \
    && ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
    && strip /usr/sbin/nginx* \
    # && strip /usr/lib/nginx/modules/*.so \
    && rm -rf /usr/src/* \
    \
    # Bring in gettext so we can get `envsubst`, then throw
    # the rest away. To do this, we need to install `gettext`
    # then move `envsubst` out of the way so `gettext` can
    # be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    \
    && runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /tmp/envsubst \
    | tr ',' '\n' \
    | sort -u \
    | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )" \
    && apk add --no-cache --virtual .nginx-rundeps $runDeps \
    && apk del .build-deps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
    \
    # Bring in tzdata so users could set the timezones through the environment
    # variables
    && apk add --no-cache tzdata libmaxminddb \
    \
    # forward request and error logs to docker log collector
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx.vh.default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80 443

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]