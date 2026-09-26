# Скрипты поддержки инфраструктуры oscript.io

## Вот ду ви вонт

* Коммит в ветку
* Сборка на этой ветке
* Прогон тестов из этой ветки
* Формирование артефактов
* Взять актуальные пакеты из hub.oscript.io/dev-channel и прогнать их тесты на собранном артефакте
    * под Windows
    * под Linux
* Если ветка была develop - положить артефакты в ночную сборку для скачивания на сайте
* Если ветка была master
  * Взять актуальные пакеты из hub.oscript.io/dev-channel и прогнать их тесты на собранном артефакте
    * под Windows
    * под Linux
  * положить артефакты в стабильную сборку на сайте
  * опубликовать артефакты в релизах github
  * опубликовать пакеты Nuget
  * обновить документацию на сайте (лежит в артефактах)
  
## Вот ду ви вонт по библиотеке пакетов
  
* Коммит в репо пакета
* Прогон тестов пакета на develop движке (для коммита в dev)
* Прогон тестов пакета на стабильном движке (для коммита в master или release/\*), если в packagedef не указана нестабильная версия среды.
* Сборка ospx
   * Публикация в dev канале хаба, если это ветка dev
   * Публикация в основном канале хаба, если это ветка master.
  
Этот документ можно обсуждать и предлагать к нему правки.

## OpenHub — hub-new.oscript.io

Новый хаб пакетов ([OpenHub](https://github.com/Segate-ekb/openhub)) живёт в том же `docker-compose.yml`:

| Сервис | Что это |
| --- | --- |
| `openhub` | сам хаб, образ `segateekb/openhub`; |
| `openhub_db` | PostgreSQL хаба;|
| `lgtm` | мониторинг хаба одним контейнером (`grafana/otel-lgtm`), Grafana — grafana.oscript.io; дашборд хаба — в `monitoring/` |

Файлы пакетов хаб хранит в общем MinIO

### Первый запуск на работающем сервере

1. Добавить в `.env` переменные из [`openhub.env.example`](openhub.env.example).
2. Завести DNS-записи `hub-new.oscript.io` и `grafana.oscript.io` на сервер.
3. Выпустить сертификаты и пересобрать nginx с новыми сайтами:

   ```bash
   ./add-letsencrypt-domain.sh hub-new.oscript.io
   ./add-letsencrypt-domain.sh grafana.oscript.io
   ```
4. Завести в MinIO бакет `openhub` и учётку хаба с ключами `OPENHUB_S3_ACCESS_KEY` /
   `OPENHUB_S3_SECRET_KEY` из `.env` — руками, один раз.
5. Поднять хаб — база и мониторинг поднимутся сами:

6. Сразу открыть <https://hub-new.oscript.io/setup> и завести первого администратора.

### Перенос данных из старого хаба

Зеркалирование привозит из opm-hub только имена, версии и файлы пакетов — дат публикации
в его протоколе нет, поэтому у всех перенесённых версий дата равна дню прогона зеркала.
Вернуть настоящие даты и дописать метаданные, которых нет в манифестах, разовым запросом
между двумя базами: [`openhub-migration/`](openhub-migration/README.md).

## Трассировка nginx

nginx собран из официального образа с модулем [ngx_otel_module](https://nginx.org/ru/docs/ngx_otel_module.html)
и шлёт спаны в `lgtm` (OTLP/gRPC, порт 4317) — трассы видны в Grafana рядом с трассами хаба.
Входящий W3C `traceparent` клиента nginx продолжает (trace id сохраняется), без него начинает
новую трассу; в бэкенд уходит тот же trace id с parent-id спана nginx, так что спаны OpenHub
встают дочерними к спану nginx; `trace_id` пишется и в access log. Настройки — `web/nginx/conf.d/otel.conf`.
Спаны — по [семконвенции OTel для HTTP server span](https://opentelemetry.io/docs/specs/semconv/http/http-spans/):
имя `{method} {route}` для известных маршрутов хаба (`GET /download/{name}/{file}`, `POST /pools/{pool}/push`),
иначе просто `{method}`; стабильные атрибуты (`http.request.method`, `url.path`, `server.address`, …)
пишутся вместе со старыми, которые модуль ставит сам. Чего модуль сделать не даёт — в комментариях `otel.conf`.

Метрики соединений и запросов (`nginx.connections_*`, `nginx.requests`; в Prometheus — с префиксом `nginx_`) коллектор `lgtm` снимает
со `stub_status` на внутреннем порту 8080 (`web/nginx/sites-enabled/status`, наружу не публикуется);
receiver подключён оверлеем `monitoring/otelcol-nginx.yaml`. RPS, ошибки и латентность по трассам
строит Tempo в `lgtm`: `traces_spanmetrics_*{service="nginx"}`.

Проверка конфига, трассировки и метрик (нужен docker compose v2):

```bash
./web/nginx/test/run.sh
```