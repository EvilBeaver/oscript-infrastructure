FROM jenkins/jenkins:latest

# для автообновления инстанса
# добавить volume для /usr/share/jenkins
#chown jenkins:jenkins /usr/share/jenkins
#chown jenkins:jenkins /usr/share/jenkins/jenkins.war

# slave должен иметь mono
USER root
RUN apt-get clean && apt-get update && \
    apt-key adv --no-tty --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF \
	&& echo "deb http://download.mono-project.com/repo/debian stable-stretch main" | tee /etc/apt/sources.list.d/mono-official.list \
	&& apt-get update \
	&& apt-get -y install mono-complete

# slave должен иметь docker
RUN curl -sSL https://get.docker.com/ | sh \
	&& usermod -a -G docker jenkins

#locales
RUN apt-get -y install locales \
	&& sed -i -e 's/# ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen \
	&& locale-gen
ENV LANG ru_RU.UTF-8
RUN locale -a

# Дополнительные пакеты поставим в отдельный слой, чтобы
# зафиксировать долгую установку mono и не выполнять ее каждый раз при сборке.
RUN apt-get -y install rsync sudo wget \
	&& wget https://oscript.io/downloads/1_7_0/x64/onescript-engine_1.7.0_all.deb \
	&& dpkg -i onescript-engine_1.7.0_all.deb \
	&& rm onescript-engine_1.7.0_all.deb \
	&& curl -L https://github.com/docker/compose/releases/download/1.22.0-rc2/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose \
	&& chmod +x /usr/local/bin/docker-compose

RUN mkdir -p /etc/sudoers.d && \
	echo 'jenkins ALL=(root) NOPASSWD: /usr/bin/rsync' >> /etc/sudoers.d/10-jenkins

COPY daemon.json /etc/docker/daemon.json

USER jenkins
