#!/bin/bash

# Сертификат для одного нового домена, остальные не трогает:
#   ./add-letsencrypt-domain.sh new.oscript.io

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [ ! -x "$ROOT/ops/dc.sh" ]; then
  echo 'Error: ops/dc.sh not found or not executable.' >&2
  exit 1
fi
DC="$ROOT/ops/dc.sh"

domain="$1"
if [ -z "$domain" ]; then
  echo "Usage: $0 <domain>" >&2
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
"$DC" run --rm --no-deps --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot

echo "### Rebuilding nginx with the new site ..."
"$DC" build nginx
"$DC" up --force-recreate --no-deps -d nginx

echo "### Deleting dummy certificate for $domain ..."
"$DC" run --rm --no-deps --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domain && \
  rm -Rf /etc/letsencrypt/archive/$domain && \
  rm -Rf /etc/letsencrypt/renewal/$domain.conf" certbot

echo "### Requesting Let's Encrypt certificate for $domain ..."
if [ $staging != "0" ]; then staging_arg="--staging"; fi

"$DC" run --rm --no-deps --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    --email $email \
    -d $domain \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --non-interactive" certbot

echo "### Reloading nginx ..."
"$DC" exec nginx nginx -s reload
