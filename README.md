# Инфраструктура oscript.io

Конфигурация и артефакты для сервисов экосистемы [OneScript](https://oscript.io). Прод — **две ноды** (A — публичный edge, B — MinIO, Grafana, hostmetrics), каталог стека `/opt/oscript`, оркестрация — **Docker Compose v2** через [`ops/dc.sh`](ops/dc.sh).

Краткая справка для агентов — [`AGENTS.md`](AGENTS.md).

## Публичные сервисы

| Домен | Сервис |
| --- | --- |
| [oscript.io](https://oscript.io) | Основной сайт |
| [hub.oscript.io](https://hub.oscript.io) | [OpenHub](https://github.com/Segate-ekb/openhub) |
| [build.oscript.io](https://build.oscript.io) | Jenkins |
| [s3.oscript.io](https://s3.oscript.io) | MinIO (после сплита — данные на B) |
| [grafana.oscript.io](https://grafana.oscript.io) | Grafana, метрики, логи, трассы |

## Структура

```
compose/          — модульный стек (node_a, node_b, overrides)
env/              — образцы .env (node_a, node_b)
ops/dc.sh         — единая команда compose на нодах
ansible/          — роли и site.yml (inventory и vault — на B, вне git)
web/nginx/        — reverse proxy и TLS
monitoring/       — observability
minio/ jenkins/ S3/ bot/
```

Секреты — в `.env` (не в git) и Ansible vault. Образцы: [`env/node_a.env.example`](env/node_a.env.example), [`openhub.env.example`](openhub.env.example), [`minio/.env.example`](minio/.env.example).

## Сайт oscript.io — исходники, сборка и развёртывание

Исходники сайта лежат **не в этом репозитории**, а в отдельном проекте [`EvilBeaver/OneScript.WebSite`](https://github.com/EvilBeaver/OneScript.WebSite). Здесь — только инфраструктура, которая запускает готовый образ `oscript/backend` (сервис `site`).

### Из чего состоит сайт

| Часть | Что это | Куда собирается |
| --- | --- | --- |
| `frontend/` | VitePress (документация и статика) | `backend/data/wwwroot` → том `wwwroot` (публикует Jenkins) |
| `backend/` | приложение OneScript (фреймворк [autumn](https://github.com/otymko/autumn)) | Docker-образ `oscript/backend` |

Бэкенд поднимает веб-сервер на порту `3030` (`backend/src/Классы/Бэкенд.os`) и отдаёт два вида контента:

- статику фронтенда из `server.rootDir/wwwroot` — это том `wwwroot` (`/app/data/wwwroot`), наполняется Jenkins-ом без перезапуска контейнера;
- файлы релизов из `filesDir/download/versions` — это том `web_content` (`/var/www/oscript.io`).

Маршрутизация (`backend/src/Классы/Роутер.os`):

| Маршрут | Обработчик | Назначение |
| --- | --- | --- |
| `downloads/…` | `ОбработчикСкачивания` | скачивание дистрибутивов (`/downloads/<version>/<type>?bitness`) |
| `api/archive/…` | `ОбработчикApi` | метаданные версий (JSON) |
| `api/publish` | `ПубликацияВерсий` | вебхук публикации сборок |
| всё остальное | статика | фронтенд из `wwwroot` |

### Конфигурация бэкенда

Конфиг `backend/src/autumn-properties.json` переопределяется переменными окружения; точка в ключе соответствует подчёркиванию в имени env-переменной.

| Ключ конфига | Env | Значение на проде | Назначение |
| --- | --- | --- | --- |
| `filesDir` | `filesDir` | `/var/www/oscript.io` | каталог файлов релизов (том `web_content`) |
| `server.rootDir` | `server_root` | `/app/data` | каталог сервера; `wwwroot` — статика фронтенда (том `wwwroot`) |
| `server.port` | `server.port` | `3030` | порт веб-сервера |
| `publish.secret` | `publish_secret` | из `.env` на A | секрет вебхука публикации сборок |

### Сборка и деплой сайта (Jenkins)

CI/CD сайта — **Jenkins** (`build.oscript.io`, нода A), пайплайн задан `Jenkinsfile` в корне репо сайта:

1. **`Build content`** — node-контейнер собирает VitePress (`npm run docs:build`) в `backend/data/wwwroot`; том `web_content` подключён как `/var/www`, чтобы страницы архива версий читали релизы (`VITEPRESS_FILES_DIR=/var/www/oscript.io`).
2. **`Publish content`** — `rsync` собранных файлов в named volume `os_wwwroot` (`WWWROOT_VOLUME` в `Jenkinsfile`). Это том `wwwroot`, смонтированный в `site` как `/app/data/wwwroot`: новый фронт отдаётся **без пересоздания контейнера**.
3. **`Create container`** — `docker buildx build --load -t oscript/backend .` собирает образ и кладёт его в Docker ноды A (Jenkins имеет доступ к `/var/run/docker.sock`). На работающий том статики эта стадия не влияет.

Имя тома на хосте — `<проект>_wwwroot`, то есть `os_wwwroot` при `COMPOSE_PROJECT_NAME=os`.

Пересоздавать контейнер нужно **только при изменениях кода бэкенда** (или его зависимостей):

```bash
cd /opt/oscript && ./ops/dc.sh up -d site
```

Правки контента и вёрстки фронтенда в пересоздании не нуждаются.

### Два независимых потока обновления

1. **Обновление самого сайта** (код фронтенда/бэкенда): правка в `OneScript.WebSite` → push → Jenkins собирает контент и публикует его в том `wwwroot`. Пересоздание `site` (`./ops/dc.sh up -d site`) — только при изменениях бэкенда.
2. **Публикация сборок OneScript** (дистрибутивы для скачивания): GitHub Actions репозитория OneScript шлёт `POST /api/publish` с подписью HMAC-SHA256 (заголовок `X-OneScript-Signature-256`). nginx проксирует на `site:3030`; бэкенд проверяет `publish.secret`, скачивает файлы с GitHub в `filesDir/download/versions` и атомарно заменяет каталоги каналов (`latest`, `preview`, `night-build`, `lts`, `lts-dev`). Это **не** деплой сайта.

Сервис `s3-sync` каждые 12 часов зеркалирует во внешний S3 только каталог `hub.oscript.io` внутри тома `web_content` (подкаталог задан `SYNC_SUBDIR` в `S3/Dockerfile`).

### Нюансы

- Статика фронтенда живёт в томе `wwwroot`, а не в образе: после `Create container` в образе лежит лишь исходная (`COPY data/`) копия, но она перекрыта монтированием тома. Поэтому «свежесть» сайта определяет `Publish content`, а не пересборка образа.
- `frontend/.github/workflows/deploy.yml` — черновик (деплой в GitHub Pages), не используется; рабочий CI — Jenkins.

## Запуск на ноде

```bash
# .env: COMPOSE_PROJECT_NAME=os и COMPOSE_FILE=… (см. env/*.env.example)
./ops/dc.sh config
./ops/dc.sh up -d
```

Первые сертификаты: `./init-letsencrypt.sh`. Новый домен: конфиг в `web/nginx/sites-enabled/`, затем `./add-letsencrypt-domain.sh <домен>`.

## Ansible (control node — нода B)

```bash
cd /opt/oscript
ansible-playbook ansible/site.yml \
  -e @/opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass \
  --tags common --limit node_b
```

Проверка каркаса без хостов: `./ansible/test/run.sh`.

## Тесты

```bash
./web/nginx/test/run.sh
./monitoring/test/run.sh
./ansible/test/run.sh
```

## Дополнительно

- OpenHub с нуля — `openhub.env.example`, первый админ через `/setup` на hub.oscript.io
