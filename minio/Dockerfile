FROM debian:bullseye-slim

# dl.min.io отдаёт 410; бинарники — с GitHub Releases (последний релиз с assets).
ARG MINIO_URL=https://github.com/minio/minio/releases/download/RELEASE.2025-09-07T16-13-09Z/minio.linux-amd64.RELEASE.2025-09-07T16-13-09Z
ARG MC_URL=https://github.com/minio/mc/releases/download/RELEASE.2025-08-13T08-35-41Z/mc.linux-amd64.RELEASE.2025-08-13T08-35-41Z

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSLo /usr/local/bin/minio "${MINIO_URL}" \
  && chmod +x /usr/local/bin/minio \
  && curl -fsSLo /usr/bin/mc "${MC_URL}" \
  && chmod +x /usr/bin/mc \
  && ln -sf /usr/local/bin/minio /usr/bin/minio

COPY policies/ /etc/minio/policies/
COPY bootstrap.sh /usr/local/bin/bootstrap.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod +x /usr/local/bin/bootstrap.sh /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["server", "/data", "--console-address", ":9001"]
