server {
   listen 80;

   root /var/www/web.oscript.io;
   index index.html index.htm

   server_name web.oscript.io;
    
   location / {
       alias /var/www/web.oscript.io
   }
}