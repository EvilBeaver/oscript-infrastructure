server {
   listen 80;

   root /var/www/oscript.io;
   index index.html index.htm default.aspx Default.aspx;

   #rewrite_log on;
   server_name oscript.io www.oscript.io;

   location /content {
        alias /var/www/oscript.io/Content;
   }

   location / {
       fastcgi_index Home;
       fastcgi_pass monoserver:9001;
       include /etc/nginx/fastcgi_params;
   }
}
