# AGENTS.md

Инфраструктура [oscript.io](https://oscript.io) и поддоменов `*.oscript.io` — две ноды (A — edge, B — worker), один каталог стека `/opt/oscript`, сборка через модульный Compose и `ops/dc.sh`. Подробный порядок работ — [`.cursor/plans/README.md`](.cursor/plans/README.md).

## Стек

Docker Compose v2 · nginx (образ с `ngx_otel_module`) · Let's Encrypt/certbot · PostgreSQL · MinIO · [OpenHub](https://github.com/Segate-ekb/openhub) · Grafana otel-lgtm · Jenkins · OneScript (бот) · WireGuard между нодами.

Секреты — в `.env` в корне стека (не в git) и в Ansible vault на B (`/opt/oscript-secrets/`). Образцы имён переменных: [`env/node_a.env.example`](env/node_a.env.example), [`env/node_b.env.example`](env/node_b.env.example), [`openhub.env.example`](openhub.env.example), [`minio/.env.example`](minio/.env.example).

## Запуск compose

На каждой ноде из `/opt/oscript`:

- в `.env`: `COMPOSE_PROJECT_NAME=os` и `COMPOSE_FILE=…` (на A до сплита: `compose/node_a.compose.yaml:compose/overrides/colocated.yml`, после сплита — `…/split.yml`, на B: `compose/node_b.compose.yaml`);
- команды: `./ops/dc.sh config`, `./ops/dc.sh up -d`, `./ops/dc.sh build nginx` и т.д.

Корневого `docker-compose.yml` нет. На A после окна переключения бинарь `docker-compose` v1 не используется.

## Карта сервисов

| Сервис compose | Назначение | Домен / доступ |
| --- | --- | --- |
| `nginx` | reverse proxy, TLS, OTel, rate limit | все публичные домены (на A) |
| `site` | основной сайт | `oscript.io`, `www.oscript.io` |
| `openhub` | хаб пакетов | `hub.oscript.io` |
| `jenkins` | CI | `build.oscript.io` |
| `minio` | S3-хранилище артефактов | `s3.oscript.io` (после сплита — на B, прокси с A) |
| `lgtm` | Grafana, Tempo, Loki, Prometheus | `grafana.oscript.io` |
| `hostmetrics` | метрики хоста и контейнеров → OTLP | `network_mode: host` |
| `certbot` | автообновление сертификатов | — |
| `s3-sync` | зеркалирование `web_content` во внешний S3 | — |
| `tg_bot` | Telegram-бот | — |

## Структура репозитория

```
compose/apps/               # тело сервисов
compose/node_a.compose.yaml # сборка A (без minio/lgtm в базе)
compose/node_b.compose.yaml # minio, lgtm, hostmetrics на B
compose/overrides/          # colocated.yml | split.yml
env/                        # образцы .env по нодам
ops/dc.sh                   # обёртка docker compose
ansible/                    # роли, site.yml (inventory и vault вне git)
web/nginx/                  # образ nginx, sites-enabled, тесты
monitoring/                 # дашборды, otelcol-*, тест hostmetrics
minio/  jenkins/  S3/  bot/  docker/
```

Конфиг nginx в образе (`web/nginx/Dockerfile`); после правок `sites-enabled` или `conf.d` — `./ops/dc.sh build nginx && ./ops/dc.sh up -d nginx`.

## Ansible

Control node — **нода B**, пользователь `deploy`. Плейбук: `ansible/site.yml`, конфиг — корневой `ansible.cfg`. Боевой `ansible/inventory.ini` и `vault.yml` на B, в git только образцы.

```bash
cd /opt/oscript
ansible-playbook ansible/site.yml \
  -e @/opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass \
  --tags common
```

Роли, меняющие хост, помечены тегом `never` и без `--tags` не выполняются. В `--tags` передают **только** тег роли (`common`, `firewall`, `wg`, …), без `never`: иначе выполнятся все роли с `never`. На A модули Ansible — `/opt/python3/bin/python3`. Подробности — [`.cursor/plans/04-ansible.md`](.cursor/plans/04-ansible.md).

## Типовые задачи

### Правки nginx

1. Файлы: `web/nginx/sites-enabled/`, `web/nginx/conf.d/`, `web/nginx/snippets/`, `web/nginx/robots/`.
2. Проверка: `./web/nginx/test/run.sh` (нужен `docker compose` v2).
3. На сервере: `./ops/dc.sh build nginx && ./ops/dc.sh up -d nginx`.

Новый домен: блок в `sites-enabled/`, затем `./add-letsencrypt-domain.sh <домен>`.

### OpenHub

Переменные — в `.env` и `compose/apps/openhub.yml` (имена по правилу хаба: точка → `_`, внутреннее `_` удваивается). Первый запуск: образцы env → DNS → certbot → MinIO → роль `grafana_ro` → `./ops/dc.sh up -d openhub` → `/setup`.

Метаданные opm-hub уже перенесены: [`openhub-migration/README.md`](openhub-migration/README.md).

### Мониторинг

- Дашборды: `monitoring/openhub-dashboard.json`, `monitoring/openhub-reference-dashboard.json`.
- Datasource каталога: `monitoring/grafana-datasource-openhub-db.yaml`.
- Трассировка nginx: `web/nginx/conf.d/otel.conf`; метрики nginx: `monitoring/otelcol-nginx.yaml`, `NGINX_STATUS_ENDPOINT` в `.env` на B после сплита.
- Метрики хоста: `monitoring/otelcol-host.yaml`, сервис `hostmetrics`.
- Проверка: `./monitoring/test/run.sh`.

### MinIO

Bootstrap: `minio/bootstrap.sh`. Политики: `minio/policies/`. Smoke: `minio/test/smoke.sh`. Образ собирается из `minio/Dockerfile` (бинарники с GitHub Releases).

### hub.oscript.io — robots и лимиты

- `web/nginx/robots/hub.oscript.io.txt` — отдаёт nginx.
- Лимиты: `web/nginx/conf.d/hub-limits.conf`, `web/nginx/snippets/hub.oscript.io-limits.conf`.
- HTTP `/push` без редиректа на https — см. `hub.oscript.io` в `sites-enabled`.

## Ограничения

- `hostmetrics` — `network_mode: host`; OTLP на A в колокации — `127.0.0.1:4317`, после сплита — `10.9.0.2:4317`.
- `local_backup.sh` — только `web_content`, не рассчитан на две ноды.
- На сервере A — Ubuntu 16.04, Docker без переустановки; Ansible на A только через `/opt/python3/bin/python3`.

## Указатели

| Тема | Документ |
| --- | --- |
| порядок миграции на две ноды | [`.cursor/plans/README.md`](.cursor/plans/README.md) |
| перенос метаданных в OpenHub | [`openhub-migration/README.md`](openhub-migration/README.md) |
| OTel, robots, rate limit hub | `web/nginx/conf.d/otel.conf`, `hub-limits.conf`; `./web/nginx/test/run.sh` |
| роль БД Grafana | `monitoring/grafana-db-role.sql`, `monitoring/grafana-datasource-openhub-db.yaml` |
| переменные OpenHub / MinIO | `openhub.env.example`, `env/node_*.env.example`, `minio/.env.example` |
