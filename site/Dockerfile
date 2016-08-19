FROM ubuntu:latest

ENV LANG ru_RU.UTF-8

RUN locale-gen ru_RU && locale-gen ru_RU.UTF-8 \
    && update-locale LANG=ru_RU.UTF-8

RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF \
	&& echo "deb http://download.mono-project.com/repo/debian wheezy main" | sudo tee /etc/apt/sources.list.d/mono-xamarin.list \
	&& sudo apt-get update \
	&& apt-get -y install mono-complete

RUN apt-get -y install mono-fastcgi-server4

VOLUME /var/www/oscript.io

EXPOSE 9002

ENTRYPOINT fastcgi-mono-server4 /applications=oscript.io:/:/var/www/oscript.io /socket=tcp:$IP:9002
