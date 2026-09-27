#!/bin/sh
# Интеграционный тест nginx + OpenTelemetry. Нужен docker compose v2.
#
# Проверяет:
#   1. весь конфиг nginx проходит nginx -t без предупреждений об устаревших директивах;
#   2. входящий traceparent клиента продолжается: trace id тот же, спан nginx —
#      дочерний к спану клиента; родитель с sampled=0 трассу не порождает; без входящего
#      заголовка nginx начинает новую трассу для 1 % запросов (выборка по trace id);
#   3. спан nginx с этим trace id и service.name=nginx доходит до коллектора,
#      а parent-id в заголовке для бэкенда — это id спана nginx (бэкенд встанет к нему дочерним);
#   4. trace id пишется в access log;
#   5. то же для пуша opm по http://hub.oscript.io/push;
#   6. метрики stub_status доходят до коллектора через оверлей monitoring/otelcol-nginx.yaml,
#      опрос не попадает в трассы, а снаружи (через сайты) stub_status не отдаётся;
#   7. спаны по семконвенции OTel HTTP server span: имя — ровно {method} (HTTP для неизвестного
#      метода; маршрут знает только хаб), стабильные атрибуты, путь — в url.path;
#   8. robots.txt hub.oscript.io отдаёт сам nginx (в хаб не ходит), по http — редирект на https;
#   9. ограничение частоты hub.oscript.io: робот по агенту (30 в минуту, всплеск 10; ключ —
#      имя робота, а не адрес и не вся строка агента), любой клиент по адресу (50/с, всплеск 500),
#      не больше 64 одновременных запросов с адреса; отказ — 429 с Retry-After; обычный клиент,
#      мониторинг и зеркала под правило роботов не попадают, другие сайты ограничений не имеют.
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

# check_span_attrs <trace id> <подстрока атрибута>...
# Ищет только внутри блока спана с этим trace id (до следующего "Span #"),
# чтобы не зацепить атрибуты соседних спанов.
check_span_attrs() {
  tid="$1"; shift
  echo "### атрибуты спана $tid"
  block="$($DC logs --no-log-prefix collector | awk -v tid="$tid" '
    $0 ~ ("Trace ID +: " tid) { f = 1 }
    f && /^(Span|ScopeSpans|ResourceSpans) #/ { exit }
    f { print }')"
  [ -n "$block" ] || fail "спан $tid не найден в коллекторе"
  for attr in "$@"; do
    printf '%s\n' "$block" | grep -qF -- "-> $attr" \
      || fail "у спана $tid нет атрибута '$attr'"
  done
  echo "OK: $# атрибутов"
}

# hits <аргументы curl...>: по строке «<код> <Retry-After>» на каждый запрос, тела не печатает.
# Несколько запросов — глоббингом URL ("…?n=[1-40]") или через --next.
hits() {
  $DC run --rm --no-deps -T curl -sk -o /dev/null \
    -w '%{http_code} %header{retry-after}\n' "$@" | tr -d '\r'
}

# count <код> <вывод hits>: сколько запросов ответили этим кодом
count() {
  printf '%s\n' "$2" | grep -c "^$1 " || true
}

# summary <вывод hits>: «200×11 429×29» — для сообщений
summary() {
  printf '%s\n' "$1" | cut -d' ' -f1 | sort | uniq -c | awk '{ printf "%s%s×%s", s, $2, $1; s = " " }'
}

# Каждый ответ 429 обязан нести Retry-After
check_retry_after() {
  name="$1"; out="$2"
  if printf '%s\n' "$out" | grep -Eq '^429 *$'; then
    fail "$name: ответ 429 без заголовка Retry-After"
  fi
}

# Предел по адресу (50/с, всплеск 500) восстанавливает всплеск за 10 с. Адрес контейнера curl
# между запусками может повториться, поэтому проверка, считающая запросы по адресу, начинается
# после паузы — чтобы не донашивать остаток соседней проверки. Роботов разводят разные агенты.
rest_addr_limit() { sleep 11; }

hub_https() { hits --connect-to hub.oscript.io:443:nginx:443 "$@"; }
hub_http()  { hits --connect-to hub.oscript.io:80:nginx:80 "$@"; }

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

check_request "POST http://hub.oscript.io/push с traceparent клиента" \
  "00-1af7651916cd43dd8448eb211c80319c-c7ad6b7169203331-01" \
  --connect-to hub.oscript.io:80:nginx:80 \
  -X POST --data 'x' \
  http://hub.oscript.io/push

echo "### родитель с sampled=0: трассы нет"
UNSAMPLED_TRACE_ID=2af7651916cd43dd8448eb211c80319c
body="$($DC run --rm --no-deps curl -sSk \
  -H "traceparent: 00-${UNSAMPLED_TRACE_ID}-${CLIENT_SPAN_ID}-00" \
  --connect-to hub.oscript.io:443:nginx:443 https://hub.oscript.io/)" \
  || fail "родитель sampled=0: запрос не прошёл"
tp="$(traceparent_of "$body")"
if echo "$tp" | grep -Eq -- '-[0-9a-f][13579bdf]$'; then
  fail "родитель sampled=0, а бэкенду ушёл sampled-заголовок: $tp"
fi

echo "### без traceparent: выборка 1 %"
# 1000 запросов одним curl (глоббинг URL): ждём около 10 трасс. Ноль — выборка не работает
# (вероятность нуля при исправной — 4e-5), больше 40 — доля заметно выше заявленной.
# Темп — 30 в секунду, ниже предела hub.oscript.io на адрес (50/с): проба ходит как обычный
# клиент и не опирается на всплеск (иначе остаток после соседних проверок решал бы, сколько
# запросов получат 429). Каждый код ответа — 200, иначе проба мерила бы не то.
codes="$($DC run --rm --no-deps -T curl -sk -o /dev/null -w '%{http_code}\n' --rate 30/s \
  --connect-to hub.oscript.io:443:nginx:443 \
  "https://hub.oscript.io/ratio-probe?n=[1-1000]" | tr -d '\r')" \
  || fail "выборка: запросы не прошли"
not_ok="$(printf '%s\n' "$codes" | grep -vc '^200$' || true)"
[ "$not_ok" -eq 0 ] || fail "выборка: $not_ok из 1000 запросов пробы ответили не 200"
sleep 7
sampled="$($DC logs --no-log-prefix collector | grep -c 'url.path: Str(/ratio-probe)' || true)"
[ "$sampled" -ge 1 ] || fail "выборка: из 1000 запросов без traceparent не выбрана ни одна трасса"
[ "$sampled" -le 40 ] || fail "выборка: из 1000 запросов выбрано $sampled — это не 1 %"
echo "OK: выбрано $sampled из 1000"

if $DC logs --no-log-prefix collector | grep -Eq "Trace ID +: $UNSAMPLED_TRACE_ID"; then
  fail "родитель sampled=0, а спан nginx дошёл до коллектора"
fi
echo "OK: unsampled родитель не трассируется"

$DC logs --no-log-prefix collector | grep -q 'service.name: Str(nginx)' \
  || fail "service.name у спанов nginx не nginx"

# Имя спана nginx — ровно {method}: маршрут знает только хаб (он есть в спане openhub),
# а путь в имени раздул бы span-metrics в Tempo. Путь — в атрибуте url.path.
check_span_name GET 443 https://hub.oscript.io/ \
  "GET" 11111111111111111111111111111111
check_span_name GET 443 https://hub.oscript.io/download/somepkg/somepkg-1.0.0.ospx \
  "GET" 22222222222222222222222222222222
check_span_name GET 443 https://hub.oscript.io/dev-channel/list.txt \
  "GET" 33333333333333333333333333333333
check_span_name GET 443 https://hub.oscript.io/pools/main/packages/somepkg/versions/1.0.0 \
  "GET" 55555555555555555555555555555555
check_span_name POST 80 http://hub.oscript.io/pools/main/push \
  "POST" 66666666666666666666666666666666
check_span_name POST 80 http://hub.oscript.io/push \
  "POST" 77777777777777777777777777777777
# неизвестный метод: {method} = HTTP, http.request.method = _OTHER
check_span_name FOO 443 https://hub.oscript.io/download/list.txt \
  "HTTP" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# Атрибуты стабильной семконвенции HTTP server span (строками: otel_span_attr не умеет int)
check_span_attrs 22222222222222222222222222222222 \
  'http.request.method: Str(GET)' \
  'http.request.method_original: Str(GET)' \
  'url.path: Str(/download/somepkg/somepkg-1.0.0.ospx)' \
  'url.scheme: Str(https)' \
  'server.address: Str(hub.oscript.io)' \
  'server.port: Str(443)' \
  'network.protocol.version: Str(2)' \
  'http.response.status_code: Str(200)' \
  'user_agent.original: Str(curl/' \
  'client.address: Str(' \
  'network.peer.address: Str(' \
  'network.peer.port: Str('
check_span_attrs 77777777777777777777777777777777 \
  'http.request.method: Str(POST)' \
  'url.scheme: Str(http)' \
  'server.port: Str(80)' \
  'network.protocol.version: Str(1.1)'
check_span_attrs aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  'http.request.method: Str(_OTHER)' \
  'http.request.method_original: Str(FOO)'

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

echo "### robots.txt отдаёт nginx"
resp="$($DC run --rm --no-deps -T curl -sk -i \
  --connect-to hub.oscript.io:443:nginx:443 https://hub.oscript.io/robots.txt | tr -d '\r')" \
  || fail "robots.txt: запрос не прошёл"
printf '%s\n' "$resp" | head -n1 | grep -q '^HTTP/[0-9.]* 200' \
  || fail "robots.txt: не 200. Ответ: $resp"
printf '%s\n' "$resp" | grep -iq '^content-type: text/plain' \
  || fail "robots.txt: не text/plain. Ответ: $resp"
for line in 'User-agent: *' 'Disallow: /api/' 'Disallow: /download/'; do
  printf '%s\n' "$resp" | grep -qxF "$line" || fail "robots.txt: нет строки '$line'. Ответ: $resp"
done
# бэкенд whoami отвечает эхом запроса — его следов в robots.txt быть не должно
if printf '%s\n' "$resp" | grep -Eq '^(Hostname:|GET /robots.txt|X-Real-Ip:)'; then
  fail "robots.txt: запрос дошёл до хаба. Ответ: $resp"
fi
# по http — тот же редирект на https, что и у всего сайта
redirect="$($DC run --rm --no-deps -T curl -s -o /dev/null -w '%{http_code} %{redirect_url}' \
  --connect-to hub.oscript.io:80:nginx:80 http://hub.oscript.io/robots.txt)"
[ "$redirect" = "301 https://hub.oscript.io/robots.txt" ] \
  || fail "robots.txt по http: ждали 301 на https, пришло '$redirect'"
echo "OK: robots.txt"

PERPLEXITY='Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; PerplexityBot/1.0; +https://perplexity.ai/perplexitybot)'
PERPLEXITY_NEXT='Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; PerplexityBot/1.1; +https://perplexity.ai/perplexitybot)'
GPTBOT='Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.2; +https://openai.com/gptbot)'
FACEBOOK='facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)'

rest_addr_limit
echo "### робот по агенту: 30 в минуту, всплеск 10"
# 40 быстрых запросов: всплеск 10 плюс один — 200, остальное — 429
out="$(hub_https -A "$PERPLEXITY" "https://hub.oscript.io/robot-probe?n=[1-40]")"
ok="$(count 200 "$out")"; limited="$(count 429 "$out")"
[ "$ok" -ge 1 ] && [ "$limited" -ge 20 ] \
  || fail "робот: ждали и 200, и не меньше 20 ответов 429, пришло $(summary "$out")"
check_retry_after "робот" "$out"
echo "OK: $(summary "$out"), Retry-After: $(printf '%s\n' "$out" | sed -n 's/^429 //p' | head -n1)"

echo "### тот же робот с другой строкой агента — бюджет общий"
# ключ — имя робота: новая версия в строке агента не даёт нового всплеска
out="$(hub_https -A "$PERPLEXITY_NEXT" "https://hub.oscript.io/robot-probe?n=[1-10]")"
limited="$(count 429 "$out")"
[ "$limited" -ge 5 ] \
  || fail "робот: другая версия агента получила свой всплеск, пришло $(summary "$out")"
echo "OK: $(summary "$out")"

echo "### робот без «bot» в имени (facebookexternalhit)"
out="$(hub_https -A "$FACEBOOK" "https://hub.oscript.io/robot-probe?n=[1-20]")"
ok="$(count 200 "$out")"; limited="$(count 429 "$out")"
[ "$ok" -ge 1 ] && [ "$limited" -ge 5 ] \
  || fail "facebookexternalhit: ждали и 200, и 429, пришло $(summary "$out")"
echo "OK: $(summary "$out")"

echo "### робот на пуше по http — ограничение и на http-сервере сайта"
# Редирект http → https ограничением не проверить: return срабатывает раньше limit_req,
# и стоит nginx столько же, сколько отказ. В хаб по http ходит только пуш — его и проверяем.
out="$(hub_http -A "$GPTBOT" "http://hub.oscript.io/push?n=[1-40]")"
ok="$(count 200 "$out")"; limited="$(count 429 "$out")"
[ "$ok" -ge 1 ] && [ "$limited" -ge 20 ] \
  || fail "робот на пуше по http: ждали и 200, и не меньше 20 ответов 429, пришло $(summary "$out")"
check_retry_after "робот на пуше по http" "$out"
echo "OK: $(summary "$out")"

echo "### другие сайты не ограничены"
# Тот же робот, чей бюджет на хабе только что исчерпан, на grafana.oscript.io не упирается.
# Бэкенда Grafana на стенде нет (ответ 502) — важно лишь, что это не 429.
out="$(hits --connect-to grafana.oscript.io:443:nginx:443 -A "$PERPLEXITY" \
  "https://grafana.oscript.io/robot-probe?n=[1-40]")"
[ "$(count 429 "$out")" -eq 0 ] \
  || fail "grafana.oscript.io: ограничение хаба задело чужой сайт, пришло $(summary "$out")"
echo "OK: $(summary "$out")"

rest_addr_limit
echo "### мониторинг, зеркала и телефоны — не роботы"
# StatusCake и openhub-proxy исключены явно: исключение обязано победить «bot» в строке.
# Cubot — марка телефонов: «bot» в модели устройства человека роботом не делает.
for ua in \
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 StatusCake' \
  'StatusCakeBot/1.0 (uptime monitoring)' \
  'openhub-proxy' \
  'Mozilla/5.0 (Linux; Android 12; CUBOT KingKong 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
do
  out="$(hub_https -A "$ua" "https://hub.oscript.io/agent-probe?n=[1-40]")"
  [ "$(count 429 "$out")" -eq 0 ] && [ "$(count 200 "$out")" -eq 40 ] \
    || fail "агент '$ua' попал под правило роботов: $(summary "$out")"
  echo "OK: $(summary "$out") — $ua"
done

rest_addr_limit
echo "### обычный клиент без агента: 250 быстрых запросов — ни одного 429"
out="$(hub_https -H 'User-Agent:' "https://hub.oscript.io/client-probe?n=[1-250]")"
[ "$(count 200 "$out")" -eq 250 ] \
  || fail "обычный клиент: ждали 250 ответов 200, пришло $(summary "$out")"
echo "OK: $(summary "$out")"

rest_addr_limit
echo "### обезумевший клиент: 1000 запросов залпом — всплеск 500, дальше 429"
# 16 параллельных потоков по HTTP/2 — быстрее предела в разы, но ниже предела одновременных.
# Пройти успевают всплеск и то, что набежит по 50/с за время залпа.
out="$(hub_https -H 'User-Agent:' --parallel --parallel-max 16 \
  "https://hub.oscript.io/flood-probe?n=[1-1000]")"
ok="$(count 200 "$out")"; limited="$(count 429 "$out")"
[ "$ok" -ge 500 ] && [ "$limited" -ge 100 ] \
  || fail "обезумевший клиент: ждали не меньше 500 ответов 200 и 100 ответов 429, пришло $(summary "$out")"
check_retry_after "обезумевший клиент" "$out"
echo "OK: $(summary "$out")"

rest_addr_limit
echo "### одновременные запросы с адреса: не больше 64"
# 100 медленных запросов разом (whoami держит ответ 3 с): 64 проходят, остальным — 429
out="$(hub_https -H 'User-Agent:' --parallel --parallel-max 100 \
  "https://hub.oscript.io/slow-probe?wait=3s&n=[1-100]")"
ok="$(count 200 "$out")"; limited="$(count 429 "$out")"
[ "$ok" -ge 1 ] && [ "$ok" -le 64 ] && [ "$limited" -ge 30 ] \
  || fail "одновременные: ждали не больше 64 ответов 200 и не меньше 30 ответов 429, пришло $(summary "$out")"
check_retry_after "одновременные" "$out"
echo "OK: $(summary "$out")"

echo "nginx otel test OK."
