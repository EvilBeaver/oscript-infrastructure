#!/bin/bash

# Разовый перенос дат и метаданных пакетов из базы старого хаба (opm_hub_db)
# в базу OpenHub (openhub_db). Что именно переносится — в README.md рядом.
#
#   ./openhub-migration/run.sh                 прогон вхолостую: считает и откатывает
#   ./openhub-migration/run.sh --apply         то же самое, но с фиксацией
#   ./openhub-migration/run.sh --pool '*'      не ограничиваться пулом по умолчанию
#   ./openhub-migration/run.sh --touch-changed двигать назад ещё и «Изменена»
#
# Базы живут в разных сетях compose и друг друга не видят, поэтому перенос идёт
# через CSV: выгрузка из старой базы ложится файлом рядом и заливается в новую.

set -euo pipefail

cd "$(dirname "$0")/.."

apply=false
pool=""
touch_changed=false
opm_db=""

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=true ;;
    --pool)
      if [ $# -lt 2 ]; then
        echo "--pool требует значение: имя пула или '*'" >&2
        exit 1
      fi
      pool="$2"
      shift
      ;;
    --touch-changed) touch_changed=true ;;
    --opm-db)
      if [ $# -lt 2 ]; then
        echo "--opm-db требует значение: имя базы старого хаба" >&2
        exit 1
      fi
      opm_db="$2"
      shift
      ;;
    -h|--help)
      sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
  esac
  shift
done

if docker compose version >/dev/null 2>&1; then
  compose="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  compose="docker-compose"
else
  echo 'Не найден ни docker compose, ни docker-compose' >&2
  exit 1
fi

for service in opm_hub_db openhub_db; do
  if [ -z "$($compose ps -q "$service")" ]; then
    echo "Сервис $service не поднят: сначала docker-compose up -d $service" >&2
    exit 1
  fi
done

# Имя базы старого хаба берём из строки соединения самого хаба: у сервера базы
# POSTGRES_DB может быть не задан, а хаб ходит в свою. Пароль отсюда не читается.
if [ -z "$opm_db" ] && [ -n "$($compose ps -q opm_hub)" ]; then
  opm_db=$($compose exec -T opm_hub \
             sh -c 'printf "%s" "${OSWEB_Database__ConnectionString:-}"' \
           | tr ';' '\n' \
           | sed -n 's/^[[:space:]]*[Dd]atabase[[:space:]]*=[[:space:]]*//p' \
           | head -1 | tr -d '\r')
fi

# Логин и пароль берём из окружения самих контейнеров — их туда положил compose,
# разобрав .env своим парсером. Читать .env шеллом нельзя: пароль с пробелом,
# решёткой или $( ) шелл выполнит, а не подставит. Заодно пароль не светится
# в списке процессов хоста: в argv докера его нет.
opm_psql() {
  $compose exec -T opm_hub_db sh -c \
    'db="$1"; shift
     if [ -z "$db" ]; then db="${POSTGRES_DB:-$POSTGRES_USER}"; fi
     PGPASSWORD="$POSTGRES_PASSWORD" exec psql -v ON_ERROR_STOP=1 \
       -U "$POSTGRES_USER" -d "$db" "$@"' psql "$opm_db" "$@"
}

hub_psql() {
  $compose exec -T openhub_db sh -c \
    'PGPASSWORD="$POSTGRES_PASSWORD" exec psql -v ON_ERROR_STOP=1 \
       -U "$POSTGRES_USER" -d "${POSTGRES_DB:-$POSTGRES_USER}" "$@"' psql "$@"
}

csv="openhub-migration/opm-dump-$(date '+%Y%m%d-%H%M%S').csv"

echo "### Выгружаю пакеты и версии из базы старого хаба в $csv ..."
opm_psql -q -f - < openhub-migration/export-opm.sql > "$csv"
echo "### Выгружено строк: $(($(wc -l < "$csv") - 1))"

echo '### Готовлю приёмную таблицу в базе OpenHub ...'
hub_psql -q -f - < openhub-migration/stage-openhub.sql

echo '### Заливаю выгрузку ...'
hub_psql -q -c '\copy opm_import FROM STDIN WITH (FORMAT csv, HEADER true)' < "$csv"

echo '### Считаю перенос ...'
hub_psql -v apply="$apply" -v pool="$pool" -v touch_changed="$touch_changed" \
  -f - < openhub-migration/apply-openhub.sql

if [ "$apply" = true ]; then
  echo "### Готово. Выгрузка осталась в $csv"
else
  echo "### Ничего не записано. Выгрузка осталась в $csv"
fi
