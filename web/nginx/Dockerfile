#FROM jwilder/nginx-proxy
FROM ubuntu:16.04

COPY cat_me_to_fastcgi_params /tmp/

RUN apt-get update && apt-get -y install nginx
RUN cat /tmp/cat_me_to_fastcgi_params >> /etc/nginx/fastcgi_params && rm /tmp/cat_me_to_fastcgi_params

COPY oscript.io /etc/nginx/sites-enabled
COPY hub.oscript.io /etc/nginx/sites-enabled

VOLUME /etc/nginx/sites-enabled
VOLUME /var/www

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]