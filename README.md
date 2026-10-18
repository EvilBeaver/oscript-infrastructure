# Инфраструктура oscript.io

Репозиторий с конфигурацией и артефактами для развёртывания сервисов экосистемы [OneScript](https://oscript.io) на одном сервере. Всё поднимается через Docker Compose.

## Что здесь разворачивается

| Домен | Сервис |
| --- | --- |
| [oscript.io](https://oscript.io) | Основной сайт проекта |
| [hub.oscript.io](https://hub.oscript.io) | Хаб пакетов [OpenHub](https://github.com/Segate-ekb/openhub) |
| [hub-old.oscript.io](https://hub-old.oscript.io) | Прежний хаб пакетов (opm-hub) |
| [build.oscript.io](https://build.oscript.io) | Jenkins — сборки и CI |
| [s3.oscript.io](https://s3.oscript.io) | MinIO — S3-совместимое хранилище артефактов |
| [grafana.oscript.io](https://grafana.oscript.io) | Мониторинг (Grafana, метрики, логи, трассы) |

## Стек технологий

- **Оркестрация** — Docker Compose
- **Веб-сервер** — nginx (TLS, reverse proxy, OpenTelemetry)
- **Сертификаты** — Let's Encrypt (certbot)
- **Базы данных** — PostgreSQL
- **Хранилище** — MinIO (локально) и внешний S3 (синхронизация через rclone)
- **Хаб пакетов** — OpenHub
- **CI** — Jenkins
- **Наблюдаемость** — Grafana otel-lgtm, OpenTelemetry Collector

## Структура репозитория

```
docker-compose.yml       — описание всего стека
web/nginx/               — конфигурация и образ nginx
web/certbot/             — сертификаты (не в git)
monitoring/              — дашборды Grafana, конфиги коллекторов
minio/                   — образ MinIO и начальная настройка
jenkins/                 — образ Jenkins
openhub-migration/       — скрипты разового переноса данных со старого хаба
S3/                      — синхронизация файлов во внешнее хранилище
bot/                     — исходники Telegram-бота
```

Секреты (пароли, ключи API) задаются в файле `.env` в корне репозитория — он не коммитится. Образцы переменных: [`openhub.env.example`](openhub.env.example), [`minio/.env.example`](minio/.env.example).

## Быстрый старт

На сервере с установленными Docker и docker-compose:

```bash
# 1. Создать .env по образцам openhub.env.example и minio/.env.example
# 2. Выпустить сертификаты (первый раз)
./init-letsencrypt.sh

# 3. Поднять стек
docker-compose up -d
```

Для добавления нового домена: создать конфиг в `web/nginx/sites-enabled/`, затем `./add-letsencrypt-domain.sh <домен>`.

## Тесты

Интеграционные проверки конфигурации (нужен Docker Compose v2):

```bash
./web/nginx/test/run.sh      # nginx, OTel, robots.txt, rate limits
./monitoring/test/run.sh     # метрики хоста
```

## Дополнительно

- **Перенос данных со старого хаба** — [`openhub-migration/README.md`](openhub-migration/README.md)
- **Настройка OpenHub с нуля** — переменные в `openhub.env.example`, первый администратор через `/setup` на hub.oscript.io
