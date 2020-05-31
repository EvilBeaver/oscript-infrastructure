server {
    listen 80;
    listen [::]:80;
    server_name hub.oscript.io;
    
    client_max_body_size 50M;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # временное решение для пуша
    location /push {
        
        root /var/www/hub.oscript.io; 
        
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Server $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;  
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_redirect off;
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host $host;
        proxy_pass http://opm_hub:5000;

    }

    location / {
        return 302 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name hub.oscript.io;
    root /var/www/hub.oscript.io;

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

    location / {
        gzip off;
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;
        proxy_pass http://opm_hub:5000;
    }

    include /etc/nginx/ssl_conf/options-ssl-nginx.conf;
    ssl_dhparam /etc/nginx/ssl_conf/ssl-dhparams.pem;
    ssl_certificate /etc/letsencrypt/live/hub.oscript.io/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/hub.oscript.io/privkey.pem;
}

