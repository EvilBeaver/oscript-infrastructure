server {
   listen 80;

   root /var/www/old.oscript.io;
   index index.html index.htm default.aspx Default.aspx;

   #rewrite_log on;
   server_name old.oscript.io;

   location /content {
        alias /var/www/old.oscript.io/Content;
   }

   location / {
       fastcgi_index Home;
       fastcgi_pass monoserver:9001;
       include /etc/nginx/fastcgi_params;
   }
}
