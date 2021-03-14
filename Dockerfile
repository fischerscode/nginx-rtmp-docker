# Dockerfile for a simple Nginx stream replicator

# Separate build stage to keep build dependencies out of our final image
ARG ALPINE_VERSION=alpine:3.12

FROM ${ALPINE_VERSION} AS nginx

# Software versions to build
ARG NGINX_VERSION=nginx-1.18.0
ARG NGINX_RTMP_MODULE_VERSION=afd350e0d8b7820d7d2cfc3fa748217153265ce6

# Install buildtime dependencies
# Note: We build against LibreSSL instead of OpenSSL, because LibreSSL is already included in Alpine
RUN apk --no-cache add build-base libressl-dev

# Download sources
# Note: We download our own fork of nginx-rtmp-module which contains some additional enhancements over the original version by arut
RUN mkdir -p /build && \
    wget -O - https://nginx.org/download/${NGINX_VERSION}.tar.gz | tar -zxC /build -f - && \
    mv /build/${NGINX_VERSION} /build/nginx && \
    wget -O - https://github.com/arut/nginx-rtmp-module/archive/${NGINX_RTMP_MODULE_VERSION}.tar.gz | tar -zxC /build -f - && \
    mv /build/nginx-rtmp-module-${NGINX_RTMP_MODULE_VERSION} /build/nginx-rtmp-module

# Build a minimal version of nginx
RUN cd /build/nginx && \
    ./configure \
        --build=DvdGiessen/nginx-rtmp-docker \
        --prefix=/etc/nginx \
        --sbin-path=/usr/local/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/lock/nginx.lock \
        --http-client-body-temp-path=/tmp/nginx/client-body \
        --user=nginx --group=nginx \
        --without-http-cache \
        --without-http_access_module \
        --without-http_auth_basic_module \
        --without-http_autoindex_module \
        --without-http_browser_module \
        --without-http_charset_module \
        --without-http_empty_gif_module \
        --without-http_fastcgi_module \
        --without-http_geo_module \
        --without-http_grpc_module \
        --without-http_gzip_module \
        --without-http_limit_conn_module \
        --without-http_limit_req_module \
        --without-http_map_module \
        --without-http_memcached_module \
        --without-http_mirror_module \
        --without-http_proxy_module \
        --without-http_referer_module \
        --without-http_rewrite_module \
        --without-http_scgi_module \
        --without-http_split_clients_module \
        --without-http_ssi_module \
        --without-http_upstream_hash_module \
        --without-http_upstream_ip_hash_module \
        --without-http_upstream_keepalive_module \
        --without-http_upstream_least_conn_module \
        --without-http_upstream_random_module \
        --without-http_upstream_zone_module \
        --without-http_userid_module \
        --without-http_uwsgi_module \
        --without-mail_imap_module \
        --without-mail_pop3_module \
        --without-mail_smtp_module \
        --without-pcre \
        --without-poll_module \
        --without-select_module \
        --without-stream_access_module \
        --without-stream_geo_module \
        --without-stream_limit_conn_module \
        --without-stream_map_module \
        --without-stream_return_module \
        --without-stream_split_clients_module \
        --without-stream_upstream_hash_module \
        --without-stream_upstream_least_conn_module \
        --without-stream_upstream_random_module \
        --without-stream_upstream_zone_module \
        --with-ipv6 \
        --add-module=/build/nginx-rtmp-module && \
    make -j $(getconf _NPROCESSORS_ONLN)

# inspired by https://github.com/alfg/docker-ffmpeg
FROM ${ALPINE_VERSION} AS ffmpeg

ARG FFMPEG_VERSION=4.3.2

# FFmpeg build dependencies.
RUN apk add --update \
  build-base \
  coreutils \
  freetype-dev \
  gcc \
  lame-dev \
  libogg-dev \
  libass \
  libass-dev \
  libvpx-dev \
  libvorbis-dev \
  libwebp-dev \
  libtheora-dev \
  opus-dev \
  openssl \
  openssl-dev \
  pkgconf \
  pkgconfig \
  rtmpdump-dev \
  wget \
  x264-dev \
  x265-dev \
  yasm

# Get fdk-aac from community.
RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories && \
  apk add --update fdk-aac-dev

# Get rav1e from testing.
RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories && \
  apk add --update rav1e-dev

# Get ffmpeg source.
RUN cd /tmp/ && \
  wget https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz && \
  tar zxf ffmpeg-${FFMPEG_VERSION}.tar.gz && rm ffmpeg-${FFMPEG_VERSION}.tar.gz

# Compile ffmpeg.
RUN cd /tmp/ffmpeg-${FFMPEG_VERSION} && \
  ./configure \
  --enable-version3 \
  --enable-gpl \
  --enable-nonfree \
#  --enable-small \
#  --enable-libmp3lame \
  --enable-libx264 \
#  --enable-libx265 \
#  --enable-libvpx \
#  --enable-libtheora \
#  --enable-libvorbis \
#  --enable-libopus \
  --enable-libfdk-aac \
#  --enable-libass \
#  --enable-libwebp \
  --enable-librtmp \
#  --enable-librav1e \
#  --enable-postproc \
#  --enable-avresample \
#  --enable-libfreetype \
#  --enable-openssl \
  --disable-debug \
  --disable-doc \
  --disable-ffplay \
  --extra-cflags="-I/opt/ffmpeg/include" \
  --extra-ldflags="-L/opt/ffmpeg/lib" \
#  --extra-libs="-lpthread -lm" \
  --prefix="/opt/ffmpeg" && \
  make && make install


# Final image stage
FROM ${ALPINE_VERSION}

# Set up group and user
RUN addgroup -S nginx --gid 101 && \
    adduser -s /sbin/nologin -G nginx -S -D -H nginx --uid 101

# Set up directories
RUN mkdir -p /etc/nginx /var/log/nginx /var/www && \
    chown -R nginx:nginx /var/log/nginx /var/www && \
    chmod -R 775 /var/log/nginx /var/www

# Forward logs to Docker
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Set up exposed ports
EXPOSE 1935

# Set up entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 555 /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD []

# Copy files from build stage
COPY --from=nginx /build/nginx/objs/nginx /usr/local/sbin/nginx
COPY --from=nginx /lib/libssl.so.48 /lib/libssl.so.48
COPY --from=nginx /lib/libcrypto.so.46 /lib/libcrypto.so.46

COPY --from=ffmpeg /opt/ffmpeg /opt/ffmpeg
COPY --from=ffmpeg /usr/lib/libfdk-aac.so.2 /usr/lib/libfdk-aac.so.2
COPY --from=ffmpeg /usr/lib/librtmp.so.1 /usr/lib/librtmp.so.1
COPY --from=ffmpeg /usr/lib/libx264.so.157 /usr/lib/libx264.so.157
COPY --from=ffmpeg /usr/lib/libx264.so /usr/lib/libx264.so
COPY --from=ffmpeg /usr/lib/libgnutls.so.30 /usr/lib/libgnutls.so.30
COPY --from=ffmpeg /usr/lib/libhogweed.so.5 /usr/lib/libhogweed.so.5
COPY --from=ffmpeg /usr/lib/libnettle.so.7 /usr/lib/libnettle.so.7
COPY --from=ffmpeg /usr/lib/libgmp.so.10 /usr/lib/libgmp.so.10
COPY --from=ffmpeg /usr/lib/libp11-kit.so.0 /usr/lib/libp11-kit.so.0
COPY --from=ffmpeg /usr/lib/libunistring.so.2 /usr/lib/libunistring.so.2
COPY --from=ffmpeg /usr/lib/libtasn1.so.6 /usr/lib/libtasn1.so.6
COPY --from=ffmpeg /usr/lib/libffi.so.7 /usr/lib/libffi.so.7

ENV PATH=/opt/ffmpeg/bin:$PATH

# Set up config file
COPY nginx.conf /etc/nginx/nginx.conf
RUN chmod 444 /etc/nginx/nginx.conf
