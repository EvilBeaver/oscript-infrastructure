# Инструкция оператора: нода A (edge)

Публичный edge: nginx, сайт, Jenkins, OpenHub, certbot, бот, s3-sync. До окна сплита (этап 7) на A же живут MinIO и LGTM (колокация). Каталог стека — **`/opt/oscript`**, пользователь **`deploy`**, группа **`docker`**.

Полная книга: [оглавление](README.md) · этапы [глава 6](06-work-order.md) · Ansible [глава 4](04-ansible.md) (плейбуки **запускаются с B**, не с A).

---

## Где остановились (2026-11-01)

Этап 3 выполнен. Окно заново не открывать. Этапы 4–6 тоже закрыты (2026-11-01), нода B готова. Следующая работа — этап 7, окно сплита; compose на A до него не трогать. Сводка для агента — [оглавление](README.md).

| Что | Сейчас на проде A |
| --- | --- |
| Ветка в `/opt/oscript` | `feature/multi-host`, коммит `fc48f60` |
| Подъём стека | `./ops/dc.sh` (`docker compose` v2.40.3). `docker-compose` v1.23.2 на диске есть, для этого каталога не используется |
| `.env` | `COMPOSE_PROJECT_NAME=os` и `COMPOSE_FILE=compose/node_a.compose.yaml:compose/overrides/colocated.yml`. Режим **`770`**, владелец `deploy`, группа **`oscript`**. Так и оставить |
| Чего в `.env` нет специально | `OTEL_HOST_NAME`, `DOCKER_GID`. В модулях подставляются `oscript.io` и группа `995` |
| Что в `.env` осталось от старого стека | ключи вроде `GITTER_*`, `GITHUB_*`, `PGADMIN_*`, `OSHUB_*`, `POSTGRES_*`, `OSWEB_*`. Образец `env/node_a.env.example` поверх файла не копировали и не копировать |
| Копия до правки | домашний каталог `andrei`, файл `.env.before-stage3` |
| Тома и контейнеры | тома `os_*` те же. Рабочие контейнеры `os_*_1` пересозданы и подняты. `os_opm_hub_1` и `os_opm_hub_db_1` — Exited; в окне их не удаляют, `--remove-orphans` не используют. Том `os_postgres_data` не удалять |
| `10.9.0.0/24` | туннеля нет. В собранном config эти адреса только в `NO_PROXY` Jenkins (`compose/apps/jenkins.yml`) |

Роль Ansible `app` с `app_apply=true` на A не запускать. Шаблон `env-node_a.j2` перезаписывает `.env` целиком: старые ключи пропадут, режим станет `0640`, группа — `docker`.

---

## Чеклист состояния ноды A (сверено 2026-11-01, 18:10 UTC)

`[x]` — проверено командами на живой ноде (`git rev-parse`, `docker ps`, `docker inspect`, `wg show`, `ufw status verbose`, `iptables -S DOCKER-USER`, `ss -lntp`), а не по документам. Пустой `[ ]` — не сделано или сознательно не делалось.

### Каталог, вход, стек

- [x] `/opt/oscript` — ветка `feature/multi-host`, коммит **`fc48f60`**. Дерево отслеживаемых файлов чистое (untracked `env-a-before-split.bak`).
- [x] `.env`: `COMPOSE_PROJECT_NAME=os` и `COMPOSE_FILE=compose/node_a.compose.yaml:compose/overrides/colocated.yml`; 35 ключей; режим `770`, владелец `deploy`, группа `oscript`.
- [x] Вход — `./ops/dc.sh`, плагин `docker compose` v2.40.3. Engine — **18.09.0** (API 1.39): не обновлять, новых флагов вида `--wait` не использовать.
- [x] Этап 3 закрыт: 11 контейнеров `os_*_1` в состоянии `Up`. `os_opm_hub_1` и `os_opm_hub_db_1` — `Exited (0)` с 2026-09-20 и 2026-08-14; не удалять, `--remove-orphans` не применять ни в окне этапа 3, ни в окне этапа 7 (проверено `--dry-run`: без флага они только попадают в список orphan-предупреждения и остаются).
- [x] Тома `os_*` на месте, томов с чужим префиксом не появилось.
- [x] Снимки для отката лежат: `/home/deploy/ufw-before-split.txt`, `/home/deploy/iptables-before-split.txt`.
- [x] Копия `.env` до правки этапа 3 — **`/home/andrei/.env.before-stage3`**.

### Туннель (этап 5, часть A)

- [x] `wg0`: `10.9.0.1/24`, listen `51820`, peer `dTzhCMch…` (совпадает с `wireguard_node_b_public_key` из vault), `latest handshake` свежий, счётчики растут.
- [x] `wg-quick@wg0` — `enabled`; drop-in `/etc/systemd/system/docker.service.d/wg.conf` (`After=` и `Wants=wg-quick@wg0.service`) на месте.
- [x] `iperf3` установлен; пропускная способность через туннель — **94.6–94.9 Мбит/с**.
- [x] Роль `wireguard` прогонялась с B (`--tags wg --limit node_a`). Оговорка: каталог `/etc/systemd/system/docker.service.d` пришлось создать вручную — первый прогон на нём падал. `wg0` поднят: `10.9.0.1/24`, listen `51820`, handshake с B есть, пропускная способность 94.6–94.9 Мбит/с.
- [ ] Мусор подготовки не убран: `/etc/wireguard/wg0.key` и `wg0.pub` (2026-10-31, публичный ключ `aRhzorE…`) — **не** из vault. Роль их не читает (она пишет `privatekey`), но поднимать туннель ими нельзя: handshake не пройдёт.
- [ ] Перезагрузка A не проводилась — это отдельное окно этапа 5; на A она гасит весь публичный стек.

### Файрвол и SpoofDPI

- [x] ufw активен: снаружи `22`, `80`, `443`, `50000/tcp`; `8888/tcp` — только из `172.17.0.0/16`; `51820/udp` — только с `94.228.175.127`.
- [x] В живых правилах `DOCKER-USER` — RETURN для established, RETURN для `80,443,50000` с `eth0`, DROP для остального с `eth0`. Случайные публикации Docker (`32777–32779`) снаружи закрыты (проверено `nmap` с B).
- [ ] Роль `firewall` на A ещё не прогонялась. В `/etc/ufw/after.rules` есть ровно одно объявление `:DOCKER-USER`, но без маркеров (проверено `grep -c '^:DOCKER-USER'` → 1, `BEGIN/END oscript` не найдено). Роль это забирает через adopt-скрипт: объявление цепочки остаётся одно, существующие правила переезжают в блок `# BEGIN/END oscript DOCKER-USER`. Повторный прогон файл не меняет. Первый прогон по-прежнему без штампа — `-e firewall_rollback_minutes=10` и вторая SSH-сессия, затем `--tags firewall_confirm`.
- [ ] Штампа `/var/lib/oscript/firewall-confirmed` на A нет; пакеты `at` и `iptables-persistent` не установлены (роль ставит их на xenial).
- [ ] Роль `spoofdpi` не прогонялась: `spoof-dpi.service` слушает `:::8888`, то есть `0.0.0.0`. Роль переводит bind на адрес `docker0` (`172.17.0.1`).
- [ ] Таймера отката `at` нет — при будущем прогоне фазы 2 держать вторую SSH-сессию (`atq` на A даже не установлен).

### Образы и данные

- [x] Образ запущенного `os_openhub_1` — `segateekb/openhub:0.23.0`, совпадает со строкой `image` в `compose/apps/openhub.yml`.
- [x] Этап 6 (участие A): `pg_dump -Fc` базы OpenHub снят, копия `.env` и `web/certbot/conf` увезены на B, дамп с A удалён.
- [ ] Образ nginx **не пересобран**: живой `nginx-simple:latest` — ID `7cd2054f805c` от 2026-10-15, в vhost `s3.oscript.io` и `grafana.oscript.io` стоит `proxy_pass $target_url` с `resolver`. Пересборка в окне обязательна, иначе адреса туннеля не заработают.
- [x] Тег `nginx-simple:pre-split` **создан** 2026-11-01: указывает на `7cd2054f805c` — тот же ID, что у `latest` и `otel-all` (образ от 2026-10-15). Репетиция сборки лежит отдельно как `split-rehearsal`. Возврат при отказе: `docker tag nginx-simple:pre-split nginx-simple:latest && ./ops/dc.sh up -d --force-recreate nginx`.
- [ ] Судьба vhost `hub-old.oscript.io` не решена владельцем: в живом образе он есть (сейчас отдаёт 502), в текущем чекауте его нет — пересборка сменит ответ на 444. Решение по умолчанию (если владелец не скажет иначе) — принять как осознанное изменение и записать в протокол окна.
- [ ] Оверлей `split.yml` не подключён; `minio`, `lgtm`, `hostmetrics` всё ещё на A. Адреса `10.9.0.x` в боевом config — только `NO_PROXY` Jenkins.
- [x] Публикации `10.9.0.1:8080` (nginx_status) и `10.9.0.1:5432` (база для Grafana) не подняты — их включает `split.yml` в окне. Сейчас на `10.9.0.1` из этих портов не слушает ничего.

### Дефект hostmetrics: правка в репозитории, контейнер на A ещё на старом inode

- [ ] **Пересоздать `os_hostmetrics_1` после выкладки правки** (`fc48f60`, на A уже выкачена). Проверено на A: контейнер `Up` с 2026-11-01 15:21 MSK, но bind-mount одного файла держит прежний inode `1190985` — в нём `api_version` ещё нет вовсе, и `docker_stats` пишет в лог `Error scraping metrics … EOF`. То есть процесс жив, а метрики по контейнерам с него не идут. Файл на диске (inode `1191056`) уже новый. В конфиге теперь `api_version: ${env:DOCKER_STATS_API_VERSION}` без `:-1.25`: коллектор 0.104.0 такой суффикс отвергает и падает. Сборка A подставляет `1.25` из `compose/apps/hostmetrics.yml`. Команда: `./ops/dc.sh up -d --force-recreate hostmetrics`. Пока на диске остаётся старый файл с `:-1.25`, пересоздание роняет контейнер — сейчас файл уже правильный.

### Как перепроверить

```bash
ssh deploy@212.109.194.11 'cd /opt/oscript && git rev-parse --short HEAD; docker ps --format "{{.Names}} {{.Status}}" | sort'
ssh deploy@212.109.194.11 'sudo -n wg show; sudo -n ufw status verbose; sudo -n iptables -S DOCKER-USER'
ssh deploy@212.109.194.11 'docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | grep nginx-simple'
```

---

## Общие правила на A

- Работы со стеком — от **`deploy`** в **`/opt/oscript`**. `.env` в git не входит; при откате его **не** откатывают через git.
- **`down -v` не выполнять** — тома `os_*` общие для всех этапов.
- Плагин **`docker compose` v2.40.3** уже есть; **не обновлять**. Engine — **18.09.0**. Проверка: `docker version` и `docker compose version`. Новые флаги вроде `--wait` на этом Engine не использовать.
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

4. Пауза проверок StatusCake в их кабинете **не требуется** (решение владельца 2026-11-01): короткая недоступность проверок допустима.

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

Писатели MinIO/LGTM/OpenHub **ещё на A**. На **B** лежит прогрев и дампы; на диске A **вторую полную копию** томов не держать (~30 ГБ свободно, тома minio 2.2 ГБ и lgtm 7.5 ГБ — вторая копия их не окупает).

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

Кратко; общий порядок — [глава 6](06-work-order.md). Координация с B обязательна. На A заходят как `deploy`: у `andrei` нет беспарольного sudo.

**До окна, A продолжает работать.**

1. Сверить образ OpenHub. Окно не начинают, если тег отличается от `compose/apps/openhub.yml`:

```bash
docker inspect os_openhub_1 --format '{{.Config.Image}}'
```

2. Собрать новый образ nginx. Vhost s3/grafana лежат в образе; живой образ от 2026-10-15 ещё использует `proxy_pass` через переменную. Тег `nginx-simple:pre-split` **уже создан** на `7cd2054f805c` (проверено), команду `docker tag` повторять не нужно. Сборка переписывает тег `nginx-simple:latest`; контейнер при этом не пересоздают: до окна остаётся прежний процесс.

```bash
cd /opt/oscript
docker image inspect nginx-simple:pre-split >/dev/null   # должно быть OK
docker image inspect nginx:1.30.5-otel >/dev/null
./ops/dc.sh build nginx
./ops/dc.sh exec nginx nginx -t
```

Успешная сборка переводит `latest` на новый ID; при ошибке сборки тег не меняется. Новый образ в этой подготовке не запускают, оверлей не меняют. Проверяют именно новый образ, а не процесс, который ещё работает на старом:

```bash
docker run --rm \
  -v /opt/oscript/web/certbot/conf:/etc/letsencrypt:ro \
  nginx-simple:latest nginx -t
```

3. Снять передачу из контейнерной сети на B. На B в это время слушает `iperf3 -s -B 10.9.0.2 -1`. Сеть проекта — `os_default`:

```bash
docker run --rm --network os_default alpine:3.20 \
  sh -c 'apk add --no-cache iperf3 && iperf3 -c 10.9.0.2 -t 10'
```

Короткий замер с хоста эту проверку не заменяет: у `docker0` MTU 1500, у `wg0` — 1420. Сейчас правила MSS clamp в `FORWARD` **нет** (проверено `iptables -t mangle -S FORWARD`), поэтому проверку из контейнера делают обязательно: обходной путь ниже — реакция на проблему, а не штатный шаг. Если передача зависнет или скорость обвалится относительно замера с хоста:

```bash
sudo iptables -t mangle -C FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN \
  -j TCPMSS --clamp-mss-to-pmtu \
  || sudo iptables -t mangle -A FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN \
  -j TCPMSS --clamp-mss-to-pmtu
```

Правило не переживает перезагрузку. `ufw route allow` для туннеля не добавляют.

**В окне на A.** Сначала останавливают писателей и только потом на B делают финальный rsync:

1. `./ops/dc.sh stop openhub`, затем `./ops/dc.sh stop minio lgtm`. `down` и `down -v` нет. Дальше работает B: финальный rsync с `--delete` и `up -d` minio, lgtm, hostmetrics.
2. Когда Grafana на B отвечает, скопировать `.env` и заменить в самом файле одну строку. Присваивание `COMPOSE_FILE=...` только в оболочке файл не меняет.

```bash
cp -a /opt/oscript/.env /opt/oscript/.env.pre-split
```

Строка после правки: `COMPOSE_FILE=compose/node_a.compose.yaml:compose/overrides/split.yml`. Режим остаётся `770`, владелец `deploy`, группа `oscript`.

3. Проверить рендер и поднять стек без `--remove-orphans`:

```bash
./ops/dc.sh config
./ops/dc.sh up -d
./ops/dc.sh exec nginx nginx -s reload
docker rm os_minio_1 os_lgtm_1
```

`config` содержит `minio:10.9.0.2`, `lgtm:10.9.0.2`, `10.9.0.1:8080` и `10.9.0.1:5432`. `docker rm` снимает только остановленные контейнеры переехавших сервисов; если такого контейнера уже нет, шаг считается выполненным. `os_opm_hub_1` и `os_opm_hub_db_1` остаются. Postgres пересоздаётся из-за новой публикации порта; OpenHub ждёт `pg_isready`.

4. Проверить `getent hosts minio lgtm` внутри nginx (оба имени — `10.9.0.2`) и что контейнеров minio/lgtm на A нет. Тома `os_minio_data` и `os_lgtm_data` на месте.

Сборка нового nginx убирает vhost `hub-old.oscript.io`: вместо 502 соединение закрывается без ответа (444). Сертификат и DNS этого имени снимают отдельно, после приёмки.

**Откат**, пока B не принял новых записей: остановить minio и lgtm на B, вернуть строку `COMPOSE_FILE` из `.env.pre-split` и выполнить `./ops/dc.sh up -d`. Если тег nginx уже новый:

```bash
docker tag nginx-simple:pre-split nginx-simple:latest
./ops/dc.sh up -d --force-recreate nginx
```

После старта сервисов на B откат — новое окно с обратным rsync. Команды — [operator-manual-B.md](operator-manual-B.md).

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
| Сборка nginx | `./ops/dc.sh build nginx && ./ops/dc.sh up -d nginx`. До окна этапа 7 контейнер не пересоздают: сначала тег `pre-split`, сборка и `nginx -t` нового образа |
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
