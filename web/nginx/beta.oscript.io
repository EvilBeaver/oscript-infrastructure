server {
   listen 80;

   root /var/www/beta.oscript.io;
   server_name beta.oscript.io;

   location / {
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host $host;
        proxy_pass http://site-dev:5005;
   }
}