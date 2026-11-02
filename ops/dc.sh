#!/bin/sh
# Обёртка docker compose: корень проекта и .env задаются явно (см. compose/node_*.compose.yaml).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec docker compose --project-directory "$ROOT" --env-file "$ROOT/.env" "$@"
