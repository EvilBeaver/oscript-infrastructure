# Инфраструктура oscript.io

Конфигурация и артефакты для сервисов экосистемы [OneScript](https://oscript.io). Прод — **две ноды** (A — публичный edge, B — MinIO, Grafana, hostmetrics), каталог стека `/opt/oscript`, оркестрация — **Docker Compose v2** через [`ops/dc.sh`](ops/dc.sh).

Пошаговый план миграции и Ansible — [`.cursor/plans/README.md`](.cursor/plans/README.md). Краткая справка для агентов — [`AGENTS.md`](AGENTS.md).

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
  --tags common,never,firewall
```

Проверка каркаса без хостов: `./ansible/test/run.sh`. Ручная подготовка B — глава 4 в [`.cursor/plans/04-ansible.md`](.cursor/plans/04-ansible.md).

## Тесты

```bash
./web/nginx/test/run.sh
./monitoring/test/run.sh
./ansible/test/run.sh
```

## Дополнительно

- Перенос метаданных opm-hub → OpenHub — [`openhub-migration/README.md`](openhub-migration/README.md)
- OpenHub с нуля — `openhub.env.example`, первый админ через `/setup` на hub.oscript.io
