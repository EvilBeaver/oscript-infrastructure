#!/bin/sh
set -e

: "${MC_HOST_minio:?Set MC_HOST_minio=http://<access>:<secret>@minio:9000}"

BUCKET="jenkins-artifacts"
OBJECT="smoke-$(date +%s).txt"
CONTENT="minio-smoke-test"

export MC_HOST_smoke="${MC_HOST_minio}"

echo "Put ${BUCKET}/${OBJECT}..."
printf '%s' "$CONTENT" | mc pipe "smoke/${BUCKET}/${OBJECT}"

echo "Get ${BUCKET}/${OBJECT}..."
got="$(mc cat "smoke/${BUCKET}/${OBJECT}")"
if [ "$got" != "$CONTENT" ]; then
  echo "Content mismatch: expected '${CONTENT}', got '${got}'" >&2
  exit 1
fi

echo "Delete ${BUCKET}/${OBJECT}..."
mc rm "smoke/${BUCKET}/${OBJECT}"

echo "Smoke test OK."
