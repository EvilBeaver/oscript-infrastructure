# 7. Перенос каталога на A

[Порядок работ на хостах](06-work-order.md) · [оглавление](README.md)

Фаза M0. Делать до сплита, отдельным коротким окном: пересоздадутся контейнеры, у которых сменится bind-mount (nginx, certbot, lgtm, hostmetrics). Именованные тома Docker не копируются и не удаляются.

Сейчас боевой clone — `/home/andrei/os`, проект Compose равен имени каталога `os`, тома `os_*`. В `.env` строки `COMPOSE_PROJECT_NAME` нет. Стек создан `docker-compose` v1.23.2, контейнеры называются `os_nginx_1`, `os_openhub_1` и так далее. Плагин `docker compose` v2.40.3 на хосте есть; для этого переноса можно вызывать тот CLI, которым стек поднимают сегодня (v1), чтобы имена контейнеров не сменились раньше модульной сборки.

## До начала

На A уже есть пользователь `deploy` в группе `docker` (глава 4). Конфликт `UU docker-compose.yml` не разбирается: после копирования каталог сбрасывается на `origin/master` этого репозитория. С диска сохраняются `.env`, `web/certbot/` и `logs/`. В gitignore из них `.env`, `logs/` и `web/certbot/conf/`; `web/certbot/www/` не отслеживается и не игнорируется, `reset --hard` не трогает ни его, ни игнорируемые файлы.

Если префикс томов в `docker volume ls` окажется не `os_`, остановиться. В `.env` пишется фактический префикс, каталог не переносить.

`docker compose down -v` и `docker volume rm os_*` не выполнять.

## Почему тома не пропадут

Имя тома — `{проект}_{том}`. Compose берёт `COMPOSE_PROJECT_NAME` из `.env` раньше, чем имя каталога. Строка `COMPOSE_PROJECT_NAME=os`, записанная до первого `up` из `/opt/oscript`, продолжает те же тома.

Без этой строки `up` из нового каталога создаст пустые `oscript_*`: файлы сайта останутся в старых томах, а контейнеры будут смотреть в пустые.

## Что переезжает файлами

| Путь | Зачем |
| --- | --- |
| `.env` | секреты и `COMPOSE_PROJECT_NAME` |
| `web/certbot/conf/` | живые сертификаты, в git их нет |
| `web/certbot/www/` | webroot ACME |
| `logs/` | логи nginx и certbot |
| сам git clone | compose, nginx, monitoring |

## 1. Зафиксировать имя проекта в старом каталоге

Каталог принадлежит root, поэтому правки файла идут через sudo.

```bash
cd /home/andrei/os

bak=.env.bak.$(date +%Y%m%d)
sudo cp -a .env "$bak"
sudo chmod 600 "$bak"

sudo grep -q '^COMPOSE_PROJECT_NAME=' .env \
  && sudo sed -i 's/^COMPOSE_PROJECT_NAME=.*/COMPOSE_PROJECT_NAME=os/' .env \
  || printf '\nCOMPOSE_PROJECT_NAME=os\n' | sudo tee -a .env >/dev/null

sudo grep '^COMPOSE_PROJECT_NAME=' .env
sudo chown root:root .env
sudo chmod 600 .env

sudo docker-compose ps
sudo docker volume ls | grep '^local *os_'
```

`up -d` в старом каталоге не нужен: строка `COMPOSE_PROJECT_NAME=os` конфигурацию не меняет, а файл `docker-compose.yml` здесь в состоянии `UU` и может содержать маркеры конфликта, на которых `docker-compose` упадёт. Ожидание: те же контейнеры, те же тома `os_*`, сайты открываются.

Снимок до копирования:

```bash
sudo docker ps --format '{{.Names}} {{.Status}}' > /tmp/ps.before
sudo docker volume ls > /tmp/vols.before
```

## 2. Скопировать дерево

Стек можно не гасить: контейнеры держат старые mount, `rsync` копирует файлы.

```bash
sudo mkdir -p /opt/oscript
sudo rsync -aHAX --numeric-ids /home/andrei/os/ /opt/oscript/

sudo test -d /opt/oscript/web/certbot/conf/live
sudo test -f /opt/oscript/.env
sudo grep -q '^COMPOSE_PROJECT_NAME=os$' /opt/oscript/.env
```

Если `conf/live` нет, сертификаты не скопировались — дальше не идти. `conf/live/*` — симлинки на `archive/`; `rsync -a` их сохраняет.

Непосредственно перед шагом 3 повторить тот же `rsync` (уйдёт дельта). `--delete` не использовать.

Дальше каталог становится общим, а git — копией `master`.

```bash
sudo chown -R deploy:docker /opt/oscript
sudo find /opt/oscript -type d -exec chmod 2755 {} +
sudo chmod 640 /opt/oscript/.env
sudo rm -f /opt/oscript/.env.bak.*

sudo -u deploy git -C /opt/oscript remote set-url origin https://github.com/EvilBeaver/oscript-infrastructure.git
sudo -u deploy git -C /opt/oscript fetch origin
sudo -u deploy git -C /opt/oscript checkout -f master
sudo -u deploy git -C /opt/oscript reset --hard origin/master
sudo -u deploy git -C /opt/oscript status
```

`reset --hard` убирает конфликт `docker-compose.yml` и любые локальные правки отслеживаемых файлов. Неотслеживаемые `.env`, сертификаты и логи остаются. `git status` после этого чистый, ветка `master`.

Права: владелец `deploy`, группа `docker`, каталоги `2755` с setgid (новые файлы наследуют группу). Зайти в дерево может любой локальный пользователь. Секреты в `.env` читают `deploy` и группа `docker`; режим `0640`, не `0777`. Приватные ключи сертификатов сохраняют режим, с которым их принёс `rsync` (обычно `0600`): контейнер nginx работает от root и эти файлы читает.

Копию `.env.bak` в новом каталоге не хранить. В старом каталоге backup до конца окна можно оставить и удалить вместе с `os.bak.YYYYMMDD`.

На B git новее и ругается на «чужой» каталог. Туда же, когда появится `/opt/oscript`:

```bash
git config --system --add safe.directory /opt/oscript
```

На A git 2.7.4 этой проверки нет.

## 3. Поднять стек из нового пути

В `/opt/oscript` уже `origin/master`. Если он отличается от файла, с которым стек работал в `/home/andrei/os`, этот `up` заодно применит версию из репозитория. Это и есть откат локального конфликта.

```bash
cd /opt/oscript
sudo docker-compose up -d --remove-orphans
sudo docker-compose ps
sudo docker volume ls | grep os_
```

В списке томов по-прежнему `os_web_content`, `os_minio_data` и остальные, не `oscript_*`.

```bash
sudo docker inspect "$(sudo docker ps -qf name=nginx)" \
  --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
```

В выводе пути `/opt/oscript/web/certbot/...` и `/opt/oscript/logs/nginx`. Если остался `/home/andrei/os`, `up` взял не тот каталог или в `.env` нет `COMPOSE_PROJECT_NAME`.

Проверить в браузере `https://oscript.io`, `https://hub.oscript.io`, `https://grafana.oscript.io`.

Имена контейнеров после v1 остаются с подчёркиваниями (`os_nginx_1`). Имя `os-nginx-1` появится только у плагина v2 без явного `container_name` — это уже модульная сборка, не этот перенос.

## 4. Старый каталог

Когда шаг 3 зелёный, старый clone не удалять в тот же час:

```bash
sudo mv /home/andrei/os /home/andrei/os.bak.$(date +%Y%m%d)
```

Через день-два, если стек жив и `web/certbot` на новом месте полный, каталог `os.bak.*` можно убрать.

Дальше руками:

```bash
cd /opt/oscript
sudo -u deploy git pull
sudo -u deploy docker-compose up -d
```

Pull делает `deploy`: каталог принадлежит ему. Остальные члены `docker` каталог читают и могут запускать compose. `deploy` в группе `docker`, поэтому сокет ему доступен без root.

## Откат

Пока `os.bak.YYYYMMDD` на диске, в его `.env` есть `COMPOSE_PROJECT_NAME=os`:

```bash
cd /home/andrei/os.bak.YYYYMMDD
sudo docker-compose up -d
```

Поднимутся те же тома. `/opt/oscript` после отката можно убрать.

## Что не делать

- `docker-compose down -v` и `docker volume rm os_*`
- первый `up` из `/opt/oscript` без `COMPOSE_PROJECT_NAME=os`
- копировать git без `web/certbot/conf` и `.env`
- менять имя проекта на `oscript`
- оставлять каталог `root:root` внутри чьего-то `/home`
- ставить `.env` в режим `0777`
