FROM minio/mc:latest

COPY smoke.sh /smoke.sh
RUN chmod +x /smoke.sh

ENTRYPOINT ["/smoke.sh"]
