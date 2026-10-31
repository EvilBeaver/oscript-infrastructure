# Инструкция оператора: нода A (edge)

Публичный edge: nginx, сайт, Jenkins, OpenHub, certbot, бот, s3-sync. До окна сплита (этап 7) на A же живут MinIO и LGTM (колокация). Каталог стека — **`/opt/oscript`**, пользователь **`deploy`**, группа **`docker`**.

Полная книга: [оглавление](README.md) · этапы [глава 6](06-work-order.md) · Ansible [глава 4](04-ansible.md) (плейбуки **запускаются с B**, не с A).

---

## Текущее состояние (на момент коммита 3 в git)

| Что | Сейчас на проде A |
| --- | --- |
| Ветка в `/opt/oscript` | `master`, корневой `docker-compose.yml` |
| Подъём стека | `docker-compose up -d` (v1.23.2, `/usr/local/bin/docker-compose`) |
| `.env` | `COMPOSE_PROJECT_NAME=os`, **без** `COMPOSE_FILE` |
| Тома | префикс `os_*` |

После **этапа 3** (отдельное окно): ветка `feature/multi-host`, вход `./ops/dc.sh`, в `.env` строка `COMPOSE_FILE=compose/node_a.compose.yaml:compose/overrides/colocated.yml`.

---

## Общие правила на A

- Работы со стеком — от **`deploy`** в **`/opt/oscript`**. `.env` в git не входит; при откате его **не** откатывают через git.
- **`down -v` не выполнять** — тома `os_*` общие для всех этапов.
- Плагин **`docker compose` v2.40.3** уже есть; **не обновлять**. Проверка: `docker compose version`.
- Ansible-модули на A: **`/opt/python3/bin/python3 --version`** (3.12). Системный `/usr/bin/python3` (3.5.2) для Ansible не использовать.
- Плейбуки с ролями `firewall`, `wg`, `spoofdpi` на A **запускает оператор с ноды B** (см. [operator-manual-B.md](operator-manual-B.md)). На A можно только проверять результат (`ufw status`, `wg show`, `ss`).

---

## Этап 3 — переключение на модульный compose (окно на A)

**Цель:** тот же однонодовый стек, те же тома и URL, сборка через `ops/dc.sh` и модули. Туннель **не нужен**.

### До окна (стек ещё на master)

1. Убедиться, что в origin запушена ветка **`feature/multi-host`** с **коммитом 3** (нет корневого `docker-compose.yml`, есть `ops/dc.sh` с режимом исполнения в git).
2. На A от `deploy`:

```bash
cd /opt/oscript
git status --porcelain --untracked-files=no   # должно быть пусто
git rev-parse HEAD                            # совпадает с origin/master
git fetch origin
# на origin/feature/multi-host не должно быть монолита (коммит 3 в git):
git cat-file -e origin/feature/multi-host:docker-compose.yml 2>/dev/null \
  && echo 'STOP: на ветке ещё есть docker-compose.yml — не начинать окно' \
  || echo 'OK: на feature/multi-host монолита нет'
git cat-file -e origin/feature/multi-host:ops/dc.sh
docker compose version
```

3. Снимок для сверки после `up`:

```bash
docker ps --format '{{.Names}} {{.Status}}' | sort
docker volume ls | grep '^local.*os_'
```

4. По желанию — пауза проверок StatusCake в их кабинете (короткий рестарт контейнеров).

### Окно

```bash
cd /opt/oscript
git checkout feature/multi-host
# после checkout: ls docker-compose.yml → No such file
```

В **`.env`** (права **`0640`**, владелец `deploy`, группа `docker`) добавить строку (остальное не трогать):

```bash
COMPOSE_FILE=compose/node_a.compose.yaml:compose/overrides/colocated.yml
```

Проверка **до** `up`:

```bash
./ops/dc.sh config > /tmp/compose-config.txt
grep -E 'container_name: os_' /tmp/compose-config.txt | wc -l   # ожидается 11 сервисов
grep -E 'minio:|lgtm:' /tmp/compose-config.txt
# в ports / extra_hosts / dns не должно быть 10.9.0.x (в environment NO_PROXY — норма)
```

Подъём:

```bash
./ops/dc.sh up -d
# без --remove-orphans; без down / down -v
```

Сверка:

```bash
docker ps --format '{{.Names}}' | sort
# os_certbot_1 os_hostmetrics_1 os_jenkins_1 os_lgtm_1 os_minio_1 os_nginx_1
# os_openhub_1 os_openhub_db_1 os_s3-sync_1 os_site_1 os_tg_bot_1
docker volume ls | grep os_
```

Проверка снаружи: `https://oscript.io`, `hub.oscript.io`, `s3.oscript.io`, `grafana.oscript.io`, `build.oscript.io`.

После успеха на A дальше **не** возвращаться на `master`, пока не решили откат (см. ниже).

### Откат этапа 3

Пока тома не удаляли и в `.env` остаётся `COMPOSE_PROJECT_NAME=os`:

```bash
cd /opt/oscript
git checkout master
# убрать из .env строку COMPOSE_FILE=
docker-compose up -d
```

---

## Этап 5 — что происходит на A (через Ansible с B)

Оператор **на B** прогоняет WireGuard и файрвол; на A меняются `wg0`, ufw, SpoofDPI. Compose **не трогать** в этом заходе.

**Приёмка с A** (после прогона с B):

```bash
sudo wg show
ping -c 3 10.9.0.2
ip route | grep 10.9.0
ss -ltn | grep 8888    # SpoofDPI — на адресе docker0, не 0.0.0.0
sudo ufw status verbose
```

Крупный ping с DF (MTU туннеля):

```bash
ping -M do -s 1372 10.9.0.2
```

---

## Этап 6 — копия данных (участие A)

Писатели MinIO/LGTM/OpenHub **ещё на A**. На **B** лежит прогрев и дампы; на диске A **вторую полную копию** томов не держать (~18 ГБ свободно).

**На A** от `deploy` только dump. `umask 077` — иначе файл в `/tmp` читается всеми. Забирает его оператор на B и сразу удаляет с A; туда же, через `sudo rsync`, уезжают `.env`, `web/certbot/conf` (закрытые ключи — `root:root` `0600`, симлинки `live/` сохраняются) и `docker volume ls`. Команды — [operator-manual-B.md](operator-manual-B.md), этап 6.

```bash
cd /opt/oscript
umask 077
./ops/dc.sh exec -T openhub_db pg_dump -Fc -U openhub openhub > /tmp/openhub-$(date +%F).dump
chmod 600 /tmp/openhub-$(date +%F).dump
```

Rsync томов запускают **с B** в каталоги Docker-томов (`os_minio_data`, `os_lgtm_data`), команды — [operator-manual-B.md](operator-manual-B.md). Пока сервисы на A работают — это прогрев без `--delete`. Финальный проход с `--delete` — после `stop` в окне этапа 7. На A вторую копию томов не собирают.

Критерий этапа 6: на B dump открывается (`pg_restore --list`), архив `.env` и `certbot/conf` лежат в `/var/lib/oscript-migration/`. Прогрев томов — подготовка этапа 7, не этот шаг.

---

## Этап 7 — окно сплита (действия на A)

Кратко; детали — [глава 6](06-work-order.md). Координация с B обязательна.

**Подготовка (A работает):** на B уже прогреты тома; на A в `.env` по-прежнему `colocated.yml`.

**В окне на A:**

1. Пауза StatusCake; при необходимости 503 на hub/s3/grafana в nginx.
2. `./ops/dc.sh stop openhub` (писатель в MinIO).
3. `./ops/dc.sh stop minio lgtm` (без `down -v`).
4. После финального rsync с B — пересобрать nginx (vhost s3/grafana лежат **в образе**, на живом A ещё `proxy_pass` через переменную; без сборки туннель не заработает) и сменить оверлей в `.env`:

```bash
./ops/dc.sh build nginx
```

```bash
COMPOSE_FILE=compose/node_a.compose.yaml:compose/overrides/split.yml
```

5. На A:

```bash
./ops/dc.sh up -d --remove-orphans
./ops/dc.sh exec nginx nginx -s reload
```

6. Проверить, что контейнеров `os_minio_1` / `os_lgtm_1` на A **нет**; nginx и openhub ходят на B по туннелю.

**Откат окна** (пока на B не писали новые данные): остановить minio/lgtm на B → вернуть на A `colocated.yml` → `./ops/dc.sh up -d` minio lgtm на старых томах.

---

## Этап 8 — приёмка (проверки с A и снаружи)

- Публичные URL s3, Grafana, hub, страница пакета, установка с hub.
- Tempo: trace nginx → openhub.
- Prometheus: метрики stub_status nginx.
- Grafana: hostmetrics A и B, datasource OpenHub.
- `./ops/dc.sh exec certbot certbot renew --dry-run`
- Перезагрузка A: `wg0` и контейнеры поднимаются без ручных шагов.

---

## Старый хаб (hub-old) — в любой день, без окна

См. раздел «Старый хаб» в [главе 6](06-work-order.md). Логи: `/opt/oscript/logs/nginx`. Том **`os_postgres_data` не удалять**.

---

## Рутина после этапа 3

| Задача | Команда |
| --- | --- |
| Обновить код | `git pull` (ветка `feature/multi-host`, пока не влито в master) |
| Поднять/пересоздать | `./ops/dc.sh up -d` |
| Сборка nginx | `./ops/dc.sh build nginx && ./ops/dc.sh up -d nginx` |
| Сертификат нового домена | правка `web/nginx/sites-enabled/`, затем `./add-letsencrypt-domain.sh <домен>` |
| Логи | `./ops/dc.sh logs -f <сервис>` |

Роль Ansible **`app`** на A — только после обкатки на B и с `-e deploy_ref=feature/multi-host`; первый прогон с **`--check`**, без `app_compose_up`, пока не согласовано с [главой 4](04-ansible.md).

---

## Чего на A не делать

- Не checkout `feature/multi-host` до готовности коммита 3 в origin и до начала окна этапа 3.
- Не ставить/обновлять Docker и `docker compose` plugin без отдельного решения.
- Не запускать `ansible-playbook` локально на A как control node (control — B).
- Не удалять тома `os_*` и не менять `COMPOSE_PROJECT_NAME`.
