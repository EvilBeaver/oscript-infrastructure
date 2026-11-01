# Инструкция оператора: нода A (edge)

Публичный edge: nginx, сайт, Jenkins, OpenHub, certbot, бот, s3-sync. До окна сплита (этап 7) на A же живут MinIO и LGTM (колокация). Каталог стека — **`/opt/oscript`**, пользователь **`deploy`**, группа **`docker`**.

Полная книга: [оглавление](README.md) · этапы [глава 6](06-work-order.md) · Ansible [глава 4](04-ansible.md) (плейбуки **запускаются с B**, не с A).

---

## Где остановились (2026-11-01)

Этап 3 выполнен. Окно заново не открывать. Следующая работа — этап 4 на ноде B, compose на A не трогать. Сводка для агента — [оглавление](README.md).

| Что | Сейчас на проде A |
| --- | --- |
| Ветка в `/opt/oscript` | `feature/multi-host`, коммит `7549e12` |
| Подъём стека | `./ops/dc.sh` (`docker compose` v2.40.3). `docker-compose` v1.23.2 на диске есть, для этого каталога не используется |
| `.env` | `COMPOSE_PROJECT_NAME=os` и `COMPOSE_FILE=compose/node_a.compose.yaml:compose/overrides/colocated.yml`. Режим **`770`**, владелец `deploy`, группа **`oscript`**. Так и оставить |
| Чего в `.env` нет специально | `OTEL_HOST_NAME`, `DOCKER_GID`. В модулях подставляются `oscript.io` и группа `995` |
| Что в `.env` осталось от старого стека | ключи вроде `GITTER_*`, `GITHUB_*`, `PGADMIN_*`, `OSHUB_*`, `POSTGRES_*`, `OSWEB_*`. Образец `env/node_a.env.example` поверх файла не копировали и не копировать |
| Копия до правки | домашний каталог `deploy`, файл `.env.before-stage3` |
| Тома и контейнеры | тома `os_*` те же. Рабочие контейнеры `os_*_1` пересозданы и подняты. `os_opm_hub_1` и `os_opm_hub_db_1` — Exited, не удалять |
| `10.9.0.0/24` | туннеля нет. В собранном config эти адреса только в `NO_PROXY` Jenkins (`compose/apps/jenkins.yml`) |

Роль Ansible `app` с `app_apply=true` на A не запускать. Шаблон `env-node_a.j2` перезаписывает `.env` целиком: старые ключи пропадут, режим станет `0640`, группа — `docker`.

---

## Общие правила на A

- Работы со стеком — от **`deploy`** в **`/opt/oscript`**. `.env` в git не входит; при откате его **не** откатывают через git.
- **`down -v` не выполнять** — тома `os_*` общие для всех этапов.
- Плагин **`docker compose` v2.40.3** уже есть; **не обновлять**. Проверка: `docker compose version`.
- Ansible-модули на A: **`/opt/python3/bin/python3 --version`** (3.12). Системный `/usr/bin/python3` (3.5.2) для Ansible не использовать.
- Плейбуки с ролями `firewall`, `wg`, `spoofdpi` на A **запускает оператор с ноды B** (см. [operator-manual-B.md](operator-manual-B.md)). На A можно только проверять результат (`ufw status`, `wg show`, `ss`).

---

## Как A управляется через Ansible

На A не устанавливают команду `ansible-playbook` и не запускают плейбуки. Ansible работает по модели «управляющая машина → управляемая машина»:

```text
B (control node, пользователь deploy)
  → SSH по отдельному ключу
A (managed node, пользователь deploy)
  → sudo без пароля
системные файлы и службы A
```

Оператор запускает команду на B. Ansible подключается к A как `deploy`, загружает небольшой временный модуль через SSH, запускает его указанным Python и удаляет временные файлы. Для системных действий модуль вызывает `sudo`.

Отсюда следуют важные практические правила:

- ошибки подключения к A диагностируют сначала обычным `ssh` с B;
- пароль пользователя `deploy` Ansible не нужен: используется SSH-ключ;
- пароль `sudo` не передаётся: для технического пользователя настроен `NOPASSWD`;
- `/opt/python3/bin/python3` на A — интерпретатор удалённых модулей, а не установленный здесь Ansible;
- inventory, пароль vault и исходный `vault.yml` остаются на B.

### Где оказываются секреты

На B хранится зашифрованный `vault.yml`, содержащий пароли приложений и обе пары ключей WireGuard. На A весь vault не копируется.

При выполнении конкретной роли на A попадает только необходимый результат:

- приватный ключ WireGuard записывается в `/etc/wireguard/privatekey`, `root:root`, режим `0600`;
- конфигурация `/etc/wireguard/wg0.conf` также доступна только root;
- роль `app` при явном `app_apply=true` формирует `/opt/oscript/.env`, `deploy:docker`, режим `0640`. На 2026-11-01 роль не применялась: живой файл другой, см. «Где остановились». Пока её не запускать;
- SSH-приватный ключ остаётся на B; на A находится только его публичная часть в `authorized_keys`.

Действующий `/opt/oscript/.env` на A — источник существующих паролей при подготовке vault. Эти значения нельзя без причины заменить новыми: MinIO, OpenHub, Jenkins, Grafana, Telegram и внешний S3 уже используют их. Порядок создания vault и перечень переменных описаны в разделе «Inventory и vault» инструкции B.

### Как читать команды в двух инструкциях

Перед блоком команд всегда проверяйте, на какой машине он выполняется:

- «на A» — текущая SSH-сессия к A, обычно `deploy@A`;
- «на B» — SSH-сессия к B, тоже под `deploy`;
- «с B на A» — команда запускается в оболочке B и сама подключается к A;
- `ansible-playbook ... --limit node_a` — команда запускается только на B, а изменяет A.

Рекомендуется держать разные терминалы с заметными prompt/цветами. Ошибка ноды особенно опасна в командах `rsync`, при редактировании `.env` и при работе с Docker-томами.

---

## Этап 3 — переключение на модульный compose (выполнен 2026-11-01)

Окно закрыто, сайты после `./ops/dc.sh up -d` открываются. Команды ниже не повторять. Раздел оставлен как запись окна и как откат.

**Цель была:** тот же однонодовый стек, те же тома и URL, сборка через `ops/dc.sh` и модули. Туннель **не нужен**.

До этого этапа один монолитный Compose-файл описывает весь стек. После переключения конфигурация собирается из двух частей:

- `compose/node_a.compose.yaml` — постоянный набор сервисов A;
- `compose/overrides/colocated.yml` — временно добавляет MinIO и LGTM на A.

Переменная `COMPOSE_FILE` соединяет эти файлы через `:`. `ops/dc.sh` является единой обёрткой над `docker compose`: она гарантирует, что используется Compose v2 и конфигурация из `.env`. `COMPOSE_PROJECT_NAME=os` сохраняется, поэтому Compose находит прежние контейнеры и тома с префиксом `os_`, а не создаёт параллельный пустой стек.

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

В **`.env`** добавить строку (остальное не трогать). Права на живом файле были `770`, владелец `deploy`, группа `oscript`; в окне их не меняли:

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

WireGuard создаёт приватный интерфейс `wg0`:

```text
A: 10.9.0.1  ← зашифрованный туннель через интернет →  10.9.0.2 :B
```

WireGuard на A слушает UDP 51820, а ufw и security group пропускают на этот порт пакеты только с публичного IP B. B инициирует соединение с A и не открывает собственный входящий порт WireGuard. После сплита публичный nginx остаётся на A, а к MinIO и LGTM на B ходит по адресу `10.9.0.2`.

`wg show` должен показывать `latest handshake`: это признак успешной взаимной аутентификации ключами. `ping` проверяет уже передачу IP-пакетов внутри созданного туннеля. Нужны обе проверки.

**Приёмка с A** (после прогона с B):

```bash
sudo wg show
ping -c 3 10.9.0.2
ip route | grep 10.9.0
ss -ltn | grep 8888    # SpoofDPI — на адресе docker0, не 0.0.0.0
sudo ufw status verbose
```

Что означает результат:

- в `wg show` есть peer B, непустой `latest handshake` и растут счётчики transfer;
- `ping 10.9.0.2` отвечает — маршрут и firewall туннеля работают;
- `ip route` показывает сеть `10.9.0.0/24` через `wg0`;
- SpoofDPI слушает `8888` на адресе `docker0`, но не на публичном `0.0.0.0`;
- ufw включён, SSH и публичные порты сайта разрешены, UDP 51820 ограничен адресом B.

Крупный ping с DF (MTU туннеля):

```bash
ping -M do -s 1372 10.9.0.2
```

`-M do` запрещает фрагментацию. `-s 1372` задаёт размер данных ICMP; вместе с IPv4- и ICMP-заголовками пакет имеет размер 1400 байт. Это консервативная проверка для MTU 1420 интерфейса WireGuard: остаётся запас 20 байт. Успех показывает, что путь пропускает крупный пакет без фрагментации; обычный короткий ping эту проблему не обнаруживает. Теоретический максимум `ping -s` для MTU 1420 и IPv4 — 1392, но операционная проверка намеренно использует меньшее значение.

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

## Рутина на A сейчас

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

- Не возвращаться на `master` и не снимать `COMPOSE_FILE`, пока не решили откат этапа 3.
- Не менять оверлей на `split.yml` до окна этапа 7.
- Не запускать роль `app` с `app_apply=true`: она затрёт живой `.env`.
- Не ставить/обновлять Docker и `docker compose` plugin без отдельного решения.
- Не запускать `ansible-playbook` локально на A как control node (control — B).
- Не удалять тома `os_*` и не менять `COMPOSE_PROJECT_NAME`.
