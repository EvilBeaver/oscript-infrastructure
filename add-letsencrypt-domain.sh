#!/bin/bash

# Сертификат для одного нового домена, остальные не трогает:
#   ./add-letsencrypt-domain.sh hub-new.oscript.io

set -e

domain="$1"
if [ -z "$domain" ]; then
  echo "Usage: $0 <domain>" >&2
  exit 1
fi

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

rsa_key_size=4096
data_path="./web/certbot"
email="ovsiankin.aa@gmail.com"
staging=0

if [ -d "$data_path/conf/live/$domain" ]; then
  echo "Certificate for $domain already exists, nothing to do." >&2
  exit 1
fi

echo "### Creating dummy certificate for $domain ..."
path="/etc/letsencrypt/live/$domain"
mkdir -p "$data_path/conf/live/$domain"
docker-compose run --rm --no-deps --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot

echo "### Rebuilding nginx with the new site ..."
docker-compose build nginx
docker-compose up --force-recreate --no-deps -d nginx

echo "### Deleting dummy certificate for $domain ..."
docker-compose run --rm --no-deps --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domain && \
  rm -Rf /etc/letsencrypt/archive/$domain && \
  rm -Rf /etc/letsencrypt/renewal/$domain.conf" certbot

echo "### Requesting Let's Encrypt certificate for $domain ..."
if [ $staging != "0" ]; then staging_arg="--staging"; fi

docker-compose run --rm --no-deps --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    --email $email \
    -d $domain \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --non-interactive" certbot

echo "### Reloading nginx ..."
docker-compose exec nginx nginx -s reload
