#!/bin/sh
# Интеграционный тест метрик хоста. Нужен docker compose v2, Linux-хост с Docker.
#
# Проверяет, что сервис hostmetrics из docker-compose.yml:
#   1. шлёт по OTLP метрики хоста: CPU, загрузка, память, диски, файловые системы, сеть;
#   2. помечает их host.name из OTEL_HOST_NAME;
#   3. не тащит виртуальные ФС (overlay-слои Docker);
#   4. видит сеть хоста, а не контейнера: у хоста Docker есть интерфейс docker0, в контейнере — нет.
set -eu
cd "$(dirname "$0")"

DC="docker compose"
# extends читает корневой docker-compose.yml целиком, а там есть обязательные переменные
export GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-test}"

cleanup() { $DC down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  echo "--- hostmetrics" >&2; $DC logs --no-log-prefix hostmetrics >&2 || true
  exit 1
}

sink_logs() { $DC logs --no-log-prefix sink 2>/dev/null; }

# Ждёт строку в логе sink (первый сбор — через секунду после старта, экспорт — пачкой)
wait_sink() {
  i=0
  while [ $i -lt 60 ]; do
    sink_logs | grep -qF -- "$1" && return 0
    i=$((i + 1)); sleep 1
  done
  return 1
}

$DC up -d

for metric in system.cpu.time system.cpu.load_average.1m system.memory.usage \
              system.paging.usage system.disk.io system.filesystem.usage system.network.io; do
  wait_sink "Name: $metric" || fail "метрика $metric не дошла"
  echo "OK: $metric"
done

sink_logs | grep -qF -- "-> host.name: Str(test-host)" \
  || fail "у метрик нет host.name=test-host"
echo "OK: host.name"

if sink_logs | grep -qF -- "-> type: Str(overlay)"; then
  fail "в system.filesystem.* попали overlay-слои Docker"
fi
echo "OK: без overlay"

sink_logs | grep -qF -- "-> device: Str(docker0)" \
  || fail "в сетевых метриках нет docker0 — скрейпер видит сеть контейнера, а не хоста"
echo "OK: сеть хоста"

echo "hostmetrics test OK."
