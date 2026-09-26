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
#   5. то же для пуша opm по http://hub.oscript.io/push;
#   6. метрики stub_status доходят до коллектора через оверлей monitoring/otelcol-nginx.yaml,
#      опрос не попадает в трассы, а снаружи (через сайты) stub_status не отдаётся;
#   7. имя спана — "{метод} {шаблон маршрута}", а не сырой путь.
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

# check_span_name <метод> <порт> <url> <ожидаемое имя спана> <trace id, 32 hex>
# Свой trace id на запрос: при propagate он достаётся спану nginx — по нему и ищем спан.
check_span_name() {
  method="$1"; port="$2"; url="$3"; expected="$4"; tid="$5"
  echo "### span name: $method $url"
  $DC run --rm --no-deps curl -sk -o /dev/null -X "$method" \
    --connect-to "hub.oscript.io:$port:nginx:$port" \
    -H "traceparent: 00-${tid}-00f067aa0ba902b7-01" "$url" \
    || fail "$method $url: запрос не прошёл"

  wait_collector "Trace ID +: $tid" \
    || fail "$method $url: спан с trace id $tid не дошёл до коллектора"
  name="$($DC logs --no-log-prefix collector | grep -A4 -E "Trace ID +: $tid" \
          | sed -n 's/^ *Name *: //p' | head -n1)"
  [ "$name" = "$expected" ] \
    || fail "$method $url: имя спана '$name', ожидали '$expected'"
  echo "OK: $name"
}

echo "### nginx -t"
# docker compose run собирает образ, только если его нет, — без явной сборки тест гоняет старый конфиг
$DC build nginx
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
          --connect-to hub.oscript.io:443:nginx:443 https://hub.oscript.io/ 2>/dev/null)" = "200" ]; do
  i=$((i + 1)); [ $i -lt 30 ] || fail "nginx не поднялся"; sleep 1
done

check_request "https://hub.oscript.io/ с traceparent клиента" "$CLIENT_TRACEPARENT" \
  -k --connect-to hub.oscript.io:443:nginx:443 \
  https://hub.oscript.io/

check_request "POST http://hub.oscript.io/push без traceparent" "" \
  --connect-to hub.oscript.io:80:nginx:80 \
  -X POST --data 'x' \
  http://hub.oscript.io/push

$DC logs --no-log-prefix collector | grep -q 'service.name: Str(nginx)' \
  || fail "service.name у спанов nginx не nginx"

# Имя спана — шаблон маршрута, а не сырой путь: иначе span-metrics в Tempo
# получают по серии на каждый файл пакета
check_span_name GET 443 https://hub.oscript.io/ \
  "GET /" 11111111111111111111111111111111
check_span_name GET 443 https://hub.oscript.io/download/somepkg/somepkg-1.0.0.ospx \
  "GET /download/{name}/{file}" 22222222222222222222222222222222
check_span_name GET 443 https://hub.oscript.io/dev-channel/list.txt \
  "GET /dev-channel/list.txt" 33333333333333333333333333333333
check_span_name GET 443 https://hub.oscript.io/api/v1/pools/main/download/somepkg/somepkg-1.0.0.ospx \
  "GET /api/v1/pools/{pool}/download/{name}/{file}" 44444444444444444444444444444444
check_span_name GET 443 https://hub.oscript.io/pools/main/packages/somepkg/versions/1.0.0 \
  "GET /pools/{pool}/packages/*" 55555555555555555555555555555555
check_span_name POST 80 http://hub.oscript.io/pools/main/push \
  "POST /pools/{pool}/push" 66666666666666666666666666666666
check_span_name POST 80 http://hub.oscript.io/push \
  "POST /push" 77777777777777777777777777777777
check_span_name GET 443 https://hub.oscript.io/groups/admins/members \
  "GET /groups/*" 88888888888888888888888888888888

echo "### метрики stub_status"
wait_collector "Name: nginx.connections_accepted" \
  || fail "метрики nginx (stub_status) не дошли до коллектора"
if $DC logs --no-log-prefix collector | grep -q 'http.target: Str(/nginx_status)'; then
  fail "опрос stub_status попал в трассы"
fi

# снаружи, через сайты на 80/443, stub_status не отдаётся
for proto_port in http:80 https:443; do
  proto="${proto_port%:*}"; port="${proto_port#*:}"
  body="$($DC run --rm --no-deps curl -sk \
          --connect-to "hub.oscript.io:$port:nginx:$port" \
          "$proto://hub.oscript.io/nginx_status" 2>/dev/null || true)"
  if echo "$body" | grep -q 'Active connections'; then
    fail "stub_status доступен снаружи: $proto://hub.oscript.io/nginx_status"
  fi
done
echo "OK: stub_status"

echo "nginx otel test OK."
