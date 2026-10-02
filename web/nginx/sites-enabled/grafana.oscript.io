server {
    listen 80;
    listen [::]:80;
    server_name grafana.oscript.io;

    access_log /var/log/nginx/access.log with_host;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name grafana.oscript.io;

    access_log /var/log/nginx/access.log with_host;

    add_header X-Content-Type-Options nosniff;
    add_header X-Robots-Tag none;
    add_header X-Download-Options noopen;
    add_header X-Permitted-Cross-Domain-Policies none;

    add_header Strict-Transport-Security "max-age=31536000" always;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_redirect off;

    resolver 127.0.0.11 valid=30s;

    location / {
        set $target_url http://lgtm:3000;
        proxy_pass $target_url;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $http_host;
    }

    include /etc/nginx/ssl_conf/options-ssl-nginx.conf;
    ssl_dhparam /etc/nginx/ssl_conf/ssl-dhparams.pem;
    ssl_certificate /etc/letsencrypt/live/grafana.oscript.io/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/grafana.oscript.io/privkey.pem;
}
