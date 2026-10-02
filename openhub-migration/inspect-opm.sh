#!/bin/bash

# Разведка перед переносом: что на самом деле лежит в базе старого хаба —
# какая база, какие схемы, таблицы и колонки. Ничего не меняет, только читает.
#
#   ./openhub-migration/inspect-opm.sh
#
# Пароль не печатается: из строки соединения хаба берутся только host, database
# и username.

set -euo pipefail

cd "$(dirname "$0")/.."

if docker compose version >/dev/null 2>&1; then
  compose="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  compose="docker-compose"
else
  echo 'Не найден ни docker compose, ни docker-compose' >&2
  exit 1
fi

if [ -z "$($compose ps -q opm_hub_db)" ]; then
  echo 'Сервис opm_hub_db не поднят' >&2
  exit 1
fi

# Первым аргументом — база, дальше аргументы psql.
opm_psql() {
  $compose exec -T opm_hub_db sh -c \
    'db="$1"; shift; PGPASSWORD="$POSTGRES_PASSWORD" exec psql -v ON_ERROR_STOP=1 \
       -U "$POSTGRES_USER" -d "$db" "$@"' psql "$@"
}

echo '### Куда ходит сам хаб (из OSWEB_Database__ConnectionString, без пароля)'
if [ -n "$($compose ps -q opm_hub)" ]; then
  $compose exec -T opm_hub sh -c 'printf "%s\n" "${OSWEB_Database__ConnectionString:-}"' \
    | tr ';' '\n' \
    | grep -iE '^[[:space:]]*(host|database|username|port)=' \
    || echo '(строка соединения пуста или в другом формате)'
else
  echo '(сервис opm_hub не поднят — пропускаю)'
fi

echo
echo '### Под кем и куда подключается перенос'
opm_psql postgres -Atc "SELECT 'пользователь: ' || current_user"

echo
echo '### Базы на сервере'
databases=$(opm_psql postgres -Atc \
  "SELECT datname FROM pg_database WHERE NOT datistemplate AND datallowconn ORDER BY datname")
echo "$databases"

for db in $databases; do
  echo
  echo "### Таблицы и колонки в базе $db"
  opm_psql "$db" -Atc "
    SELECT table_schema || ' . ' || table_name || '  ->  '
           || string_agg(column_name, ', ' ORDER BY ordinal_position)
    FROM information_schema.columns
    WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
    GROUP BY table_schema, table_name
    ORDER BY 1" || echo "(в базу $db подключиться не удалось)"
done
