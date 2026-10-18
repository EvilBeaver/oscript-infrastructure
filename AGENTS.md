# AGENTS.md

Инфраструктура сайта [oscript.io](https://oscript.io) и поддоменов `*.oscript.io` — один сервер, один `docker-compose.yml`.

## Стек

Docker Compose · nginx (образ с `ngx_otel_module`) · Let's Encrypt/certbot · PostgreSQL · MinIO · [OpenHub](https://github.com/Segate-ekb/openhub) · Grafana otel-lgtm · Jenkins · OneScript (бот).

Секреты и пароли — в `.env` в корне (не в git). Образцы: [`openhub.env.example`](openhub.env.example), [`minio/.env.example`](minio/.env.example).

## Карта сервисов

| Сервис compose | Назначение | Домен |
| --- | --- | --- |
| `nginx` | reverse proxy, TLS, OTel, rate limit | все публичные домены |
| `site` | основной сайт | `oscript.io`, `www.oscript.io` |
| `openhub` | хаб пакетов (актуальный) | `hub.oscript.io` |
| `opm_hub` | старый хаб | `hub-old.oscript.io` |
| `jenkins` | CI | `build.oscript.io` |
| `minio` | S3-хранилище артефактов | `s3.oscript.io` |
| `lgtm` | Grafana, Tempo, Loki, Prometheus | `grafana.oscript.io` |
| `hostmetrics` | метрики хоста и контейнеров → `lgtm` | только localhost OTLP |
| `certbot` | автообновление сертификатов | — |
| `s3-sync` | зеркалирование `web_content` во внешний S3 | — |
| `tg_bot` | Telegram-бот | — |

Общий том `web_content` — статика сайта и артефакты старого хаба. Файлы OpenHub — бакет `openhub` в MinIO.

## Структура репозитория

```
docker-compose.yml          # весь стек
web/nginx/                  # образ nginx, sites-enabled, conf.d, snippets, robots, тесты
web/certbot/                # сертификаты (gitignore)
monitoring/                 # дашборды Grafana, otelcol-*, роль grafana_ro, тесты
minio/                      # образ MinIO, bootstrap учёток и бакетов
jenkins/                    # образ Jenkins (mono, docker, onescript)
openhub-migration/          # разовый перенос метаданных opm-hub → OpenHub
S3/                         # rclone-синхронизация во внешнее хранилище
bot/                        # исходники Telegram-бота (образ — внешний)
docker/                     # Dockerfile для сборок в Jenkins
```

Конфиг nginx собирается в образ (`web/nginx/Dockerfile`); после правок `sites-enabled` или `conf.d` — пересборка `nginx`.

## Типовые задачи

### Правки nginx

1. Файлы: `web/nginx/sites-enabled/`, `web/nginx/conf.d/`, `web/nginx/snippets/`, `web/nginx/robots/`.
2. Проверка: `./web/nginx/test/run.sh` (нужен `docker compose` v2).
3. На сервере: `docker-compose build nginx && docker-compose up -d nginx`.

Новый домен и сертификат: `./add-letsencrypt-domain.sh <домен>` — добавить `server`-блок в `sites-enabled` до запуска скрипта.

### OpenHub

Переменные окружения хаба в `docker-compose.yml` (секция `openhub`). Имена ключей: точка настройки → подчёркивание, внутреннее `_` удваивается (`OSHUB_INSTANCE_TRUSTED__PROXIES`).

Первый запуск: переменные из `openhub.env.example` → DNS → сертификаты → бакет и учётка в MinIO → роль `grafana_ro` (`monitoring/grafana-db-role.sql`) → `docker-compose up -d openhub` → `/setup` для первого админа.

Перенос дат и метаданных со старого хаба: [`openhub-migration/README.md`](openhub-migration/README.md).

### Мониторинг

- Дашборды: `monitoring/openhub-dashboard.json`, `monitoring/openhub-reference-dashboard.json`.
- Источник Grafana для каталога хаба: `monitoring/grafana-datasource-openhub-db.yaml` (роль `grafana_ro`, пароль `GRAFANA_DB_PASSWORD`).
- Трассировка nginx: `web/nginx/conf.d/otel.conf`; метрики nginx: `monitoring/otelcol-nginx.yaml`.
- Метрики хоста: `monitoring/otelcol-host.yaml`, сервис `hostmetrics`.
- Проверка: `./monitoring/test/run.sh`.

Схему базы OpenHub меняет сам хаб — после обновления с переименованием таблиц/колонок править SQL в дашбордах и `monitoring/grafana-db-role.sql`.

### MinIO

Bootstrap при старте: `minio/bootstrap.sh`. Политики: `minio/policies/`. Smoke-тест: `minio/test/smoke.sh`.

### hub.oscript.io — robots и лимиты

- `web/nginx/robots/hub.oscript.io.txt` — отдаёт nginx, не хаб.
- Лимиты: `web/nginx/conf.d/hub-limits.conf`, `web/nginx/snippets/hub.oscript.io-limits.conf`.
- HTTP push (`/push`) на hub идёт без редиректа на https — см. `hub.oscript.io` в `sites-enabled`.

## Ограничения

- На сервере — `docker-compose` (v1 CLI), в тестах — `docker compose` v2.
- `hostmetrics` в `network_mode: host`; OTLP `lgtm` опубликован на `127.0.0.1:4317`.
- `Vagrantfile` и `init.sh` — устаревший локальный стенд, не отражают боевой стек.
- `local_backup.sh` — ручной бэкап тома `web_content`, пути захардкожены.

## Указатели

| Тема | Документ |
| --- | --- |
| перенос метаданных opm-hub → OpenHub | [`openhub-migration/README.md`](openhub-migration/README.md) |
| трассировка, robots, rate limit hub | комментарии в `web/nginx/conf.d/otel.conf`, `hub-limits.conf`; тест `web/nginx/test/run.sh` |
| справочный дашборд и роль БД | `monitoring/grafana-db-role.sql`, `monitoring/grafana-datasource-openhub-db.yaml` |
| переменные OpenHub | `openhub.env.example`, секция `openhub` в `docker-compose.yml` |
| переменные MinIO / Jenkins S3 | `minio/.env.example` |
