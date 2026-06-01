#!/bin/sh
set -e

if [ "$#" -eq 0 ]; then
  set -- server /data --console-address ":9001"
fi

if [ ! -f /data/.minio-bootstrap-done ]; then
  echo "First start: initializing MinIO data..."
  minio "$@" &
  MINIO_PID=$!

  cleanup() {
    if kill -0 "$MINIO_PID" 2>/dev/null; then
      kill "$MINIO_PID" 2>/dev/null || true
      wait "$MINIO_PID" 2>/dev/null || true
    fi
  }
  trap cleanup EXIT INT TERM

  /usr/local/bin/bootstrap.sh
  cleanup
  trap - EXIT INT TERM
fi

exec minio "$@"
