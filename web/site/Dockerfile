FROM evilbeaver/mono-ru

ENV LANG ru_RU.UTF-8

COPY run.sh /var/run.sh
RUN chmod +x /var/run.sh

EXPOSE 9001

ENTRYPOINT /var/run.sh
