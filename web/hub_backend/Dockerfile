FROM ubuntu:16.04

# Installing ru-locale support
RUN apt-get clean && apt-get update && apt-get -y install locales locales-all
ENV LANG ru_RU.UTF-8
RUN locale-gen ru_RU && locale-gen ru_RU.UTF-8 \
    && update-locale LANG=ru_RU.UTF-8

# Installing requiered packages
RUN apt-get update && apt-get install -y \
    apache2 \
    mono-complete \
    tzdata \
    wget

# Installing oscript
RUN wget http://oscript.io/downloads/1_0_16/deb
RUN dpkg -i deb

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
