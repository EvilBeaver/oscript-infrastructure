server {
   listen 80;

   root /var/www/oscript.io;
   server_name oscript.io www.oscript.io;

   location / {
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host $host;
        proxy_pass http://site:5000;
   }
}
