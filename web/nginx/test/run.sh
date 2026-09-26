#!/bin/sh
# Интеграционный тест nginx + OpenTelemetry. Нужен docker compose v2.
#
# Проверяет:
#   1. весь конфиг nginx проходит nginx -t;
#   2. в бэкенд уходит свежий W3C traceparent (клиентский перезаписан, а не принят);
#   3. спан nginx с этим trace id и service.name=nginx доходит до коллектора,
#      а parent-id из traceparent — это id спана nginx (бэкенд встанет к нему дочерним);
#   4. trace id пишется в access log;
#   5. то же для пуша opm по http://hub.oscript.io/push.
set -eu
cd "$(dirname "$0")"

DC="docker compose"
CLIENT_TRACE_ID=0af7651916cd43dd8448eb211c80319c
CLIENT_TRACEPARENT="00-${CLIENT_TRACE_ID}-b7ad6b7169203331-01"

cleanup() { $DC down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  echo "--- nginx" >&2;     $DC logs --no-log-prefix nginx >&2 || true
  echo "--- collector" >&2; $DC logs --no-log-prefix collector >&2 || true
  exit 1
}

# Вытаскивает traceparent из ответа whoami ("Traceparent: 00-<trace>-<span>-<flags>")
traceparent_of() {
  printf '%s\n' "$1" | tr -d '\r' | sed -n 's/^Traceparent: //p' | head -n1
}

# Ждёт, пока коллектор напечатает спан (экспорт nginx идёт пачками раз в 5 секунд)
wait_collector() {
  pattern="$1"
  i=0
  while [ $i -lt 30 ]; do
    $DC logs --no-log-prefix collector 2>/dev/null | grep -Eq "$pattern" && return 0
    i=$((i + 1)); sleep 1
  done
  return 1
}

check_request() {
  name="$1"; shift
  echo "### $name"
  body="$($DC run --rm --no-deps curl -sS "$@")" || fail "$name: запрос не прошёл"

  tp="$(traceparent_of "$body")"
  [ -n "$tp" ] || fail "$name: бэкенд не получил traceparent. Ответ: $body"
  echo "$tp" | grep -Eq '^00-[0-9a-f]{32}-[0-9a-f]{16}-01$' \
    || fail "$name: traceparent не по W3C или не sampled: $tp"

  trace_id="$(echo "$tp" | cut -d- -f2)"
  span_id="$(echo "$tp" | cut -d- -f3)"
  [ "$trace_id" != "$CLIENT_TRACE_ID" ] \
    || fail "$name: nginx принял trace id клиента вместо своего"

  wait_collector "Trace ID +: $trace_id" \
    || fail "$name: спан с trace id $trace_id не дошёл до коллектора"
  $DC logs --no-log-prefix collector | grep -Eq "^ +ID +: $span_id" \
    || fail "$name: parent-id $span_id из traceparent не совпал с id спана nginx"

  $DC logs --no-log-prefix nginx | grep -q "$trace_id" \
    || fail "$name: trace id $trace_id не попал в access log"

  echo "OK: $tp"
}

echo "### nginx -t"
$DC run --rm certs >/dev/null
$DC run --rm --no-deps nginx nginx -t || fail "nginx -t"

$DC up -d nginx backend collector

# nginx поднимается не мгновенно — ждём ответа от сайта (default_server рвёт соединение, его не спрашиваем)
i=0
until [ "$($DC run --rm --no-deps curl -sk -o /dev/null -w '%{http_code}' \
          --connect-to hub-new.oscript.io:443:nginx:443 https://hub-new.oscript.io/ 2>/dev/null)" = "200" ]; do
  i=$((i + 1)); [ $i -lt 30 ] || fail "nginx не поднялся"; sleep 1
done

check_request "https://hub-new.oscript.io/" \
  -k --connect-to hub-new.oscript.io:443:nginx:443 \
  -H "traceparent: $CLIENT_TRACEPARENT" \
  https://hub-new.oscript.io/

check_request "POST http://hub.oscript.io/push" \
  --connect-to hub.oscript.io:80:nginx:80 \
  -X POST --data 'x' \
  http://hub.oscript.io/push

$DC logs --no-log-prefix collector | grep -q 'service.name: Str(nginx)' \
  || fail "service.name у спанов nginx не nginx"

echo "nginx otel test OK."
