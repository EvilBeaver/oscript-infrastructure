FROM evilbeaver/onescript:1.0.20

# Installing requiered packages
RUN apt-get clean \
	&& apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF \
	&& echo "deb http://download.mono-project.com/repo/debian wheezy main" | tee /etc/apt/sources.list.d/mono-xamarin.list \
	&& apt-get update \
    && apt-get install -y mono-xsp4 \
    && apt-get clean \
	&& rm -rf /var/lib/apt/lists/* /tmp/*

# Copying the necessary files
COPY app /var/xsp

# Installing backend oscript dependencies
WORKDIR /var/xsp
RUN chmod +x /var/xsp/install.sh
RUN /var/xsp/install.sh

EXPOSE 9002
CMD xsp4 --port 9002 --applications=*:9002:/:. --nonstop
