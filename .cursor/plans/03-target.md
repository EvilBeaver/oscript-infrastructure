# 3. Целевое устройство

[Как устроена нода A](02-as-is.md) · [оглавление](README.md) · дальше: [Ansible](04-ansible.md)

## Топология

```
Интернет
    │ :80 :443
    ▼
Нода A                                          WireGuard 10.9.0.0/24                         Нода B
nginx  s3.oscript.io ──────────────────────────────────────────────────────────────────────► minio :9000
       grafana.oscript.io ─────────────────────────────────────────────────────────────────► lgtm :3000
       otel gRPC ──────────────────────────────────────────────────────────────────────────► lgtm :4317
openhub  S3 http://minio:9000 ─────────────────────────────────────────────────────────────► minio :9000
         OTLP http://lgtm:4318 ─────────────────────────────────────────────────────────────► lgtm :4318
hostmetrics A ──────────────────────────────────────────────────────────────────────────────► lgtm :4317
openhub_db :5432 на 10.9.0.1 ◄────────────────────────────────────────────────────────────── Grafana
hostmetrics B ──────────────────────────────────────────────────────────────────────────────► lgtm :4317
```

Публичные 80 и 443 слушаются на всех адресах A. Порт 50000 (tcp и udp) остаётся открытым, как сейчас (см. `DOCKER-USER` в [главе 2](02-as-is.md)); в этой схеме он не участвует. Всё остальное из таблицы ниже — только на адресе WireGuard своей ноды.

| Кто | Куда | Как резолвить | Публикация |
| --- | --- | --- | --- |
| nginx, сайт S3 | MinIO API | `extra_hosts: minio:10.9.0.2` и статический `proxy_pass http://minio:9000` | `10.9.0.2:9000:9000` |
| nginx, Grafana | lgtm:3000 | то же для имени `lgtm` | `10.9.0.2:3000:3000` |
| nginx, otel.conf | lgtm:4317 | имя `lgtm` | `10.9.0.2:4317:4317` |
| openhub | minio:9000 и lgtm:4318 | `extra_hosts`, URL в env не менять | `9000` и `4318` на `10.9.0.2` |
| hostmetrics A | `OTLP_ENDPOINT=10.9.0.2:4317` | IP | 4317 |
| hostmetrics B | `10.9.0.2:4317` | IP, даже с самой B | 4317 |
| коллектор nginx в lgtm | `${NGINX_STATUS_ENDPOINT:-http://nginx:8080/nginx_status}` | переменная в `monitoring/otelcol-nginx.yaml` (на B в `.env` `http://10.9.0.1:8080/nginx_status`) | `10.9.0.1:8080:8080` у nginx |
| Grafana, datasource | `openhub_db:5432` | `extra_hosts: openhub_db:10.9.0.1` на B | `10.9.0.1:5432:5432` |
| Jenkins → S3, когда переключат | `https://s3.oscript.io` | публичный DNS, через nginx A | отдельный extra_hosts контейнеру Jenkins не нужен |
| Portainer | браузер оператора | `ssh -L 9443:10.9.0.2:9443` | Server на B, `10.9.0.2:9443` |
| Portainer Agent | Server на B | туннель | `10.9.0.1:9001` |

`web/nginx/sites-enabled` для status уже разрешает `10.0.0.0/8`, адрес B туда входит. В `monitoring/otelcol-nginx.yaml` endpoint задаётся через `${NGINX_STATUS_ENDPOINT:-http://nginx:8080/nginx_status}`: тестовый compose nginx продолжает ходить по умолчанию на `http://nginx:8080/nginx_status`, а на B в `.env` задаётся `http://10.9.0.1:8080/nginx_status`. В `web/nginx/test/docker-compose.yml` сервису `backend` добавляется сетевой алиас `minio`, чтобы статический `proxy_pass http://minio:9000` проходил `nginx -t` и `./web/nginx/test/run.sh` оставался зелёным.

Консоль MinIO: `127.0.0.1:9001` на B. Portainer этот порт не занимает.

## Почему proxy_pass статический

`extra_hosts` попадает в `/etc/hosts` контейнера. nginx при `proxy_pass` через переменную (`set $target_url`) спрашивает только `resolver` — сейчас это Docker DNS `127.0.0.11` — и `/etc/hosts` не читает. Статический `proxy_pass http://minio:9000` резолвится при загрузке конфига через `getaddrinfo` и `/etc/hosts` видит.

Имя резолвится один раз при старте или reload. Пока MinIO ещё локальный, пересоздание контейнера меняет его IP, и до reload nginx (в образе это раз в 6 часов) будет 502. Поэтому статический `proxy_pass` для s3 и grafana выкатывается вместе с переносом, когда адрес уже адрес туннеля. В колокации оверлей оставляет `depends_on` на minio и lgtm.

Если имя не резолвится на старте, nginx падает с `host not found in upstream`. У сервиса в боевом файле нет `restart`. В модуле nginx задать `restart: unless-stopped`. В сборке ноды A без локальных minio/lgtm имена для `nginx -t` даёт `extra_hosts`, однако для самого старта контейнера `nginx` интерфейс `wg0` обязателен, так как на `10.9.0.1:8080` делается `bind` (отсюда drop-in `After=wg-quick@wg0.service` у Docker).

Переменная `$target_url` остаётся рабочей только если resolver знает и локальные имена Docker, и адреса туннеля. Встроенный `127.0.0.11` адреса на B не знает. CoreDNS для этого не поднимаем.

## Репозиторий

Текущие каталоги приложений остаются. Монолитный `docker-compose.yml` не удалять, пока модульная сборка не проверена на A.

```
ansible.cfg                   # в корне репо; host_key_checking включён, inventory вне git
ansible/
  requirements.yml            # community.docker и community.general, версии закреплены
  inventory.example.ini
  inventory.ini               # gitignore, живёт только на B
  group_vars/all.yml          # подсеть WG, project_name, карта размещения
  host_vars/node_a.yml
  host_vars/node_b.yml
  vault.example.yml           # только имена ключей
  site.yml
  roles/common
  roles/firewall
  roles/spoofdpi
  roles/wireguard
  roles/app
  roles/portainer             # тег, после переноса
compose/
  apps/<сервис>.yml
  node_a.compose.yaml         # целевая сборка ноды A (без minio и lgtm)
  node_b.compose.yaml         # сборка ноды B (minio, lgtm, hostmetrics)
  overrides/colocated.yml     # A до сплита: include minio/lgtm, их тома, локальный OTLP и depends_on
  overrides/split.yml         # A после сплита: публикации на 10.9.0.1, extra_hosts minio/lgtm/..., OTLP на B
env/
  node_a.env.example
  node_b.env.example
ops/dc.sh                     # единая команда запуска на обеих нодах: docker compose с --project-directory и --env-file (COMPOSE_FILE из .env)
docker-compose.yml            # переходный монолит; удаляется в коммите 3
web/nginx/  jenkins/  minio/  S3/  monitoring/  bot/
```

Файлы `host_vars` названы по хостам `node_a` и `node_b`. Группы inventory — `edge` и `worker`. Карта размещения в `group_vars/all.yml` ключуется именами хостов (`node_a`, `node_b`), а не группами.

Карта размещения в `group_vars/all.yml` — таблица «сервис → нода». Из неё Ansible собирает `extra_hosts` и список include. Перенос сервиса позже — правка карты и двух строк include, не тела модуля. Для первой версии достаточно явно перечисленных include в `node_*.compose.yaml`; карта всё равно заводится сразу, чтобы не выдумывать её при выносе OpenHub.

Контексты сборки в модулях, пути от каталога `compose/apps/`:

- nginx — `../../web/nginx`
- jenkins — `../../jenkins`
- minio — `../../minio`
- s3-sync — `../../S3`
- тома lgtm и hostmetrics — `../../monitoring/...`

## Правила модулей

1. В `apps/<сервис>.yml` только этот сервис. Тома и сети объявляются в `node_*.compose.yaml`, иначе `include` конфликтует по именам.
2. `depends_on` — только на сервис той же сборки. `compose/node_a.compose.yaml` — общая часть ноды A: сервисы A без `minio` и `lgtm`, без публикаций на адрес туннеля и без `extra_hosts` на B. Сама по себе эта сборка не запускается, к ней всегда подключается ровно один оверлей:
   - `compose/overrides/colocated.yml` — до окна переноса (этап 7): подключает `compose/apps/minio.yml` и `compose/apps/lgtm.yml`, объявляет тома `minio_data` и `lgtm_data`, локальный `OTLP_ENDPOINT=127.0.0.1:4317` и `depends_on` у `nginx` и `openhub` на `minio`/`lgtm`. Адреса `10.9.0.x` здесь не используются, поэтому оверлей работает и до WireGuard;
   - `compose/overrides/split.yml` — с окна переноса (этап 7): публикации `10.9.0.1:8080` (nginx) и `10.9.0.1:5432` (openhub_db), `extra_hosts` на `minio`/`lgtm` (`10.9.0.2`), `OTLP_ENDPOINT=10.9.0.2:4317`. Нужен интерфейс `wg0`.
3. `restart`, переменные, ulimits и комментарии про OTEL переносятся из `docker-compose.yml` в `master`. Образ openhub — `segateekb/openhub:0.21.0`, sampler `1.0`, переменные `OSHUB_UPDATES_CHECK` и `OTEL_*` сохраняются. Корневой файл остаётся прежним, пока модули не сверены: момент замены — [глава 5](05-repo-refactor.md).
4. `name: os` в обоих `node_*.compose.yaml`. Плюс `COMPOSE_PROJECT_NAME=os` и `COMPOSE_FILE` в `.env` каждой ноды — единственный способ выбрать файлы, одинаковый на обеих нодах (на A до сплита: `compose/node_a.compose.yaml:compose/overrides/colocated.yml`, на A после сплита: `compose/node_a.compose.yaml:compose/overrides/split.yml`, на B: `compose/node_b.compose.yaml`). Запуск на каждой ноде один и тот же: `ops/dc.sh up -d`. Корневого `docker-compose.yml` после коммита 3 нет. Ansible передаёт `project_name: os` и нужный список `files`, чтобы имя не взялось от каталога `compose/`.
5. Compose по умолчанию ищет `.env` в каталоге первого файла `-f`, то есть в `compose/`. Запуск всегда указывает корень проекта и `.env` (а список файлов берётся из `COMPOSE_FILE` в `.env` либо передаётся явно через `-f`):

```bash
docker compose \
  --project-directory /opt/oscript \
  --env-file /opt/oscript/.env \
  -f /opt/oscript/compose/node_a.compose.yaml \
  up -d
```

То же делает `ops/dc.sh` (передаёт `--project-directory /opt/oscript --env-file /opt/oscript/.env`, опираясь на `COMPOSE_FILE` из `.env`, если `-f` не передан аргументом). Роль `app` задаёт `project_src`, `files` и `env_files` явно.

6. Относительные bind-mount резолвятся от `compose/apps/`. Путь `./web/certbot/conf` из монолита в модуле записывается как `../../web/certbot/conf`. Ошибочный путь молча создаёт пустой каталог, и nginx поднимется без сертификатов. Проверка: `docker compose config` показывает источники под `/opt/oscript/`, кроме `/var/run/docker.sock` и корня хоста для hostmetrics.
7. Контейнерам не задавать `dns:`.
8. hostmetrics: `network_mode: host`, `user: "10001:${DOCKER_GID:-995}"`, сокет Docker и `/` как hostfs. `DOCKER_GID` Ansible вычисляет через `getent group docker` и пишет в `.env`. На B другой номер группы — это нормально. `OTEL_HOST_NAME` разный. `OTLP_ENDPOINT` после сплита на обеих нодах — `10.9.0.2:4317` (в колокации на A — `127.0.0.1:4317`).
9. `openhub_db` публикует `10.9.0.1:5432:5432` для Grafana. Публикацию `5432:5432` старой базы в новый модуль не копировать: сервиса `opm_hub_db` в compose больше нет.
10. Явные `container_name: os_<сервис>_1` во всех `compose/apps/*.yml` (`os_nginx_1`, `os_site_1`, `os_jenkins_1`, `os_certbot_1`, `os_tg_bot_1`, `os_s3-sync_1`, `os_minio_1`, `os_openhub_1`, `os_openhub_db_1`, `os_lgtm_1`, `os_hostmetrics_1`). Имена `os_openhub_1` и `os_openhub_db_1` зашиты в `monitoring/openhub-dashboard.json` и `monitoring/grafana-db-role.sql`. Явное задание для всех сервисов гарантирует, что переход с v1 на плагин v2 не переименует контейнеры в `os-*-1`. Сервисов `opm_hub` и `opm_hub_db` среди модулей нет.
11. Ключ `version:` в файлах не писать.
12. Первый `up` на A после удаления minio и lgtm — с `--remove-orphans` (`remove_orphans: true`). Иначе контейнеры останутся от монолита.
13. Скрипты `init-letsencrypt.sh`, `add-letsencrypt-domain.sh`, `openhub-migration/*.sh`, плюс `AGENTS.md`, `monitoring/test/docker-compose.yml` (`extends` на `../../compose/apps/hostmetrics.yml`) и корневой README переводят в коммите переключения (глава 5), не в том коммите, где модули только появляются рядом с монолитом.
14. Первый `up` из модулей пересоздаст контейнеры: сменятся метки `config-hash` и рабочий каталог. Тома остаются. Это короткий рестарт всего стека, его делают в окне, а не «в фоне днём».

Проверка, которую должен проходить PR:

```bash
docker compose --project-directory . --env-file env/node_a.env.example \
  -f compose/node_a.compose.yaml config
docker compose --project-directory . --env-file env/node_b.env.example \
  -f compose/node_b.compose.yaml config
docker compose --project-directory . --env-file env/node_a.env.example \
  -f compose/node_a.compose.yaml -f compose/overrides/colocated.yml config
docker compose --project-directory . --env-file env/node_a.env.example \
  -f compose/node_a.compose.yaml -f compose/overrides/split.yml config
```

Для примеров env в команде `config` пустые обязательные переменные задают фиктивными значениями в CI, не в git. `depends_on` на сервис, которого нет в этой сборке, — ошибка.

Сравнение с монолитом: `config` колокации и `config` корневого файла совпадают по сервисам, образам, переменным и томам. Отличаться могут пути bind-mount (они станут абсолютными от корня репо) и служебные метки.

## Секреты

HashiCorp Vault нет. «Vault» здесь — файл, зашифрованный `ansible-vault`.

| Что | Где | В git |
| --- | --- | --- |
| Пароли БД, ключи MinIO, Grafana, токен бота, ключи внешнего S3, ключи WireGuard | `/opt/oscript-secrets/vault.yml` на B, владелец `deploy`, каталог `0700`. Копия — в менеджере паролей оператора | нет |
| Пароль расшифровки | менеджер паролей и `/opt/oscript-secrets/vault_pass` на B, режим `0400`, владелец `deploy` | нет |
| Файл, который читает Compose | `/opt/oscript/.env` на каждой ноде, `0640`, владелец `deploy`, группа `docker`. Его рисует плейбук | нет |
| Имена без значений | `env/node_*.env.example`, `openhub.env.example`, `minio/.env.example` | да |
| Inventory (IP, пользователь, путь к ключу) | `ansible/inventory.ini` только на B | нет, в git образец с документационными адресами |
| Ключ деплоя | приватный на B, публичный в `authorized_keys` пользователя `deploy` на A, с `from="<IP B>"` | нет |
| Сертификаты | `web/certbot/conf/` на диске A | нет |
| Учётные данные Jenkins к S3 | UI Jenkins | нет |

`DOCKER_GID` секретом не является: роль вычисляет его на хосте. `COMPOSE_PROJECT_NAME=os` пишется в `.env` обеих нод.

Запуск:

```bash
ansible-playbook ansible/site.yml \
  -e @/opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass
```

На переносе пароли не ротируют. Действующий `.env` с A переносят в `vault.yml`, режут по нодам, прогоняют шаблон и сверяют файлы.

- Нода A: секреты старого хаба (пока он описан), OpenHub, его Postgres, бот, s3-sync, `COMPOSE_PROJECT_NAME`, `COMPOSE_FILE`.
- Нода B: `MINIO_ROOT_*`, `JENKINS_S3_*` (бакет `jenkins-artifacts` создаёт bootstrap MinIO, даже пока Jenkins в облаке), `OPENHUB_S3_*`, `GRAFANA_ADMIN_PASSWORD`, `GRAFANA_DB_PASSWORD`, `NGINX_STATUS_ENDPOINT=http://10.9.0.1:8080/nginx_status`, `COMPOSE_PROJECT_NAME`, `COMPOSE_FILE`.
- В двух местах одни и те же значения: `OPENHUB_S3_*` (хаб на A и bootstrap MinIO на B), `GRAFANA_DB_PASSWORD` (роль `grafana_ro` в Postgres на A и datasource Grafana на B).

В `.gitignore`: `ansible/inventory.ini`, `vault.yml`, `vault_pass*`. Перед коммитом каталога `ansible/` — поиск по диффу на `password`, `secret`, `token` или gitleaks.

Ключ с B на A плюс sudo без пароля делает учётку `deploy` на B равносильной root на A. На B нет других публичных сервисов, кроме SSH. `vault_pass` читает только `deploy`.

Каталог `/opt/oscript` — общее место стека, не чей-то домашний каталог. Владелец `deploy`, группа `docker` (в неё входят люди, которые и сейчас управляют Docker на A). Каталоги `2755` с setgid: изменения в git-дереве делает только `deploy`, остальные члены `docker` дерево читают и запускают `compose`. `.env` (`0640`) группа читает и мир не читает: у членов `docker` и так есть сокет Docker. Учётка `deploy` входит в `docker` на обеих нодах.

## Jenkins и S3

В образе Jenkins настроек S3 нет. В MinIO уже есть заготовка: `minio/bootstrap.sh` создаёт бакет и пользователя `jenkins-artifacts`, политика в `minio/policies/`, в `minio/.env.example` endpoint для плагина — `https://s3.oscript.io`.

Переключение артефактов с облака на этот endpoint — отдельный шаг после того, как nginx стабильно проксирует MinIO. В окне переноса джобы, пишущие в облако, не останавливают.

У Jenkins задан прокси `http://host.docker.internal:8888`. Запрос на `https://s3.oscript.io` уйдёт через SpoofDPI на собственный публичный адрес A. В модуль jenkins добавляется `NO_PROXY=localhost,127.0.0.1,s3.oscript.io,10.9.0.1,10.9.0.2,minio,lgtm,openhub` (адреса перечислены явно: CIDR в `NO_PROXY` понимают не все клиенты, в том числе Java). Прокси на хосте описывает роль `spoofdpi`, иначе при воспроизведении A он потеряется.

## nginx и мониторинг

До окна, в репозитории:

1. Для `s3.oscript.io` и `grafana.oscript.io` — статический `proxy_pass` на имена `minio` и `lgtm` (в `web/nginx/test/docker-compose.yml` сервису `backend` добавляется сетевой алиас `minio`). Вливать можно заранее, на A накатывать вместе с переносом. `./web/nginx/test/run.sh` зелёный на обоих вариантах.
2. `web/nginx/conf.d/otel.conf` оставляет имя `lgtm:4317`. Адрес даёт `extra_hosts`.
3. В `monitoring/otelcol-nginx.yaml` endpoint задаётся как `${NGINX_STATUS_ENDPOINT:-http://nginx:8080/nginx_status}`: после переноса на B через `.env` подставляется `http://10.9.0.1:8080/nginx_status`, а тест nginx без переменных окружения продолжает ходить на `http://nginx:8080/nginx_status`.
4. Образ nginx пересобирается после правок `sites-enabled` и `conf.d`.

## Тесты

| Команда | Когда |
| --- | --- |
| `./web/nginx/test/run.sh` | любой PR с nginx или edge-сборкой |
| `./monitoring/test/run.sh` | PR с hostmetrics или otelcol-host |
| `docker compose … config` для обеих нод и колокации | PR с модулями |
| `./minio/test/smoke.sh` | если меняется bootstrap MinIO |
