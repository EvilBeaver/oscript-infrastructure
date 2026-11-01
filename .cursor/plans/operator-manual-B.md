# Инструкция оператора: нода B (worker, control Ansible)

**Нода B** — Ubuntu 24.04, будущий дом для MinIO, LGTM и hostmetrics (после этапа 7). Здесь же **control node Ansible**: все `ansible-playbook` выполняются **на B** под **`deploy`**, в том числе для изменений на A по SSH.

Каталог стека: **`/opt/oscript`**. Секреты вне git: **`/opt/oscript-secrets/`** (`vault.yml`, `vault_pass`). Боевой **`ansible/inventory.ini`** только на B.

Книга: [оглавление](README.md) · Ansible [глава 4](04-ansible.md) · этапы [глава 6](06-work-order.md) · работы на A [operator-manual-A.md](operator-manual-A.md).

---

## Чеклист состояния ноды B (сверено 2026-11-01, 18:10 UTC)

`[x]` — проверено командами на живой ноде (`id`, `docker …`, `dpkg-query`, `systemctl`, `ufw status`, `ansible … -m ping`), не по документам.

### Машина и доступ

- [x] Ubuntu **24.04.1**, 2 vCPU, 3916 MiB RAM, диск `/` 59 ГБ — занято 32 %, свободно 40 ГБ. Swap **0**.
- [x] Пользователь `deploy`: `uid=1500`, группы `oscript` (1500) и `docker` (**988**), `sudo -n` без пароля.
- [x] Docker **29.9.1** + плагин compose **v5.6.0**; репозиторий Docker подключён (`/etc/apt/sources.list.d/docker.list`, `noble stable`).
- [x] Базовые пакеты роли `common` на месте: `ca-certificates`, `curl`, `gnupg`, `rsync`. Каталог `/opt/oscript` — `deploy:docker 2755`.
- [x] Ключ `deploy@B → A` создан и **авторизован на A**: в `/home/deploy/.ssh/authorized_keys` на A две строки — `hermes@oscript-deploy` (`SHA256:cfRahOUblDHdrcMjj4HJPeIzlmkkKBkITkE1GCuzSjE`) и `deploy@oscript-b` (`SHA256:V2fdDqDt0kUi3faktu34vM/h5VFYAH/PvZ624trjF98`). Второй — ключ этой ноды.
- [x] Клон `/opt/oscript` — ветка `feature/multi-host`, коммит **`8f6bf93`**, дерево чистое. Расхождения с origin нет: прежний локальный `386dfe5` уже влит в origin, force/rebase не нужен.

### Ansible

- [x] `ansible-core 2.18.11` (`/home/deploy/.local/bin/ansible-playbook`), коллекции `community.docker 4.8.2` и `community.general 10.7.6`.
- [x] `/opt/oscript/ansible/inventory.ini` — `inventory_is_example=false`; `node_a` → `ansible_user=deploy`, интерпретатор `/opt/python3/bin/python3`, ключ `/home/deploy/.ssh/oscript_deploy`; `node_b` → `ansible_connection=local`.
- [x] `/opt/oscript-secrets/`: `vault_pass` (`0400`) и `vault.yml` (`0600`). В vault заполнены все ключи: секреты приложений, обе пары WireGuard, `portainer_agent_secret`.
- [x] `ansible all -m ping` → `node_a pong`, `node_b pong` (проверено 18:0x UTC).
- [ ] Защита от примерного inventory не работает при тегированных прогонах: у `pre_tasks` в `ansible/site.yml` нет тега `always`, а все команды в этой инструкции — тегированные. Прогон с `-i ansible/inventory.example.ini` проверку пройдёт мимо. Ждёт правки в git.

### Этап 4 на B

- [x] Роль `common` прогонялась: Docker и базовые пакеты на месте (см. выше).
- [x] Роль `firewall` прогонялась и **подтверждена**: ufw `active`, `deny (incoming)`, из интернета только `22/tcp`; штамп `/var/lib/oscript/firewall-confirmed` лежит, очередь `at` пуста; в `/etc/ufw/after.rules` ровно одно объявление `:DOCKER-USER`; политики ip6tables — `DROP`.
- [x] `iptables-persistent` не установлен и не ставится — на 24.04 он снимает `ufw` (`Breaks`). Правка роли — коммит `386dfe5`.
- [x] `iperf3 3.16` установлен на обеих нодах.
- [ ] Замер «до ufw на B» пропущен: окно ушло, пока роль ещё не была поправлена. Скорость мерилась только через туннель — **94.6–94.9 Мбит/с** (см. этап 5).

### Этап 5 на B

- [x] `wg0`: `10.9.0.2/24`, listen `59564`, peer `xFpsyUEMs…`, `AllowedIPs 10.9.0.1/32`, `PersistentKeepalive 25`, `latest handshake` свежий.
- [x] `/etc/wireguard/{privatekey,wg0.conf}` — `root:root 0600`; `wg-quick@wg0` активен; drop-in Docker `/etc/systemd/system/docker.service.d/wg.conf` (`After=` и `Wants=wg-quick@wg0.service`) на месте.
- [x] B — клиент: свой UDP-порт не слушает, входящий 51820 в ufw не открыт.
- [ ] Перезагрузка B не проводилась — отдельное окно этапа 5 (сначала B, потом A).
- [ ] Swap не добавлен: `free -m` показывает 0, в `/etc/fstab` записи нет. Файл `/swapfile` на 512 МиБ от 2024-11-02 лежит, но **не активен** и для LGTM мал — в окне нужен рабочий swap 2 ГБ.

### Этап 6 (копия до окна) — выполнен

- [x] `/var/lib/oscript-migration` (`0700 root`): `openhub-2026-11-01.dump` (1.42 МБ), `pg-restore-list.txt` (дамп открывается, `TOC Entries: 354`), `env-node-a` (копия `.env` A, `0600`), `volume-ls.txt`, `certbot-conf/`.
- [x] Дальнейшее закрывает пункты чеклиста «B готова к этапу 7» ниже: `.env` собран вручную (13 ключей, `0640 deploy:docker`), секреты MinIO/Grafana совпадают с A по sha256.

### Этап 7 (подготовка) — часть сделана, окно не открывалось

- [x] `.env`: `COMPOSE_PROJECT_NAME=os`, `COMPOSE_FILE=compose/node_b.compose.yaml`, `OTEL_HOST_NAME=oscript-b`, `DOCKER_GID=988`, `NGINX_STATUS_ENDPOINT=http://10.9.0.1:8080/nginx_status` + 8 секретов.
- [x] Тома созданы с метками Compose и **прогреты**: `os_minio_data` 2.2 ГБ (`.minio.sys`, бакеты `openhub`, `jenkins-artifacts`), `os_lgtm_data` 7.1 ГБ (`grafana`, `loki`, `prometheus`, `pyroscope`, `tempo`).
- [x] Образ `os_minio:latest` собран на B (325 МБ, `minio RELEASE.2025-09-07T16-13-09Z`); стянуты `grafana/otel-lgtm:0.33.1` и `otel/opentelemetry-collector-contrib:0.104.0`.
- [x] `./ops/dc.sh config` на сборке B валиден (`rc=0`).
- [x] Пробный запуск стека B выполнялся: MinIO отдал бакеты, Grafana ответила на `10.9.0.2:3000`, метрики хоста B доходили. После проверок стек остановлен.
- [x] `/root/warm_rsync.sh` в окне **не использовать**: в ветке `real` нет `--delete`, критерий «пустой dry-run» после него недостижим. Финальный rsync — командами этапа 7 из этой инструкции.
- [ ] В окне не собирать MinIO повторно: `build minio` упал бы на `bullseye-security` (исправлено в `8f6bf93` — база переведена на `debian:bookworm-slim`, но образ уже собран).
- [ ] Отдельное окно перезагрузки (B, затем A) не начато.

### Мусор и известный дефект на B

- [ ] Контейнер `wizardly_hodgkin` (`otel/opentelemetry-collector-contrib:0.104.0`) запущен с 17:54 UTC с конфигом `/tmp/t-default.yaml` — след чьей-то проверки, к стеку `os` не относится. Удалить: `docker rm -f wizardly_hodgkin`.
- [ ] **Поднять `hostmetrics` после выкладки правки.** `os_hostmetrics_1` падал с `Exited (1)`: коллектор 0.104.0 не принимает `api_version: ${env:DOCKER_STATS_API_VERSION:-1.25}`. В репозитории суффикс убран, сборка B по-прежнему задаёт `DOCKER_STATS_API_VERSION=1.44`. После `git pull`: `./ops/dc.sh up -d hostmetrics` — контейнер должен остаться `Up`, не `Restarting`.

### Как перепроверить

```bash
ssh aeza-msk 'docker ps -a --format "{{.Names}}|{{.Status}}"; wg show; ufw status verbose | head -12'
ssh aeza-msk 'sudo -u deploy bash -lc "cd /opt/oscript && git rev-parse --short HEAD && ansible all -m ping -e @/opt/oscript-secrets/vault.yml --vault-password-file /opt/oscript-secrets/vault_pass | tail -12"'
ssh aeza-msk 'sudo du -sh /var/lib/docker/volumes/os_minio_data/_data /var/lib/docker/volumes/os_lgtm_data/_data; sudo ls -la /var/lib/oscript-migration/'
```

---

## Модель управления: что здесь делает Ansible

Ansible — не постоянно работающий сервер и не часть Docker-стека. Это программа командной строки, которая запускается оператором на B, подключается к управляемым машинам и последовательно выполняет описанные в репозитории задачи.

В этой схеме:

- **control node** — B. Здесь установлена команда `ansible-playbook`, лежат inventory, пароль vault и SSH-ключ;
- **managed node** — A. Ansible подключается к ней по SSH как `deploy`, а системные изменения выполняет через `sudo`;
- B одновременно control node и managed node. Для самой B Ansible использует локальное соединение, без SSH;
- **inventory** — список машин и адресов подключения: `node_a`, `node_b`, их публичные IP и параметры Python;
- **playbook** — точка входа `ansible/site.yml`;
- **role** — группа задач одного назначения: `common`, `firewall`, `wireguard`, `app` и т. д.;
- **tag** — имя, которым оператор выбирает нужную роль: например, `--tags wg`;
- **variables** — параметры ролей. Несекретные лежат в git в `group_vars` и `host_vars`, секретные передаются из зашифрованного vault;
- **become** — переход от `deploy` к root через `sudo`. Для автоматического прогона у `deploy` настроен `NOPASSWD`;
- **idempotency** — повторный запуск должен приводить машину к тому же описанному состоянию. Это не означает, что любой плейбук безопасно прерывать или что ошибочную переменную можно передать без последствий.

Путь одного запуска выглядит так:

```text
оператор на B
  → ansible-playbook читает ansible.cfg и inventory.ini
  → расшифровывает vault.yml паролем из vault_pass
  → выбирает хосты через --limit и задачи через --tags
  → локально меняет B либо подключается по SSH к A
  → при необходимости выполняет задачи через sudo
```

На A не устанавливают Ansible и не копируют туда `vault.yml`. На A оказываются только результаты: системные конфиги, закрытый ключ WireGuard в root-only файле и, если запущена роль `app` с `app_apply=true`, рабочий `.env`.

### Защита от слишком широкого запуска

Почти все изменяющие задачи имеют специальный тег `never`. Он означает: задача не выполняется без явного выбора роли. Оператор всегда указывает один содержательный тег:

```bash
--tags common
--tags firewall
--tags wg
```

Само слово `never` в команду добавлять нельзя. В Ansible теги объединяются по правилу «ИЛИ», поэтому `--tags firewall,never` выберет не только firewall, а вообще все задачи с `never`.

`--limit node_b` или `--limit node_a` — второй предохранитель: он ограничивает машины. Если `--limit` отсутствует, роль применяется ко всем подходящим хостам из группы `oscript`.

### Какие секреты существуют

Не смешивайте три независимых механизма доступа:

1. **SSH-ключ `/home/deploy/.ssh/oscript_deploy`** позволяет B войти на A. Это не Ansible Vault и не пароль сервиса.
2. **`vault_pass`** расшифровывает файл `vault.yml`. Он нигде не используется как пароль приложения.
3. **Значения внутри `vault.yml`** — реальные токены, пароли приложений и ключи WireGuard.

Для разных ролей нужен разный набор:

| Роль/операция | Что должно быть подготовлено |
| --- | --- |
| `common`, `firewall`, `firewall_confirm`, `spoofdpi` | Рабочий SSH и `sudo`; прикладные пароли могут пока быть пустыми |
| `wg` | Четыре ключа `wireguard_node_*_{private,public}_key` |
| `app` только с `app_checkout=true` | Секреты приложений не нужны; нужен `deploy_ref` |
| `app` с `app_apply=true` | Все ключи из `app_env_required_keys` соответствующей ноды |
| `portainer` | `portainer_agent_secret`; без него роль пропускает развёртывание |

Команда всё равно передаёт `vault.yml` каждому прогону: это единый шаблон запуска. Наличие пустых прикладных значений не мешает `common` или `firewall`, потому что эти роли их не читают.

### Откуда берутся секреты приложений

Для действующей ноды A источником истины является её текущий `/opt/oscript/.env`. При миграции существующие значения MinIO, OpenHub, Jenkins, Grafana, Telegram и внешнего S3 нужно **сохранить**, а не сгенерировать заново. Новые ключи могут разорвать доступ к существующей БД, бакетам и внешним сервисам.

В `vault.yml` с A переносят:

- `publish_secret`, `TELEGRAM_TOKEN`;
- `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_BUCKET`;
- `OPENHUB_DB_PASSWORD`;
- `OPENHUB_S3_ACCESS_KEY`, `OPENHUB_S3_SECRET_KEY`;
- `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`;
- `JENKINS_S3_ACCESS_KEY`, `JENKINS_S3_SECRET_KEY`;
- `GRAFANA_ADMIN_PASSWORD`, `GRAFANA_DB_PASSWORD`.

Заново создаются только:

- пароль самого Ansible Vault (`vault_pass`);
- две пары ключей WireGuard;
- `portainer_agent_secret`, если разворачивается Portainer.

Не вставляйте секреты в аргументы командной строки: они попадают в history и могут быть видны через список процессов. Для заполнения используйте `ansible-vault edit`.

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

Группу `docker` добавляют после установки Engine (шаг 2).

SSH-ключ создаётся от имени пользователя `deploy` на B. Следующая команда запускается из root-сессии, но сам файл будет принадлежать `deploy`; текущая оболочка останется root для шага установки Docker:

```bash
sudo -u deploy -H sh -c \
  'umask 077; ssh-keygen -t ed25519 -f "$HOME/.ssh/oscript_deploy" -C deploy@oscript-b'
```

Для ключа автоматизации обычно оставляют пустую passphrase: иначе каждый запуск Ansible потребует интерактивный ввод или настроенный `ssh-agent`. Защита строится на правах файла `0600`, отдельном пользователе и ограничении публичного ключа по исходному IP.

Показать публичную часть:

```bash
sudo -u deploy cat /home/deploy/.ssh/oscript_deploy.pub
```

Её добавляют на **A** в `~deploy/.ssh/authorized_keys` одной строкой:

```text
from="<публичный_IP_B>" ssh-ed25519 AAAA... deploy@oscript-b
```

Префикс `from=` означает, что украденную публичную авторизацию нельзя использовать с произвольного адреса: SSH на A примет этот ключ только от публичного IP B.

Первое обычное подключение также записывает host key A в `~/.ssh/known_hosts`. Сверьте fingerprint через консоль провайдера, а не подтверждайте неизвестный ключ вслепую:

```bash
sudo -u deploy -H ssh \
  -i /home/deploy/.ssh/oscript_deploy deploy@<IP_A>
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

Inventory отвечает на вопрос «к каким машинам подключаться», а vault — «какие секретные значения передать ролям». Оба файла существуют только на B и не коммитятся.

Сначала создайте закрытый каталог. Все следующие команды этого подраздела выполняются на B под `deploy`, кроме явно отмеченных `sudo`:

```bash
sudo mkdir -p /opt/oscript-secrets
sudo chown deploy:deploy /opt/oscript-secrets
sudo chmod 700 /opt/oscript-secrets

umask 077
openssl rand -base64 48 > /opt/oscript-secrets/vault_pass
chmod 0400 /opt/oscript-secrets/vault_pass
```

`vault_pass` содержит одну случайную строку. Этот файл нужен для неинтерактивного запуска: Ansible прочитает из него пароль и расшифрует vault. Потеря файла означает потерю возможности прочитать `vault.yml`, поэтому сохраните его в принятом у вас защищённом хранилище паролей. Не копируйте его в git и на A.

Создайте рабочую копию списка переменных с закрытыми правами:

```bash
install -m 0600 /opt/oscript/ansible/vault.example.yml \
  /opt/oscript-secrets/vault.yml
```

На этом коротком шаге `vault.yml` ещё обычный YAML. Заполните известные значения в редакторе и сразу зашифруйте:

```bash
${EDITOR:-nano} /opt/oscript-secrets/vault.yml
ansible-vault encrypt /opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass
```

Если прикладные секреты пока не собраны, их разрешается оставить пустыми: этапы `common` и `firewall` от этого не зависят. Четыре ключа WireGuard должны быть заполнены до первого штатного `--tags wg`; их генерация описана в этапе 5.

Существующие значения с A переносите непосредственно в редактор vault. Например, открыть текущий файл на A можно отдельной SSH-сессией:

```bash
ssh -i ~/.ssh/oscript_deploy deploy@<IP_A>
cd /opt/oscript
less .env
```

Не копируйте `.env` в git и не отправляйте его через чат. Перенос означает сопоставить имена переменных из `ansible/vault.example.yml` с одноимёнными строками действующего `.env`.

После шифрования файл начинается с заголовка `$ANSIBLE_VAULT;...`, а не с YAML-переменных. Дальше правьте его только так:

```bash
ansible-vault edit /opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass
```

Проверка, что пароль подходит и YAML читается:

```bash
ansible-vault view /opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass
```

`view` выводит секреты в терминал: используйте его только в приватной сессии и не сохраняйте вывод в лог.

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

Разбор последней команды:

- `ansible/site.yml` — какой playbook выполнить;
- `$VAULT` — откуда взять зашифрованные переменные и пароль к ним;
- `$REF` — какую git-ветку или SHA использует роль `app`;
- `--tags firewall` — выполнить только задачи firewall;
- `--limit node_b` — применить их только к B;
- последнее `-e` — разовый несекретный параметр таймера отката.

Перед изменяющим запуском полезно проверить выборку:

```bash
ansible-playbook ansible/site.yml $VAULT $REF \
  --tags firewall --limit node_b --list-hosts

ansible-playbook ansible/site.yml $VAULT $REF \
  --tags firewall --limit node_b --list-tasks
```

Это ничего не меняет и показывает, какие хосты и задачи выбраны. `--check` тоже является режимом проверки, но не все команды способны достоверно симулировать результат. Используйте его там, где инструкция явно это предлагает; не считайте `--check` универсальной гарантией безопасности.

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

На Ubuntu 24.04 роль не ставит `iptables-persistent`: пакет конфликтует с `ufw` (`Breaks`), и apt снимает `ufw`. При `IPV6=no` DROP в ip6tables записывает сам ufw в момент включения. A в этом заходе не трогать.

Если предыдущий прогон уже снимал `ufw`, до нового запуска на B:

```bash
# очередь пуста, либо в ней нет задания «ufw disable»
atq
sudo rm -f /var/lib/oscript/firewall-rollback.job

sudo apt-get purge -y iptables-persistent netfilter-persistent

# ожидается: install ok installed ... 0.36.2-6
dpkg-query -W -f '${Status} ${Version}\n' ufw
# если пакета нет: sudo apt-get install -y ufw

# до прогона декларации цепочки быть не должно
grep -c '^:DOCKER-USER' /etc/ufw/after.rules
```

Файл `firewall-rollback.job` со старым id роль передаёт в `atrm` и может снять чужое задание `at`. Каталог `/opt/oscript` к этому моменту уже содержит правку роли: задачи «iptables-persistent для сохранения ip6tables» в `ansible/roles/firewall/tasks/main.yml` нет. Иначе прогон снова снимет `ufw`.

Держите SSH-сессию. Первый раз на хосте:

```bash
ansible-playbook ansible/site.yml $VAULT $REF \
  --tags firewall --limit node_b \
  -e firewall_rollback_minutes=10
```

Проверить SSH с A и с рабочей станции. До `firewall_confirm` на B:

- `ufw` по-прежнему `0.36.2-6`, прогон без `failed`;
- `sudo ufw status verbose` — `Status: active`, `Default: deny (incoming)`, из интернета открыт только `22/tcp`;
- `sudo ip6tables -S` — политики `DROP`, ACCEPT на `lo`; правила conntrack нет (его затирает включение ufw);
- `grep -c '^:DOCKER-USER' /etc/ufw/after.rules` — `1`;
- `atq` показывает задание, `/var/lib/oscript/firewall-rollback.job` содержит его id.

Затем снять таймер:

```bash
ansible-playbook ansible/site.yml $VAULT $REF \
  --tags firewall_confirm --limit node_b
```

После подтверждения `atq` пуст, есть файл `/var/lib/oscript/firewall-confirmed`. С интернета на B роль открывает только **22/tcp**. UDP 51820 на B не слушается и в ufw не разрешается.

### 4.4. Диск

Убедиться, что на B достаточно места под прогрев **`os_minio_data`**, **`os_lgtm_data`**, дампы и `/opt/oscript-secrets`.

**Готово этап 4**, когда `ansible node_a -m ping` и `ansible node_b -m ping` зелёные, iperf3 снят до ufw, firewall на B включён и подтверждён (`firewall_confirm`).

---

## Этап 5 — туннель и hardening A

**Compose на обеих нодах не менять.** На A — вторая SSH-сессия, пока не выполнен `firewall_confirm`.

### Как устроен WireGuard в этой схеме

WireGuard создаёт на каждой ноде виртуальный сетевой интерфейс `wg0`. Поверх публичного интернета получается приватная точка-точка сеть:

```text
A: wg0 = 10.9.0.1  ← зашифрованный UDP-туннель →  wg0 = 10.9.0.2 :B
```

После этапа 7 nginx и OpenHub на A обращаются к MinIO/LGTM на B по адресам `10.9.0.2`, а не через публичный интерфейс B. Сами сервисы B привязываются к адресу туннеля, поэтому не публикуются в интернет.

У каждой ноды есть пара ключей:

- закрытый ключ остаётся на своей ноде и доказывает её идентичность;
- публичный ключ этой ноды записывается в конфигурацию соседа;
- публичный ключ вычисляется из закрытого, обратное вычисление невозможно.

Закрытые ключи между пирами не обмениваются. В этой процедуре оператор временно хранит обе пары в защищённом vault, чтобы Ansible положил каждой ноде только её собственный закрытый ключ и публичный ключ соседа.

A играет роль доступной точки входа: только A слушает UDP 51820. B — **клиент**: она знает `Endpoint = <публичный_IP_A>:51820`, сама инициирует обмен и поддерживает NAT-состояние через `PersistentKeepalive = 25`. Поэтому входящий 51820 на B открывать не нужно.

`AllowedIPs` в WireGuard одновременно определяет, какие адреса принадлежат пиру и какой трафик направлять в туннель. Здесь каждая сторона разрешает только один адрес соседа `/32`, а не весь интернет.

Успешный `ping` недостаточен без `wg show`: актуальный `latest handshake` подтверждает, что пакеты действительно шифруются и принимаются правильным пиром.

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

Пустой `OTEL_HOST_NAME` в сборке B подменяется на `oscript-b`, пустой `DOCKER_GID` — на `995` (группа docker на A, на B номер другой). В файле должно лежать число GID, не текст `$(getent ...)`. Подстановка ниже раскрывается оболочкой в момент записи. Метрики контейнеров на B идут с Docker API 1.44: это задаёт `compose/node_b.compose.yaml`, отдельной строки `.env` для этого нет.

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

Образ MinIO в окне не собирают. Если `docker image inspect os_minio` не находит образ, сборку делают один раз в этой подготовке (`./ops/dc.sh build minio`) и дожидаются успеха. База образа — `debian:bookworm-slim`.

Перед прогревом проверить диск и память:

```bash
df -h /
free -m
```

Свободного места нужно не меньше удвоенного размера `os_minio_data` и `os_lgtm_data` на A плюс 5 ГБ. Swap на B изначально нет; файл на 2 ГБ добавляют до старта LGTM:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -m
```

4. Прогрев **в эти каталоги**, без `--delete`. Локальный rsync на B — от root (`sudo`): `-aHAX --numeric-ids` выставляет владельцев и xattr, у `deploy` на это нет прав. `--rsync-path` поднимает `sudo` только на A. Ключ SSH — файл `deploy`, потому что локальный процесс уже root и в `~/.ssh` root ключа нет. `/root/warm_rsync.sh` не запускают: его запись не удаляет файлы, которые есть только на B, и проверка dry-run после него не сходится.

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

`./ops/dc.sh ps` показывает `os_hostmetrics_1` в состоянии Up, не Restarting. После этого на **A** оператор переключает оверлей на **`split.yml`** (см. manual A). Старт этих контейнеров — точка, после которой быстрый возврат на тома A уже не сохраняет новые записи B.

### Откат после записей на B

Это отдельное окно. Сначала останавливают openhub на A и minio/lgtm на B. Затем с B, тем же ключом, данные толкают обратно; `--delete` убирает на A файлы, которых на B уже нет:

```bash
RSYNC_SSH='ssh -i /home/deploy/.ssh/oscript_deploy -o UserKnownHostsFile=/home/deploy/.ssh/known_hosts'

sudo rsync -aHAX --numeric-ids --delete \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  /var/lib/docker/volumes/os_minio_data/_data/ \
  deploy@<IP_A>:/var/lib/docker/volumes/os_minio_data/_data/

sudo rsync -aHAX --numeric-ids --delete \
  --rsync-path="sudo -n rsync" -e "$RSYNC_SSH" \
  /var/lib/docker/volumes/os_lgtm_data/_data/ \
  deploy@<IP_A>:/var/lib/docker/volumes/os_lgtm_data/_data/
```

Пустой `rsync --dry-run --delete --itemize-changes` в ту же сторону — критерий совпадения. Дальше на A возвращают `colocated.yml` и поднимают minio, lgtm и openhub, как в [operator-manual-A.md](operator-manual-A.md).

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
- Не копировать тома через `/root/warm_rsync.sh` и не собирать MinIO повторно в окне, если образ `os_minio` уже есть.
- Не удалять dump, каталог `/var/lib/oscript-migration/` и тома `os_minio_data` / `os_lgtm_data` до успешной приёмки этапа 8.
