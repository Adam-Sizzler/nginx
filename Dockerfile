#######################################
# Stage 1: Компиляция Nginx и модулей
#######################################
FROM alpine:latest AS build

ENV NGINX_VERSION=1.30.3

# Установка зависимостей для сборки
RUN apk add --no-cache \
    gcc make build-base linux-headers pcre2-dev \
    zlib-dev openssl-dev libmaxminddb-dev gd-dev \
    libxslt-dev wget git

WORKDIR /build

# Скачивание исходников Nginx
RUN wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar -xvf nginx-${NGINX_VERSION}.tar.gz

# Клонирование модуля GeoIP2
RUN git clone https://github.com/leev/ngx_http_geoip2_module.git /tmp/geoip2

WORKDIR /build/nginx-${NGINX_VERSION}

# Конфигурация сборки со всеми необходимыми модулями (включая HTTP/2 и HTTP/3)
RUN ./configure \
    --prefix=/usr/share/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/run/nginx.pid \
    --lock-path=/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --add-module=/tmp/geoip2 \
    --with-cc-opt="-Os -fstack-protector-strong" \
    --with-ld-opt="-Wl,-z,relro -Wl,-z,now"

# Компиляция и установка
RUN make -j$(nproc) && make install

#######################################
# Stage 2: Финальный минимальный образ
#######################################
FROM alpine:latest

# Сохраняем фиксированный UID/GID 101 для стабильности прав на томах (Volume)
RUN addgroup -S -g 101 nginx && \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx

# Установка системных зависимостей для работы рантайма
RUN apk add --no-cache \
    libmaxminddb \
    gd \
    pcre2 \
    libxslt \
    zlib \
    openssl \
    ca-certificates \
    tzdata \
    curl \
    supervisor \
    bash

# Копируем собранный NGINX
COPY --from=build /usr/sbin/nginx /usr/sbin/nginx
COPY --from=build /usr/share/nginx /usr/share/nginx

# Подготовка структуры директорий
RUN mkdir -p \
    /etc/nginx/conf.d \
    /etc/nginx/geolite2 \
    /var/www/html \
    /var/cache/nginx \
    /var/log/nginx \
    /var/log/supervisor \
    /run \
    /docker-entrypoint.d

# Права доступа
RUN chown -R nginx:nginx /var/cache/nginx /var/log/nginx && \
    chmod 755 /var/cache/nginx /var/log/nginx

# Перенаправление логов в stdout/stderr контейнера
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Копируем локальные файлы проекта
COPY mime.types /etc/nginx/
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY var/www/ /var/www/

# Выполняем первичную загрузку баз
COPY scripts/update_geolite.sh /usr/local/bin/
COPY docker-entrypoint.sh /
RUN chmod +x /usr/local/bin/update_geolite.sh /docker-entrypoint.sh

EXPOSE 36078

# Запускаем через supervisor
ENTRYPOINT ["/docker-entrypoint.sh"]
