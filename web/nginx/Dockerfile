#FROM jwilder/nginx-proxy
FROM ubuntu:16.04

COPY cat_me_to_fastcgi_params /tmp/

RUN apt-get update && apt-get -y install nginx openssl
RUN cat /tmp/cat_me_to_fastcgi_params >> /etc/nginx/fastcgi_params && rm /tmp/cat_me_to_fastcgi_params

COPY ssl_conf /etc/nginx/ssl_conf
COPY sites-enabled /etc/nginx/sites-enabled

# Самоподписанный сертификат для default-сервера
RUN mkdir /etc/nginx/ssl && \
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt -subj "/C=RU/ST=Serpukhov/L=Serpukhov/O=OneScript./OU=OneScript/CN=oscript.io"

VOLUME /var/www

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
