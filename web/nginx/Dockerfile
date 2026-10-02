# Официальный образ с модулем ngx_otel_module (трассировка OpenTelemetry)
FROM nginx:1.30.5-otel

COPY cat_me_to_fastcgi_params /tmp/

RUN apt-get update && apt-get -y install --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*
RUN cat /tmp/cat_me_to_fastcgi_params >> /etc/nginx/fastcgi_params && rm /tmp/cat_me_to_fastcgi_params

# Свой nginx.conf: грузит модуль otel и подключает sites-enabled; демо-сайт образа не нужен
RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf
COPY ssl_conf /etc/nginx/ssl_conf
COPY sites-enabled /etc/nginx/sites-enabled
COPY conf.d /etc/nginx/conf.d
COPY snippets /etc/nginx/snippets
COPY robots /etc/nginx/robots

# Самоподписанный сертификат для default-сервера
RUN mkdir /etc/nginx/ssl && \
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt -subj "/C=RU/ST=Serpukhov/L=Serpukhov/O=OneScript./OU=OneScript/CN=oscript.io"

VOLUME /var/www

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
