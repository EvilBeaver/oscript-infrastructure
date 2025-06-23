server {
    listen 80;
    listen [::]:80;
    server_name oscript.io www.oscript.io;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name oscript.io www.oscript.io;
    root /var/www/oscript.io;

    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header X-Download-Options noopen;
    add_header X-Permitted-Cross-Domain-Policies none;

    add_header Strict-Transport-Security "max-age=31536000" always;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    client_max_body_size 50M;

    proxy_redirect off;
    
    resolver 127.0.0.11 valid=30s;

    location / {
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;
        set $target_url http://site:3030;
        proxy_pass $target_url; 
    }

    include /etc/nginx/ssl_conf/options-ssl-nginx.conf;
    ssl_dhparam /etc/nginx/ssl_conf/ssl-dhparams.pem;
    ssl_certificate /etc/letsencrypt/live/oscript.io/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/oscript.io/privkey.pem;
}

