FROM debian:bullseye-slim

ARG MINIO_DEB_URL=https://dl.min.io/server/minio/release/linux-amd64/archive/minio.deb
ARG MC_URL=https://dl.min.io/client/mc/release/linux-amd64/mc

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSLo /tmp/minio.deb "${MINIO_DEB_URL}" \
  && apt-get update \
  && apt-get install -y --no-install-recommends /tmp/minio.deb \
  && rm -f /tmp/minio.deb \
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
