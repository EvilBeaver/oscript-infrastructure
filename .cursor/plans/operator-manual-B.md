# Инструкция оператора: нода B (worker, control Ansible)

**Нода B** — Ubuntu 24.04, будущий дом для MinIO, LGTM и hostmetrics (после этапа 7). Здесь же **control node Ansible**: все `ansible-playbook` выполняются **на B** под **`deploy`**, в том числе для изменений на A по SSH.

Каталог стека: **`/opt/oscript`**. Секреты вне git: **`/opt/oscript-secrets/`** (`vault.yml`, `vault_pass`). Боевой **`ansible/inventory.ini`** только на B.

Книга: [оглавление](README.md) · Ansible [глава 4](04-ansible.md) · этапы [глава 6](06-work-order.md) · работы на A [operator-manual-A.md](operator-manual-A.md).

---

## Роли B в миграции

| Этап | Что делает оператор на B |
| --- | --- |
| 4 | Первичная настройка B, inventory, vault, `common` + `firewall`, iperf3 |
| 5 | `wireguard` + `firewall`/`spoofdpi` на **обеих** нодах (команды с B) |
| 6 | Dump OpenHub, архив `.env` и certbot с A (байты томов — в подготовке этапа 7) |
| 7 | Тома compose, rsync, `up` minio/lgtm/hostmetrics на B |
| 8 | Приёмка, nmap снаружи на B, проверка портов |

Этап 3 (модульный compose на A) можно выполнить **до или после** этапа 4; этап 7 ждёт **и** этап 3 на A, **и** туннель (этап 5).

---

## Однократная подготовка B (до первого плейбука)

Выполняется **вручную** один раз, от root консоли провайдера, затем от **`deploy`**. Роль `common` эти шаги не заменяет. `--tags common` повторно ставит Docker CE, если репозиторий Docker уже описан ниже. Плейбук **без** `--tags` на пустой B останавливается на проверке `docker version` и до установки не доходит: задачи установки помечены `never`.

### 1. Пользователь `deploy`

```bash
adduser --disabled-password --gecos "" deploy
echo 'deploy ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy
visudo -cf /etc/sudoers.d/deploy
```

Группу `docker` добавляют после установки Engine (шаг 2). Ключ **`~/.ssh/oscript_deploy`** создаёт `deploy`. Публичная часть на **A** в `~deploy/.ssh/authorized_keys`:

```text
from="<публичный_IP_B>" ssh-ed25519 AAAA... deploy@oscript-b
```

Проверка с B (уже под `deploy`):

```bash
ssh -i ~/.ssh/oscript_deploy deploy@<IP_A> sudo -n true
ssh -i ~/.ssh/oscript_deploy deploy@<IP_A> /opt/python3/bin/python3 --version
```

### 2. Docker CE

Репозиторий Docker, затем пакеты. Группа `docker` появляется вместе с Engine.

```bash
apt-get update
apt-get install -y ca-certificates curl gnupg rsync
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker deploy
```

Проверка — **новой SSH-сессией** под `deploy` (`sudo -u` из root группу `docker` не подхватывает):

```bash
id
docker version
docker compose version
sudo -n true
```

В `id` есть группа `docker`.

### 3. Ansible (pipx, не apt)

Под `deploy`:

```bash
sudo apt-get install -y pipx
pipx ensurepath
```

Выйти и зайти по SSH снова. `command -v ansible` должен указывать на `/home/deploy/.local/bin/ansible`. Если каталога нет в `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

и проверить, что `~/.bashrc` от `pipx ensurepath` подхватывается логином.

```bash
pipx install 'ansible-core==2.18.11'
ansible --version
```

Коллекции — после клона (шаг 4): `ansible/requirements.yml` ставится через Galaxy, не через pip.

```bash
ansible-galaxy collection install -r /opt/oscript/ansible/requirements.yml
```

Ожидаемые версии — в [`ansible/group_vars/all.yml`](../../ansible/group_vars/all.yml): core **2.18.11**, `community.docker` **4.8.2**, `community.general` **10.7.6**.

### 4. Клон репозитория

```bash
sudo mkdir -p /opt/oscript
sudo chown deploy:docker /opt/oscript
sudo chmod 2755 /opt/oscript
sudo git config --system --add safe.directory /opt/oscript

sudo -u deploy git clone https://github.com/EvilBeaver/oscript-infrastructure.git /opt/oscript
cd /opt/oscript
sudo -u deploy git checkout feature/multi-host
sudo -u deploy git pull
```

На время миграции **`deploy_ref=feature/multi-host`**. После приёмки — `master`.

### 5. Inventory и vault

Каталог секретов и пароль vault — **до** шифрования. `ansible-vault encrypt` без `--vault-password-file` спросит пароль интерактивно; его легко разойтись с файлом `vault_pass`.

```bash
sudo mkdir -p /opt/oscript-secrets
sudo chown deploy:deploy /opt/oscript-secrets
sudo chmod 700 /opt/oscript-secrets

install -m 0600 /dev/null /opt/oscript-secrets/vault_pass
# одна строка пароля, без пробела в конце
chmod 0400 /opt/oscript-secrets/vault_pass

cp /opt/oscript/ansible/vault.example.yml /opt/oscript-secrets/vault.yml
# заполнить секреты в открытом файле; четыре ключа WireGuard — см. этап 5, до первого --tags wg
ansible-vault encrypt /opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass
```

Дальше правка только через `ansible-vault edit --vault-password-file /opt/oscript-secrets/vault_pass`.

Inventory — правка копии примера. Строка хоста **одна**, без обратных слэшей: INI их не склеивает. У `node_b` соединение локальное. `public_ip` нужен на обеих строках: firewall на A берёт адрес B из inventory.

```bash
cp /opt/oscript/ansible/inventory.example.ini /opt/oscript/ansible/inventory.ini
```

```ini
[oscript:children]
edge
worker

[oscript:vars]
inventory_is_example=false

[edge]
node_a ansible_host=<IP_A> public_ip=<IP_A> ansible_user=deploy ansible_python_interpreter=/opt/python3/bin/python3 ansible_ssh_private_key_file=/home/deploy/.ssh/oscript_deploy

[worker]
node_b ansible_connection=local ansible_user=deploy public_ip=<IP_B>
```

### 6. Проверка связи

```bash
cd /opt/oscript
export ANSIBLE_CONFIG=/opt/oscript/ansible.cfg
ansible all -m ping \
  -e @/opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass
```

Syntax-check (без хостов):

```bash
./ansible/test/run.sh
# или локально:
ansible-playbook --syntax-check -i ansible/inventory.example.ini ansible/site.yml
```

---

## Шаблон команд Ansible

Рабочий каталог — **`/opt/oscript`**. Задачи ролей, меняющих хост, помечены **`never`**: без `--tags` они не выполняются.

В `--tags` передают **только тег роли**. Слово `never` туда не добавляют: `--tags firewall,never` выполняет все роли с тегом `never` (проверено `--list-tasks`).

```bash
cd /opt/oscript
export ANSIBLE_CONFIG=/opt/oscript/ansible.cfg

VAULT="-e @/opt/oscript-secrets/vault.yml --vault-password-file /opt/oscript-secrets/vault_pass"
REF="-e deploy_ref=feature/multi-host"

ansible-playbook ansible/site.yml $VAULT $REF --tags firewall --limit node_b -e firewall_rollback_minutes=10
```

Первый прогон `firewall` на хосте без штампа `/var/lib/oscript/firewall-confirmed` требует `-e firewall_rollback_minutes=10` (роль ставит `at` → `ufw disable`). Подтверждение — **отдельная** команда, когда SSH проверен:

```bash
ansible-playbook ansible/site.yml $VAULT $REF --tags firewall_confirm --limit node_b
```

`--skip-tags firewall_confirm` не нужен: задачи подтверждения не входят в тег `firewall`.

---

## Этап 4 — B как машина и первые роли

**Критерий:** Docker и `deploy` на B, ping до A, ufw на B (default deny), зафиксирован iperf3.

### 4.1. Роль `common`

```bash
ansible-playbook ansible/site.yml $VAULT $REF --tags common
```

На B ставит базовые пакеты и Docker; на A **не переустанавливает** Engine и **не включает** ufw.

### 4.2. iperf3 до файрвола

Пакет на нодах не ставит Ansible, порт **5201** в правилах worker **не открывать** постоянно.

```bash
# на A и на B, пока ufw на B ещё выключен
sudo apt-get install -y iperf3
# на B
iperf3 -s
# на A
iperf3 -c <IP_B> -t 30
```

Записать Mbps. После `ufw` на B этот замер с публичного IP перестанет проходить. Повтор — после туннеля: на B `iperf3 -s -B 10.9.0.2`, на A `iperf3 -c 10.9.0.2`.

### 4.3. Роль `firewall` только на B

Держите SSH-сессию. Первый раз на хосте:

```bash
ansible-playbook ansible/site.yml $VAULT $REF \
  --tags firewall --limit node_b \
  -e firewall_rollback_minutes=10
```

Проверить `ssh` с A и с рабочей станции. Затем снять таймер:

```bash
ansible-playbook ansible/site.yml $VAULT $REF \
  --tags firewall_confirm --limit node_b
```

С интернета на B роль открывает только **22/tcp**. UDP 51820 на B не слушается и в ufw не разрешается.

### 4.4. Диск

Убедиться, что на B достаточно места под прогрев **`os_minio_data`**, **`os_lgtm_data`**, дампы и `/opt/oscript-secrets`.

**Готово этап 4**, когда `ansible node_a -m ping` и `ansible node_b -m ping` зелёные, iperf3 снят до ufw, firewall на B включён и подтверждён (`firewall_confirm`).

---

## Этап 5 — туннель и hardening A

**Compose на обеих нодах не менять.** На A — вторая SSH-сессия, пока не выполнен `firewall_confirm`.

B — **клиент**. `ListenPort 51820` есть только в конфиге A. B ходит исходящим UDP на `публичный_IP_A:51820` (`Endpoint`, `PersistentKeepalive = 25`) и свой порт не слушает. Приёмка туннеля — handshake в `wg show` и ping `10.9.0.1` ↔ `10.9.0.2`.

### Ключи до `--tags wg`

Четыре значения в vault, пока они ещё пустые строки образца: `wireguard_node_a_private_key`, `wireguard_node_a_public_key`, `wireguard_node_b_private_key`, `wireguard_node_b_public_key`. Генерация на B (`wireguard-tools` даёт команду `wg`; пакет `wireguard` роль поставит сама на этапе `wg`):

```bash
sudo apt-get install -y wireguard-tools
umask 077
kdir=$(mktemp -d)
wg genkey | tee "$kdir/a.private" | wg pubkey > "$kdir/a.public"
wg genkey | tee "$kdir/b.private" | wg pubkey > "$kdir/b.public"
ansible-vault edit /opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass
shred -u "$kdir"/* && rm -rf "$kdir"
```

В vault вставляют содержимое четырёх файлов, затем файлы уничтожают. Роль при непустом закрытом ключе копирует его в `/etc/wireguard/privatekey` и `wg genkey` на хостах не вызывает.

Пустой ключ в vault — не процедура. Роль тогда пишет ключ на диск и завершает плей ошибкой. Закрытый ключ при этом попадает в лог Ansible: задача печатает stdout `tee`. Если такой прогон уже случился, новые ключи не генерировать (`creates` оставляет файл). Снять значения с диска, стереть или закрыть лог прогона, вписать пары в vault и повторить `--tags wg`:

```bash
sudo -n cat /etc/wireguard/privatekey
sudo -n sh -c 'wg pubkey < /etc/wireguard/privatekey'
ssh -i ~/.ssh/oscript_deploy deploy@<IP_A> "sudo -n cat /etc/wireguard/privatekey; sudo -n sh -c 'wg pubkey < /etc/wireguard/privatekey'"
```

Перенаправление `<` делает оболочка до `sudo`. Команда `sudo wg pubkey < файл` читает ключ от `deploy` и получает «Permission denied». `sh -c` выполняется уже от root.

Обе пары должны быть в vault до второго прогона: шаблон каждой ноды содержит публичный ключ соседа.

### Security group провайдера

ufw на хосте не заменяет фильтр перед ВМ. Если панель есть:

| Куда | Входящие |
| --- | --- |
| A | UDP **51820** с публичного IP B. 22/80/443/50000 уже открыты для текущего сайта |
| B | TCP **22** для оператора. UDP 51820 не открывать |

Исходящий UDP с B на `A:51820` должен проходить (обычный egress это позволяет).

### Прогоны

Каждый тег отдельно, без `never`:

```bash
ansible-playbook ansible/site.yml $VAULT $REF --tags wg

ansible-playbook ansible/site.yml $VAULT $REF \
  --tags firewall --limit node_a \
  -e firewall_rollback_minutes=10
# SSH на A жив? иначе ждать at (ufw disable) и не подтверждать

ansible-playbook ansible/site.yml $VAULT $REF \
  --tags firewall_confirm --limit node_a

ansible-playbook ansible/site.yml $VAULT $REF --tags spoofdpi --limit node_a
```

**Приёмка** (с B и с A):

```bash
ansible node_a -m command -a 'wg show'
ansible node_a -m command -a 'ping -c 3 10.9.0.2'
ansible node_b -m command -a 'ping -c 3 10.9.0.1'
```

В `wg show` на обоих узлах есть handshake. Порт 51820 на B не проверяют.

Для этапов 6–7 этого достаточно. Перезагрузка сюда не входит.

### Перезагрузка — отдельное окно до этапа 7

Окно не совмещают с этапом 7 и не начинают, пока нет ping по туннелю. Перезагрузка A — простой всего публичного стека (сайт, хаб, Jenkins, s3, Grafana).

1. Перезагрузить **B**. Готово: SSH, `wg show` с handshake, `ping -c 3 10.9.0.1`.
2. Handshake после возврата SSH нет — **A не перезагружать**, этап 7 не начинать.
3. Перезагрузить **A** в объявленное окно. Готово: SSH, открываются `oscript.io` и `hub.oscript.io`, `wg show` с handshake, `ping -c 3 10.9.0.2`, `ufw status` — enabled.
4. SSH или сайты не вернулись — консоль провайдера; плейбуки и compose не трогать. Сайты открываются, а `wg0` нет — этап 7 не начинать: данные остаются на A.

Повтор перезагрузки на приёмке (этап 8) уже с контейнерами, которые слушают адреса туннеля.

---

## Этап 6 — копия на B (dump и архив)

Пока MinIO/LGTM/OpenHub **ещё на A**. Байты томов сюда не кладут: прогрев этапа 7 пишется сразу в каталоги Docker-томов на B, иначе в окне пришлось бы копировать данные дважды.

Каталог архива — **`root:root` `0700`**. Внутри лежат `.env` A и закрытые ключи сертификатов; `deploy` их напрямую не читает.

```bash
sudo install -d -m 0700 -o root -g root /var/lib/oscript-migration
sudo install -d -m 0700 -o root -g root /var/lib/oscript-migration/certbot-conf
```

Дальше с B, тем же ключом, что и rsync томов. `--rsync-path` читает на A от root: `privkey.pem` в `web/certbot/conf` — `root:root` `0600`, у `deploy` чтения нет. Локальный `sudo` записывает те же права на B. Флаг `-a` сохраняет симлинки `live/` → `archive/`; без `-L`, иначе ключи скопируются мимо симлинков и дерево certbot разъедется.

```bash
RSYNC_SSH='ssh -i /home/deploy/.ssh/oscript_deploy -o UserKnownHostsFile=/home/deploy/.ssh/known_hosts'
```

### Dump OpenHub

На **A** от `deploy` (файл в `/tmp` с `umask 077`, иначе он читается всеми). На хосте нет `pg_dump`, только клиент в контейнере:

```bash
cd /opt/oscript
umask 077
./ops/dc.sh exec -T openhub_db pg_dump -Fc -U openhub openhub > /tmp/openhub-$(date +%F).dump
chmod 600 /tmp/openhub-$(date +%F).dump
```

На **B** забрать и убрать копию с A (`YYYY-MM-DD` — дата файла):

```bash
sudo rsync -a --numeric-ids \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  deploy@<IP_A>:/tmp/openhub-YYYY-MM-DD.dump \
  /var/lib/oscript-migration/openhub-YYYY-MM-DD.dump
sudo chmod 0600 /var/lib/oscript-migration/openhub-YYYY-MM-DD.dump
ssh -i ~/.ssh/oscript_deploy deploy@<IP_A> 'rm -f /tmp/openhub-YYYY-MM-DD.dump'
```

Проверка (на хостах нет `pg_restore`; формат custom). Каталог `0700` root, поэтому `docker` тоже через `sudo`:

```bash
sudo docker run --rm -v /var/lib/oscript-migration:/d:ro postgres:17-alpine \
  pg_restore --list /d/openhub-YYYY-MM-DD.dump | head
```

### Архив `.env` и список томов

`.env` с A в этот каталог — архив. Стек B им не запускают: на A другой `COMPOSE_FILE`.

```bash
sudo rsync -a --numeric-ids \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  deploy@<IP_A>:/opt/oscript/.env \
  /var/lib/oscript-migration/env-node-a
sudo chmod 0600 /var/lib/oscript-migration/env-node-a

ssh -i ~/.ssh/oscript_deploy deploy@<IP_A> 'docker volume ls' \
  | sudo tee /var/lib/oscript-migration/volume-ls.txt >/dev/null
sudo chmod 0640 /var/lib/oscript-migration/volume-ls.txt
```

### Сертификаты

Копируется весь `web/certbot/conf/` (`archive`, `live`, `renewal`, `accounts`). После копирования закрытые ключи остаются `0600` и владельцем root; симлинки в `live/` указывают на `archive/`.

```bash
sudo rsync -aHAX --numeric-ids \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  deploy@<IP_A>:/opt/oscript/web/certbot/conf/ \
  /var/lib/oscript-migration/certbot-conf/
```

Проверка:

```bash
sudo find /var/lib/oscript-migration/certbot-conf -name 'privkey*.pem' -printf '%m %u:%g %p\n'
sudo find /var/lib/oscript-migration/certbot-conf/live -type l -ls
```

У каждого `privkey*.pem` режим `600` и владелец `root`. В `live/` есть симлинки на `../../archive/...`. Каталог не коммитить и не класть в `/opt/oscript`.

---

## Этап 7 — окно (действия на B)

Согласовать с [operator-manual-A.md](operator-manual-A.md) (stop openhub/minio/lgtm на A, финальный rsync).

### Подготовка на B (A ещё обслуживает)

1. Клон/обновление `/opt/oscript` на `feature/multi-host`.
2. `.env` собрать вручную из [`env/node_b.env.example`](../../env/node_b.env.example). Значения MinIO и Grafana — из vault, те же, что на A. Файл с A поверх этого пути не копировать.

Пустой `OTEL_HOST_NAME` в compose подменяется на `oscript.io`, пустой `DOCKER_GID` — на `995` (группа docker на A). В файле должно лежать число GID, не текст `$(getent ...)`. Подстановка ниже раскрывается оболочкой в момент записи.

```bash
cd /opt/oscript
gid=$(getent group docker | cut -d: -f3)
test -n "$gid"
umask 027
cat > .env <<EOF
COMPOSE_PROJECT_NAME=os
COMPOSE_FILE=compose/node_b.compose.yaml
OTEL_HOST_NAME=oscript-b
DOCKER_GID=${gid}
NGINX_STATUS_ENDPOINT=http://10.9.0.1:8080/nginx_status
EOF
chgrp docker .env
chmod 0640 .env
```

В тот же файл дописать секреты MinIO и Grafana из vault (`MINIO_ROOT_*`, `JENKINS_S3_*`, `OPENHUB_S3_*`, `GRAFANA_ADMIN_PASSWORD`, `GRAFANA_DB_PASSWORD`). Проверка двух строк hostmetrics:

```bash
grep -q '^OTEL_HOST_NAME=oscript-b$' .env
grep -q "^DOCKER_GID=$(getent group docker | cut -d: -f3)$" .env
```

`NGINX_STATUS_ENDPOINT` — не секрет и не поле vault. В `host_vars/node_b.yml` тот же URL лежит в `nginx_status_endpoint`; шаблон роли `app` пишет в `.env` его. Роль `app` в это окно не запускают: `app_apply` перезапишет ручной файл.

3. Тома с метками compose **без старта** контейнеров:

```bash
cd /opt/oscript
./ops/dc.sh up --no-start
```

Появляются `/var/lib/docker/volumes/os_minio_data/_data/` и `.../os_lgtm_data/_data/`.

4. Прогрев **в эти каталоги**, без `--delete`. Локальный rsync на B — от root (`sudo`): `-aHAX --numeric-ids` выставляет владельцев и xattr, у `deploy` на это нет прав. `--rsync-path` поднимает `sudo` только на A. Ключ SSH — файл `deploy`, потому что локальный процесс уже root и в `~/.ssh` root ключа нет.

```bash
RSYNC_SSH='ssh -i /home/deploy/.ssh/oscript_deploy -o UserKnownHostsFile=/home/deploy/.ssh/known_hosts'

sudo rsync -aHAX --numeric-ids \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  deploy@<IP_A>:/var/lib/docker/volumes/os_minio_data/_data/ \
  /var/lib/docker/volumes/os_minio_data/_data/

sudo rsync -aHAX --numeric-ids \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  deploy@<IP_A>:/var/lib/docker/volumes/os_lgtm_data/_data/ \
  /var/lib/docker/volumes/os_lgtm_data/_data/
```

### Окно: финальный rsync

После `stop` openhub, minio и lgtm на A — те же цели, с `--delete`. Переменную задают снова, если оболочка новая:

```bash
RSYNC_SSH='ssh -i /home/deploy/.ssh/oscript_deploy -o UserKnownHostsFile=/home/deploy/.ssh/known_hosts'

sudo rsync -aHAX --numeric-ids --delete \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  deploy@<IP_A>:/var/lib/docker/volumes/os_minio_data/_data/ \
  /var/lib/docker/volumes/os_minio_data/_data/

sudo rsync -aHAX --numeric-ids --delete \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  deploy@<IP_A>:/var/lib/docker/volumes/os_lgtm_data/_data/ \
  /var/lib/docker/volumes/os_lgtm_data/_data/
```

Совпадение проверяют тем же rsync, без записи. `du -sb` для этого не используют: размер каталога зависит от метаданных файловой системы. stdout пустой. Допустима одна строка `.d..t...... ./` — отличается только время самого каталога. Строка с `>f`, `cd` или `*deleting` значит, что копия не сошлась: повторить rsync без `--dry-run` и снова снять dry-run.

```bash
sudo rsync -aHAX --numeric-ids --delete --dry-run --itemize-changes \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  deploy@<IP_A>:/var/lib/docker/volumes/os_minio_data/_data/ \
  /var/lib/docker/volumes/os_minio_data/_data/

sudo rsync -aHAX --numeric-ids --delete --dry-run --itemize-changes \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  deploy@<IP_A>:/var/lib/docker/volumes/os_lgtm_data/_data/ \
  /var/lib/docker/volumes/os_lgtm_data/_data/
```

### Старт сервисов на B

```bash
cd /opt/oscript
./ops/dc.sh up -d
# minio, lgtm, hostmetrics
```

Проверки с B. `./ops/dc.sh` читает `.env` для Compose и не экспортирует его в shell хоста, поэтому `mc` запускают внутри контейнера, где `MINIO_ROOT_*` уже в окружении:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://10.9.0.2:3000/
./ops/dc.sh exec -T minio sh -c \
  'mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" && mc ls local/openhub'
```

После этого на **A** оператор переключает оверлей на **`split.yml`** (см. manual A).

---

## Этап 8 — приёмка (B)

- С **машины оператора** (`nmap` на нодах нет): публичный IP B — только **22**. **9000, 3000, 4317, 4318** снаружи закрыты. **51820/udp** на B никто не слушает; туннель жив, если в `wg show` есть handshake.
- Grafana hostmetrics B видны в Grafana.
- После перезагрузки B: `wg0`, контейнеры `os_minio_1`, `os_lgtm_1`, `os_hostmetrics_1` работают. Перезагрузка A в этом же заходе — снова отдельное окно (этап 5).

---

## Роль `app` (после обкатки, не в первом окне)

На A роль не запускают, пока `--check` на B не прошёл без ошибок. `--check` не пишет `.env` и не переключает git. `git status` в этом прогоне выполняется (`check_mode: false` у задачи): грязное дерево tracked-файлов останавливает плей и в проверке.

```bash
ansible-playbook ansible/site.yml $VAULT $REF \
  --tags app \
  --limit node_b \
  --check \
  -e app_checkout=true
```

Проверка ещё и шаблона `.env` (файл на диске не меняется; секреты vault должны быть заполнены):

```bash
ansible-playbook ansible/site.yml $VAULT $REF \
  --tags app \
  --limit node_b \
  --check \
  -e app_checkout=true -e app_apply=true
```

Боевой checkout на B — та же команда без `--check`. На A тот же `--check` отдельно, с `--limit node_a`, и только после зелёного прогона на B.

Пример **только checkout** на обеих нодах:

```bash
ansible-playbook ansible/site.yml $VAULT $REF \
  --tags app \
  -e app_checkout=true
```

Запись `.env` из vault (без `up`):

```bash
ansible-playbook ansible/site.yml $VAULT $REF \
  --tags app \
  -e app_checkout=true -e app_apply=true
```

Подъём compose через Ansible:

```bash
ansible-playbook ansible/site.yml $VAULT $REF \
  --tags app \
  -e app_checkout=true -e app_apply=true -e app_compose_up=true
```

`app_apply` на B проверяет секреты из `app_env_required_keys` в [`host_vars/node_b.yml`](../../ansible/host_vars/node_b.yml). `NGINX_STATUS_ENDPOINT` в этот список не входит: шаблон берёт `nginx_status_endpoint` из того же файла.

На A в `host_vars` по умолчанию **`colocated.yml`**; перед этапом 7 вручную или через правку host_vars переключить на **`split.yml`** согласованно с `.env`.

---

## Portainer (после приёмки, этап 8+)

```bash
ansible-playbook ansible/site.yml $VAULT $REF --tags portainer
```

Доступ к UI — SSH-туннель на **`10.9.0.2:9443`**, не публичный DNS.

---

## Чеклист «B готова к этапу 7»

- [ ] Inventory и vault на месте, `ansible all -m ping` OK
- [ ] Этапы 4–5 выполнены, ping `10.9.0.1` ↔ `10.9.0.2`
- [ ] Этап 3 на A выполнен (`ops/dc.sh`, colocated)
- [ ] Этап 6: dump на B, `pg_restore --list` OK; архив `.env` A лежит отдельно от `.env` стека B
- [ ] Ключи WireGuard в vault до `--tags wg`; ping `10.9.0.1` ↔ `10.9.0.2` с handshake
- [ ] Отдельное окно перезагрузки: сначала B, затем A
- [ ] На B: `/opt/oscript` на `feature/multi-host`, ручной `.env` для `node_b.compose.yaml`
- [ ] Security group: на A входящий UDP 51820 с IP B; на B входящий 51820 не открыт
- [ ] Согласованы время окна, StatusCake, откат

---

## Чего на B не делать

- Не коммитить `inventory.ini`, `vault.yml`, `vault_pass` в git.
- Не запускать плейбук с `inventory.example.ini` и `inventory_is_example=true` на боевые хосты.
- Не публиковать MinIO/Grafana/OTLP на `0.0.0.0` публичного интерфейса — только туннель и ufw по ролям.
- Не удалять dump, каталог `/var/lib/oscript-migration/` и тома `os_minio_data` / `os_lgtm_data` до успешной приёмки этапа 8.
