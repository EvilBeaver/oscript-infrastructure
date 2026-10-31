# 4. Ansible

[Целевое устройство](03-target.md) · [оглавление](README.md) · дальше: [как меняется репозиторий](05-repo-refactor.md)

Ansible здесь — команда, которую человек запускает на ноде B. Демона и панели нет. Между прогонами на хостах ничего само не применяется. Пока плейбука нет, A обновляют как сейчас: `git pull` и `docker compose up -d` в каталоге стека.

```bash
# на B, под пользователем deploy; боевой inventory с inventory_is_example=false
cd /opt/oscript
ansible-playbook ansible/site.yml \
  -e @/opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass \
  --tags firewall --limit node_b \
  -e firewall_rollback_minutes=10
```

Тег `never` на задачах значит «не выполнять при запуске без `--tags`». В `--tags` его **не передают**: выборка тегов — по «или», и `--tags firewall,never` выполняет **все** роли, у которых есть `never` (common, firewall, wireguard, spoofdpi, app, portainer). Нужная роль выбирается своим тегом:

```text
--tags common
--tags firewall --limit node_b
--tags wg
--tags spoofdpi --limit node_a
--tags firewall_confirm --limit node_a
--tags app
--tags portainer
```

Голый `ansible-playbook ansible/site.yml` без тегов выполняет только задачи без `never` (проверка inventory и версий Ansible/Docker). Файрвол, WireGuard и остальное не трогает.

Плейбук по SSH заходит на A как `deploy` и локально, тем же пользователем, приводит B к описанному состоянию.

## Кто куда заходит

| | Нода A | Нода B |
| --- | --- | --- |
| Роль в Ansible | группа `edge`, хост `node_a` | группа `worker`, хост `node_b`, `ansible_connection=local` |
| Пользователь | `deploy` + `become: sudo` | `deploy` + `become: sudo` |
| Интерпретатор | `/opt/python3/bin/python3` (CPython 3.12, вне `PATH`) | системный Python Ubuntu 24.04 |
| Каталог | `/opt/oscript` | `/opt/oscript` |
| Код | `ansible.builtin.git`, `version: "{{ deploy_ref }}"` (ветка, тег или SHA; на время миграции `feature/multi-host`, потом `master`) | тот же приём |

Рабочая станция с Cursor в эту схему не входит. Запасной control node — любой Linux с тем же ключом и копией репозитория. Плейбуки пишутся так, чтобы смена «руки на B» на «runner на B» была файлом workflow, а не переписыванием ролей.

Образец inventory (боевой файл на B, в git его нет):

```ini
[oscript:children]
edge
worker

[oscript:vars]
inventory_is_example=false

[edge]
node_a ansible_host=<публичный IP A> public_ip=<публичный IP A> ansible_user=deploy ansible_python_interpreter=/opt/python3/bin/python3 ansible_ssh_private_key_file=/home/deploy/.ssh/oscript_deploy

[worker]
node_b ansible_connection=local ansible_user=deploy public_ip=<публичный IP B>
```

Образец для `ansible-playbook --syntax-check` — [`ansible/inventory.example.ini`](../../ansible/inventory.example.ini) с `inventory_is_example=true` (прогон с ним на хосты запрещён assert'ом).

`host_key_checking` в корневом `ansible.cfg` включён (файл лежит в `/opt/oscript/ansible.cfg`, чтобы подхватываться при запуске из `/opt/oscript`). Ключ хоста A принимается один раз при первом SSH, не отключается в конфиге.

Пользователь `deploy` на обеих нодах:

- отдельный от людей (`andrei` и остальные); у `andrei` sudo спрашивает пароль, плейбук на этом остановится;
- sudo без пароля;
- член группы `docker`, чтобы читать сокет и вместе с остальными работать в `/opt/oscript`;
- на A в `authorized_keys` ключ B с префиксом `from="<публичный IP B>"`.

Плейбук на B запускает сам `deploy`, поэтому локальное соединение идёт от его имени. Проверка с B: `ssh -i ~/.ssh/oscript_deploy deploy@<A> sudo -n true`.

Root по SSH на A для Ansible не открывают. Уже включённый `PermitRootLogin` этой книгой не расширяется. На B вход людей по SSH может остаться отдельным; Ansible ходит только как `deploy`.

## Один раз руками на A, до первого плейбука

Системный `/usr/bin/python3` — 3.5.2, его не меняют: на нём работает `apt`. Модули ansible-core 2.21 на этом интерпретаторе падают.

Для модулей на A уже стоит CPython 3.12: `/opt/python3/bin/python3`. Рядом `/opt/python3/bin/uv` (44 МБ, `root:root`). Каталог `/opt/python3/bin` в `PATH` не входит. Проверка и любой ручной запуск — полным путём:

```bash
/opt/python3/bin/python3 --version
```

Тот же путь записан в `ansible_python_interpreter` у `node_a`: образец inventory и [`ansible/host_vars/node_a.yml`](../../ansible/host_vars/node_a.yml). Автопоиск Ansible на Xenial выбирает `/usr/bin/python3`, поэтому интерпретатор задают явно, а не через `PATH`.

Модуль `ansible.builtin.apt` на A не использовать: `python-apt` есть только для системного 3.5. Пакеты в ролях для A ставятся командой `apt-get … -y` с проверкой через `dpkg -s`. Модули `file`, `template`, `copy`, `systemd`, `git`, `command` и `community.docker` от `python-apt` не зависят.

На B (Ubuntu 24.04) **Ansible на control node** ставят один раз вручную через pipx (`ansible-core==2.18.11`, коллекции из `ansible/requirements.yml`: `community.docker` 4.8.2, `community.general` 10.7.6). Пакет `ansible` из apt Noble (core 2.16) не подходит. Роль `common` только проверяет версии core и коллекций и падает при расхождении; сами пакеты Ansible она не ставит.

Готовность A: `ansible node_a -m ping` и `ansible node_a -b -m command -a id`.

## Один раз руками на B, до первого плейбука

Начальная настройка B ручная; роль `common` Ansible не устанавливает. Команды sudoers, Docker, `PATH` после pipx, порядок `vault_pass` и однострочный inventory — [инструкция B](operator-manual-B.md). `--tags common` повторно ставит Docker CE. Плейбук без `--tags` на пустой B падает на проверке `docker version` и установку не начинает (`never`).

1. Пользователь `deploy`: sudo без пароля, группа `docker`. Ключ `~/.ssh/oscript_deploy`, публичная часть на A (`authorized_keys` с `from="<IP B>"`).
2. pipx: `pipx install 'ansible-core==2.18.11'`, затем `ansible-galaxy collection install -r /opt/oscript/ansible/requirements.yml`.
3. Каталог `/opt/oscript`: владелец `deploy:docker`, `2755`. Клон репозитория, `git config --system --add safe.directory /opt/oscript`.
4. Docker CE и compose-plugin (дальше поддерживает роль `common` с тегом `common`, без `never` в `--tags`).
5. `/opt/oscript-secrets/` (`0700`), `vault.yml` и `vault_pass` (`0400`). `ansible/inventory.ini` из [`inventory.example.ini`](../../ansible/inventory.example.ini) с `inventory_is_example=false` и `ansible_connection=local` у `node_b`.

Проверка: `ansible all -m ping` с B.

## Плейбук

`site.yml`, хосты группы `oscript` (`edge` и `worker`). Теги: `wg`, `firewall`, `spoofdpi`, `app`, `portainer`.

Порядок ролей:

1. `common`. На B ставит Docker и базовые пакеты (`ca-certificates`, `curl`, `rsync`). На A проверяет, что Engine и `docker compose` на месте, и не переустанавливает их. Unified Agent не трогает. Ветка по `ansible_distribution_version`.
2. `firewall` и `spoofdpi` — на A, см. ниже. На B `firewall` создаёт политику по умолчанию: с интернета только 22/tcp. Входящий 51820/udp на B не открывается: WireGuard там клиент и порт не слушает. Свой `DOCKER-USER` в `/etc/ufw/after.rules`: правило `DROP` применяется только к входящим пакетам с внешнего интерфейса `-i <wan_if>`, а трафик с `-i wg0` пропускается через `RETURN`, чтобы нода A видела опубликованные на `10.9.0.2` порты `minio` и `lgtm`, но случайно опубликованный на `0.0.0.0` порт контейнера не стал доступен из интернета.
3. `wireguard`.
4. `app` — git, шаблон `.env`, `community.docker.docker_compose_v2`.
5. `portainer` — тег `portainer`, в первый прогон на A не входит. После приёмки переноса.

Роли CoreDNS нет.

Пока плейбук не обкатан на пустой B, на A его не запускают. Первый заход на A — `--check` и без `compose up`, после сверки пути и `COMPOSE_PROJECT_NAME=os`.

### Роль app

- `ansible.builtin.git` только при `-e app_checkout=true` и обязательном `-e deploy_ref=…` (на миграции `feature/multi-host`). Локальные правки tracked-файлов роль не затирает.
- Владелец дерева — `deploy:docker`. Режим `2755` ставится **только каталогам** (setgid). Mode файлов роль не меняет: `privkey.pem` остаётся `600`, `.env` не становится `2755`. Системные роли по-прежнему с `become`. Роль не делает `chown` на человека.
- Каталог не копируется с control node поверх clone: так затираются `web/certbot`, `.env` и логи. Исключения из git на хосте те же, что сейчас: `.env`, `web/certbot/`, логи, тома Docker.
- `.env` режим `0640`, группа `docker`. Compose не вызывается, пока файла нет.
- `project_name: os`, `files: "{{ compose_files }}"`, `env_files: [.env]` относительно `project_src`.
- Перед первым боевым `up` на A — копия `.env` и `docker volume ls`.

### Роль wireguard

- Пакет на A — только `wireguard-tools` из `xenial-updates/universe` (`1.0.20200513-1~16.04.2`). Метапакет `wireguard` не ставить: он может потянуть DKMS. Модуль ядра уже есть (`wireguard.ko`, `intree`), роль делает `modprobe wireguard` и кладёт файл в `/etc/modules-load.d/`.
- На B — обычный пакет WireGuard из Ubuntu 24.04.
- Ключи до первого `--tags wg`: две пары (`wg genkey` / `wg pubkey`) в `vault.yml`. Роль копирует закрытый ключ в `/etc/wireguard/privatekey` (`0600`). Пустые значения в vault запускают генерацию на хосте и намеренный `fail`; этот проход не используется — задача печати ключа пишет закрытый ключ в лог Ansible (`tee` на stdout, без `no_log`). Шаблон пира не рендерится при пустой группе `edge`.
- A — хаб, `ListenPort 51820`, peer с `AllowedIPs` адреса B `/32`. B — клиент, `Endpoint` публичный адрес A, `AllowedIPs = 10.9.0.1/32`, `PersistentKeepalive = 25`, без `ListenPort`.
- Handler перезапускает `wg-quick@wg0`.
- Подсеть проверить на пересечение с маршрутами провайдеров и docker bridge (`ip route` на обеих нодах) до первого `wg-quick up`. MTU оставить 1420 и проверить крупным пакетом: `ping -M do -s 1372`.
- Входящий UDP 51820 — только на A, в ufw и в security group провайдера, если она есть, с публичного IP B. На B роль firewall этот порт не открывает. В security group B его тоже не открывать. Входящий TCP 22 на B — для оператора.
- Drop-in `docker.service.d/wg.conf`: `After=wg-quick@wg0.service` и `Wants=wg-quick@wg0.service`. Порты контейнеров висят на адресе `wg0`. Если интерфейса ещё нет, Docker не сможет сделать bind, и политика `restart` это не лечит.
- Исходящий трафик контейнеров A в `10.9.0.2` уходит через `wg0` уже с MASQUERADE Docker, источник становится `10.9.0.1` и попадает в `AllowedIPs` на B. Отдельный SNAT не нужен. То же проверить в обратную сторону.

Приёмка туннеля: `wg show` и ping `10.9.0.1` ↔ `10.9.0.2`.

### Роль firewall на A

Шаблон `/etc/ufw/after.rules` повторяет эталон из [главы 2](02-as-is.md): цепочка `DOCKER-USER` и разрешения 8888 для `docker0` и `br+`. Остальные правила — модулем ufw из коллекции `community.general`: 22, 80, 443, 50000 и `8888/tcp` из docker-сетей, плюс `51820/udp` только с IP B.

Первый прогон на хосте, где ещё нет штампа `/var/lib/oscript/firewall-confirmed`:

```bash
ansible-playbook ansible/site.yml \
  -e @/opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass \
  --tags firewall --limit node_a \
  -e firewall_rollback_minutes=10
```

Задачи подтверждения помечены только `firewall_confirm` (и `never`). Тег роли на `site.yml` им не наследуется, иначе `--tags firewall` сразу создаёт штамп и задача «Требовать таймер отката» таймер не ставит. После проверки, что SSH жив:

```bash
ansible-playbook ansible/site.yml \
  -e @/opt/oscript-secrets/vault.yml \
  --vault-password-file /opt/oscript-secrets/vault_pass \
  --tags firewall_confirm --limit node_a
```

Это снимает задание `at` и ставит штамп. Повторный `--tags firewall` таймер уже не требует.

Пакеты `at` и `iptables-persistent` на Xenial ставятся через `apt-get` (`ansible/tasks/apt_install.yml`), не модулем `ansible.builtin.apt`: у `/opt/python3/bin/python3` нет `python3-apt`. 22/tcp разрешается до `ufw enable`. Держите вторую SSH-сессию, пока не прошёл `firewall_confirm`.

Опубликованные на адрес туннеля порты (`10.9.0.1:5432`, `10.9.0.1:8080`) идут через цепочки Docker. Правило `DOCKER-USER` с `-i eth0` их для трафика с `wg0` не закрывает и закрывает попытку зайти на них с интернета.

Drop-in `docker.service.d/ufw.conf`: `After=ufw.service`.

### Роль spoofdpi

Включается на A (`spoofdpi_enabled: true`). Юнит сохраняет сегодняшнее имя `spoof-dpi.service`, чтобы не появилась вторая служба рядом со старой.

1. Скачать закреплённый релиз SpoofDPI (сейчас на A работает 1.5.3), проверить контрольную сумму, положить бинарь в `/usr/local/bin/spoofdpi`.
2. Слушать адрес docker0, не `0.0.0.0`. Адрес вычислять с хоста (`ip addr show docker0`), в compose Jenkins тот же адрес попадает в `extra_hosts` для `host.docker.internal`. На текущей A это `172.17.0.1`.
3. `Restart=always`, старт после `network-online.target` и `docker.service`. Понижение прав с root — отдельная проверка: процессу могут понадобиться `CAP_NET_RAW` и `CAP_NET_ADMIN`. Пока это не проверено, юнит остаётся от root, как в эталоне, но bind уже на docker0.
4. Приёмка: `ss` показывает 8888 только на адресе docker0; `curl -x http://<docker0>:8888 https://<внешний хост>` с A успешен; с интернета порт закрыт.

В модуле jenkins остаются `HTTP_PROXY` и `HTTPS_PROXY`, добавляется `NO_PROXY` из [главы 3](03-target.md).

## Чего роль не делает

Не ставит Docker заново на A, не обновляет плагин `docker compose` на A (закреплён v2.40.3: Engine 18.09 старый, более новые версии плагина могут потребовать более свежий API), не обновляет Ubuntu 16.04, не выключает Unified Agent, не публикует Portainer в интернет, не кладёт `vault.yml` в git.
