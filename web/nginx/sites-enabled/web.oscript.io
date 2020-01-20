server {
   listen 80;
   server_name web.oscript.io;

   location / {
    root /var/www/web.oscript.io;
    index index.html;
    try_files $uri $uri/ =404;
   }
}