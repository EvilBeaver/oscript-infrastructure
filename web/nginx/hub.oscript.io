server {
	listen 80;
	#listen 443 ssl;

	server_name hub.oscript.io;
	
	root /var/www/hub.oscript.io;
	
	location / {
		allow all;
		autoindex on;
	}

	location /push {
		allow all;
		gzip off;

		client_max_body_size 50M;
		proxy_set_header X-Real-IP  $remote_addr;
		proxy_set_header X-Forwarded-For $remote_addr;
		proxy_set_header Host $host;
		proxy_pass http://hub_backend;
		proxy_temp_file_write_size 100m;
		client_max_body_size 100m;
	}

	#keepalive_timeout   60;
	#ssl_certificate      hub.oscript.crt;
	#ssl_certificate_key  hub.private.key;
	#ssl_protocols SSLv3 TLSv1 TLSv1.1 TLSv1.2;
    	#ssl_ciphers  "RC4:HIGH:!aNULL:!MD5:!kEDH";
	#add_header Strict-Transport-Security 'max-age=604800';
}
