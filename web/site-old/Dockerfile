FROM evilbeaver/mono-ru:5.4

ENV LANG ru_RU.UTF-8

COPY run.sh /var/run.sh
RUN chmod +x /var/run.sh

EXPOSE 9001

ENTRYPOINT /var/run.sh
