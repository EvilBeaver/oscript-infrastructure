server {
   listen 80;

   root /var/www/beta.oscript.io;
   server_name beta.oscript.io;

   location / {
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;
        set target_url="http://site-dev:5000";
        proxy_pass $target_url; 
   }
}