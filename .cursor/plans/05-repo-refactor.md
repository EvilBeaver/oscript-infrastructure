# 5. Как меняется репозиторий

[Ansible](04-ansible.md) · [оглавление](README.md) · дальше: [порядок работ на хостах](06-work-order.md)

Целевое дерево описано в [главе 3](03-target.md). Здесь — в каком порядке сегодняшние файлы уступают место модулям и Ansible, и какой коммит можно влить в `master`, пока нода A ещё делает `git pull` и `docker-compose up`.

## Правило

Весь рефакторинг ведётся в ветке `feature/multi-host`. `master` не меняется, пока старый стек не остановлен: пока A обновляется из `master` корневым `docker-compose.yml`, очередной `git pull` на проде ничего нового не принесёт. Новый стек разворачивается из `feature/multi-host` (`deploy_ref=feature/multi-host`, см. [главу 1](01-decisions.md)), после приёмки ветка вливается в `master`, `deploy_ref` возвращается к `master`.

Внутри ветки коммиты по-прежнему идут в порядке ниже: новые каталоги (`compose/`, `ansible/`, `env/`, `ops/`) рядом с корневым `docker-compose.yml`, коммит, переписывающий корневой файл, скрипты и `AGENTS.md`, — последним и выкатывается на A отдельным окном после [переноса каталога](07-move-clone.md).

Каталоги приложений не переезжают: `web/nginx`, `jenkins`, `minio`, `S3`, `monitoring`, `bot`, `docker/` остаются контекстами сборки и конфигами. Меняется только то, как их собирают в стек и как это применяют на хостах.

## Три коммита

Их можно склеивать, если проверка из колонки «критерий» уже зелёная. На хост A из этой тройки попадает только последний.

| Коммит | Этап (гл. 6) | Что появляется в git | Что ещё живёт по-старому | На хосты |
| --- | --- | --- | --- | --- |
| 1. Модули рядом с монолитом | 1 | `compose/`, `env/*.env.example`, `ops/dc.sh`, правки тестовых стендов под статический upstream и переменную `NGINX_STATUS_ENDPOINT` | корневой `docker-compose.yml` — источник, с которого сняты модули; скрипты по-прежнему зовут `docker-compose` | файлы появятся в клоне при `git pull`, но в работу не попадают. CI сравнивает `config` |
| 2. Ansible рядом | 2 | корневой `ansible.cfg` и `ansible/` без секретов и без боевого inventory | роли ни на что не указывают как на уже применённое | только B, и только после того, как оператор сам запустит плейбук (этапы 4 и 5) |
| 3. Переключение входа | 3 | корневой `docker-compose.yml` удаляется, на A в `.env` появляется `COMPOSE_FILE` (колокация); скрипты и `AGENTS.md` зовут `ops/dc.sh`, `monitoring/test` переключает `extends` на модуль | v1-команда `docker-compose` на этом файле останавливается с ошибкой и второй стек не создаёт | окно на A после переноса каталога |

До коммита 3 в репозитории два описания одного и того же однонодового стека. Истина для прода — корневой файл. Истина для новой сборки — модули (`node_a.compose.yaml` + `overrides/colocated.yml`). Их удерживает проверка: `config` колокации и `config` монолита совпадают по сервисам, образам, переменным и томам.

## Коммит 1 — что именно кладётся

Снимается с текущего `docker-compose.yml` в `master`, сервис за сервисом:

- `compose/apps/<сервис>.yml` — тело сервиса (с явным `container_name: os_<сервис>_1`);
- `compose/node_a.compose.yaml` — целевая сборка ноды A (без `minio` и `lgtm`), `name: os`, тома и сети ноды A;
- `compose/node_b.compose.yaml` — `minio`, `lgtm`, `hostmetrics`, `name: os`, тома и сети ноды B; на A этот файл не запускают;
- `compose/overrides/colocated.yml` — оверлей однонодовой колокации на A до окна переноса (этап 7): подключает `compose/apps/minio.yml` и `compose/apps/lgtm.yml`, тома `minio_data` и `lgtm_data`, локальный `OTLP_ENDPOINT=127.0.0.1:4317` и `depends_on` у `nginx` и `openhub` на `minio` и `lgtm`;
- `compose/overrides/split.yml` — оверлей A с окна переноса (этап 7): публикации `10.9.0.1:8080` и `10.9.0.1:5432`, `extra_hosts` на `minio`/`lgtm`, `OTLP_ENDPOINT=10.9.0.2:4317`. Он подключается только в этом окне, когда `wg0` уже есть;
- `env/node_a.env.example` и `env/node_b.env.example` — имена переменных, значения пустые;
- `ops/dc.sh` — обёртка `docker compose` с `--project-directory` и `--env-file` (подхватывает `COMPOSE_FILE` из `.env`).

Корневой `docker-compose.yml` в этом коммите не редактируется. Сервисов `opm_hub` и `opm_hub_db` в нём уже нет — в модули их не переносить. `init-letsencrypt.sh`, `add-letsencrypt-domain.sh`, `openhub-migration/*.sh`, `README.md` и `AGENTS.md` в этом коммите тоже не редактируются. Иначе книга для агента и боевая команда на A разойдутся раньше окна.

Тесты `./web/nginx/test/run.sh` и `./monitoring/test/run.sh` остаются на своих `docker-compose.yml` внутри `web/nginx/test` и `monitoring/test`. В `web/nginx/test/docker-compose.yml` добавляется сетевой алиас `minio` (для статического `proxy_pass`), а в `monitoring/otelcol-nginx.yaml` — `${NGINX_STATUS_ENDPOINT:-http://nginx:8080/nginx_status}`. В Коммите 3 `monitoring/test/docker-compose.yml` переключает `extends.file` с корневого `../../docker-compose.yml` на `../../compose/apps/hostmetrics.yml`, так как `extends` в Compose не проходит сквозь `include`.

## Коммит 2 — Ansible

В git появляется каркас из [главы 4](04-ansible.md): корневой `ansible.cfg`, `ansible/requirements.yml`, `ansible/site.yml`, роли, `inventory.example.ini`, `vault.example.yml`, `host_vars`, `group_vars`. В `.gitignore` — `ansible/inventory.ini`, `vault.yml`, `vault_pass*`.

Факт «роль применена» наступает только на хосте:

| Роль | Первый прогон | Где |
| --- | --- | --- |
| `common`, `firewall` | этап 4 | B, пустая машина |
| `wireguard` | этап 5 | B и A; на A — с таймером отката |
| `spoofdpi`, `firewall` для эталона A | этап 5, вместе с туннелем | A |
| `app` | после коммита 3, сначала `--check` | A — последней; на B — когда нужны minio и lgtm, ещё без прод-данных |
| `portainer` | после приёмки | после этапа 8 |

Пока роль `app` на A не прогнана, стек на A обновляют руками: `git pull` и `ops/dc.sh` (после коммита 3) или прежний `docker-compose` (до него). Ansible не заводит второй каталог и не подменяет этот ритуал, пока `--check` не сошёлся.

## Коммит 3 — окно на A

Делается после этапа 0, когда каталог уже `/opt/oscript` и `COMPOSE_PROJECT_NAME=os`. В одном коммите:

1. Корневой `docker-compose.yml` удаляется. Вход на каждой ноде один: `ops/dc.sh` и `COMPOSE_FILE` в `.env`. На A в `.env` добавляется `COMPOSE_FILE=compose/node_a.compose.yaml:compose/overrides/colocated.yml` (до этого окна переменной нет, её вписывает оператор или роль `app`), `name: os` лежит в `node_*.compose.yaml`.
2. В `monitoring/test/docker-compose.yml` путь `extends.file` для `hostmetrics` меняется на `../../compose/apps/hostmetrics.yml`.
3. `init-letsencrypt.sh`, `add-letsencrypt-domain.sh` и скрипты `openhub-migration/` вызывают `ops/dc.sh`.
4. `README.md` и `AGENTS.md` описывают две ноды, каталог `/opt/oscript` и эту команду. Инструкция «один сервер, один `docker-compose.yml`» снимается здесь, не в коммите 1.
5. `Vagrantfile` и `init.sh` удаляются: они не описывают боевой стек уже сейчас, а после смены входа окончательно вводят в заблуждение.

На A этот коммит накатывается так: `git pull` от `deploy`, затем `ops/dc.sh up -d` (или прямой вызов плагина v2 с теми же флагами). Контейнеры пересоздадутся из‑за меток Compose, тома `os_*` останутся. Бинарь `/usr/local/bin/docker-compose` (v1) модульные файлы не понимает — это ожидаемо, им больше не пользуются.

Откат окна — вернуть предыдущий коммит, убрать `COMPOSE_FILE` из `.env` (v1 тоже его читает и упадёт на файлах v2) и снова поднять стек прежней командой v1 из того же каталога. Тома те же, пока имя проекта `os`.

## Что не заменяется модулями

| Файл | Когда с ним что-то происходит |
| --- | --- |
| `web/`, `jenkins/`, `minio/`, `S3/`, `monitoring/`, `bot/`, `docker/` | остаются. В модулях меняются только пути `build` и bind-mount |
| `openhub.env.example`, `minio/.env.example` | остаются справочниками имён. Разрез по нодам — в `env/node_*.env.example` |
| `local_backup.sh` | остаётся до отдельной задачи про бэкапы после сплита. Ansible его не подменяет в этих коммитах |
| `openhub-migration/` | архив уже выполненного переноса. Скрипты либо зовут `ops/dc.sh`, либо, если ими больше не пользуются, уезжают в коммите вывода старого хаба |
| Файрвол, SpoofDPI, WireGuard | в git их раньше не было. Они появляются как роли коммита 2 и впервые применяются на хосте на этапе 5, а не заменой какого-то файла репозитория |

## Когда колокация отключается на ноде A

`compose/node_a.compose.yaml` с самого Коммита 1 — общая часть ноды A без `minio`, `lgtm`, туннельных публикаций и `extra_hosts` на B. До окна переноса (этап 7) к ней подключён `compose/overrides/colocated.yml` (`COMPOSE_FILE=compose/node_a.compose.yaml:compose/overrides/colocated.yml` в `.env`). Адреса `10.9.0.x` в нём не нужны, поэтому этап 3 не ждёт туннель (этап 5).

В окне (этап 7) на A меняется одна строка `.env`: `COMPOSE_FILE=compose/node_a.compose.yaml:compose/overrides/split.yml`. Файл `compose/overrides/colocated.yml` остаётся в репозитории на случай отката окна, пока живы старые тома на A.
