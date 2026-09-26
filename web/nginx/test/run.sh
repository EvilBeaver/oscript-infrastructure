#!/bin/sh
# Интеграционный тест nginx + OpenTelemetry. Нужен docker compose v2.
#
# Проверяет:
#   1. весь конфиг nginx проходит nginx -t без предупреждений об устаревших директивах;
#   2. входящий traceparent клиента продолжается: trace id тот же, спан nginx —
#      дочерний к спану клиента; без входящего заголовка nginx начинает новую трассу;
#   3. спан nginx с этим trace id и service.name=nginx доходит до коллектора,
#      а parent-id в заголовке для бэкенда — это id спана nginx (бэкенд встанет к нему дочерним);
#   4. trace id пишется в access log;
#   5. то же для пуша opm по http://hub.oscript.io/push.
set -eu
cd "$(dirname "$0")"

DC="docker compose"
CLIENT_TRACE_ID=0af7651916cd43dd8448eb211c80319c
CLIENT_SPAN_ID=b7ad6b7169203331
CLIENT_TRACEPARENT="00-${CLIENT_TRACE_ID}-${CLIENT_SPAN_ID}-01"

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

# check_request <имя> <traceparent клиента или ""> <аргументы curl...>
check_request() {
  name="$1"; client_tp="$2"; shift 2
  echo "### $name"
  if [ -n "$client_tp" ]; then
    body="$($DC run --rm --no-deps curl -sS -H "traceparent: $client_tp" "$@")" \
      || fail "$name: запрос не прошёл"
  else
    body="$($DC run --rm --no-deps curl -sS "$@")" || fail "$name: запрос не прошёл"
  fi

  tp="$(traceparent_of "$body")"
  [ -n "$tp" ] || fail "$name: бэкенд не получил traceparent. Ответ: $body"
  echo "$tp" | grep -Eq '^00-[0-9a-f]{32}-[0-9a-f]{16}-01$' \
    || fail "$name: traceparent не по W3C или не sampled: $tp"

  trace_id="$(echo "$tp" | cut -d- -f2)"
  span_id="$(echo "$tp" | cut -d- -f3)"

  if [ -n "$client_tp" ]; then
    client_trace_id="$(echo "$client_tp" | cut -d- -f2)"
    client_span_id="$(echo "$client_tp" | cut -d- -f3)"
    [ "$trace_id" = "$client_trace_id" ] \
      || fail "$name: trace id клиента $client_trace_id не дошёл до бэкенда, пришёл $trace_id"
    [ "$span_id" != "$client_span_id" ] \
      || fail "$name: parent-id не заменён на спан nginx — бэкенд встанет мимо nginx"
    wait_collector "Parent ID +: $client_span_id" \
      || fail "$name: спан nginx не дочерний к спану клиента $client_span_id"
  else
    [ "$trace_id" != "$CLIENT_TRACE_ID" ] \
      || fail "$name: без входящего заголовка nginx должен начать новую трассу"
  fi

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
nginx_t="$($DC run --rm --no-deps nginx nginx -t 2>&1)" || { echo "$nginx_t" >&2; fail "nginx -t"; }
echo "$nginx_t"
if echo "$nginx_t" | grep -q deprecated; then
  fail "в конфиге устаревшие директивы"
fi

$DC up -d nginx backend collector

# nginx поднимается не мгновенно — ждём ответа от сайта (default_server рвёт соединение, его не спрашиваем)
i=0
until [ "$($DC run --rm --no-deps curl -sk -o /dev/null -w '%{http_code}' \
          --connect-to hub-new.oscript.io:443:nginx:443 https://hub-new.oscript.io/ 2>/dev/null)" = "200" ]; do
  i=$((i + 1)); [ $i -lt 30 ] || fail "nginx не поднялся"; sleep 1
done

check_request "https://hub-new.oscript.io/ с traceparent клиента" "$CLIENT_TRACEPARENT" \
  -k --connect-to hub-new.oscript.io:443:nginx:443 \
  https://hub-new.oscript.io/

check_request "POST http://hub.oscript.io/push без traceparent" "" \
  --connect-to hub.oscript.io:80:nginx:80 \
  -X POST --data 'x' \
  http://hub.oscript.io/push

$DC logs --no-log-prefix collector | grep -q 'service.name: Str(nginx)' \
  || fail "service.name у спанов nginx не nginx"

echo "nginx otel test OK."
