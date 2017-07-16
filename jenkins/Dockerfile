FROM jenkins:2.60.1

# для автообновления инстанса
# добавить volume для /usr/share/jenkins
#chown jenkins:jenkins /usr/share/jenkins
#chown jenkins:jenkins /usr/share/jenkins/jenkins.war

# slave должен иметь mono
USER root
RUN apt-get clean && apt-get update && \
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF \
	&& echo "deb http://download.mono-project.com/repo/debian jessie main" | tee /etc/apt/sources.list.d/mono-official.list \
	&& apt-get update \
	&& apt-get -y install mono-complete

# slave должен иметь docker
RUN curl -sSL https://get.docker.com/ | sh \
	&& usermod -a -G docker jenkins

# Дополнительные пакеты поставим в отдельный слой, чтобы
# зафиксировать долгую установку mono и не выполнять ее каждый раз при сборке.
RUN apt-get -y install rsync sudo

RUN mkdir -p /etc/sudoers.d && \
	echo 'jenkins ALL=(root) NOPASSWD: /usr/bin/rsync' >> /etc/sudoers.d/10-jenkins

USER jenkins
