#!/bin/sh
mc alias set health http://127.0.0.1:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" || exit 1
mc ready health || exit 1
