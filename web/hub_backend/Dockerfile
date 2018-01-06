FROM evilbeaver/onescript:1.0.19

# Installing requiered packages
RUN apt-get update && apt-get install -y \
    apache2 \
    && apt-get clean \
	&& rm -rf /var/lib/apt/lists/* /tmp/*

# Copying the necessary files
COPY cgi /var/cgi
RUN chmod +x /var/cgi/push-package.os
COPY packagedef packagedef

# Installing backend oscript dependencies
RUN opm install

# Configuring apache
COPY 000-default.conf /etc/apache2/sites-enabled/000-default.conf
RUN ln -s /etc/apache2/mods-available/cgi.load /etc/apache2/mods-enabled/cgi.load 

# Copy hub secrets file
COPY hub_backend.secret hub_backend.secret

CMD /usr/sbin/apache2ctl -D FOREGROUND
