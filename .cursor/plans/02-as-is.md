# 2. Как устроена нода A

[Решения](01-decisions.md) · [оглавление](README.md) · дальше: [целевое устройство](03-target.md)

Снимок 2026-10-18 с живой A. Это спецификация ролей `common`, `firewall`, `spoofdpi`, `wireguard` и проверка «после = как до». Сырой дамп (iptables, crontab, unit-файлы) в git не кладём: репозиторий публичный. Перед тем как роль начнёт управлять файрволом, оператор ещё раз снимает эталон скриптом и вычитывает его на токены; в книгу попадают уже обезличенные факты.

Каталог стека с 2026-10-24 — `/opt/oscript` (раздел «Git на A»). Остальное в этой главе — снимок 2026-10-18.

## Хост

| Параметр | Значение |
| --- | --- |
| ОС / ядро | Ubuntu 16.04.7, ядро `4.4.0-210-generic`. Стандартная поддержка закончилась в 2021. Ubuntu Pro не подключён, ESM на дату снимка не был оформлен |
| Диск | `/` 89 ГБ, занято около 80 %, свободно около 18 ГБ. Самый крупный том — `os_jenkins_home`, 17 ГБ. Вторую копию данных на этом диске не делать |
| Пользователь людей | `andrei`: группы `sudo`, `docker` (GID 995), `powerusers`. Sudo с паролем, `NOPASSWD` нет |
| Ещё в группе `docker` | `otymko`, `bonv`, `nixel`, `segate`. После Ansible ручные правки стека на A не делаются: роль `app` разойдётся с ними |
| SSH | только ключи, `PermitRootLogin without-password`, пароль выключен. Конфиг старый (DSA host key, `ServerKeyBits 1024`) |
| Python / git / OpenSSL | 3.5.2 / 2.7.4 / 1.0.2g. Компилятора нет, пока не поставлен `build-essential`. TLS до GitHub и PyPI с хоста открывается |
| Сторонний агент | Yandex Unified Agent, `unified-agent.service`, слушает `*:16300` и `127.0.0.1:16301`. Снаружи закрыт файрволом. Роль `common` его не трогает и может лишь проверять, что сервис активен |

Публичный адрес — `/32` на `eth0`, шлюз `10.0.0.1` onlink. Адрес в inventory вписывает оператор.

## Docker

| Параметр | Значение |
| --- | --- |
| Engine | **18.09.0**, API 1.39, overlay2, cgroupfs. Клиент `docker` — 20.10.7, он новее сервера |
| Тот CLI, которым создан стек | `docker-compose` **v1.23.2** (`/usr/local/bin/docker-compose`) |
| Плагин | `docker compose` v2.40.3 в `/usr/local/lib/docker/cli-plugins/`. Оператор подтвердил: `up` проходит и v1, и этим плагином |
| Имена контейнеров | `os_nginx_1`, `os_openhub_1`, … — подчёркивания, так именует v1. Плагин v2 без явного `container_name` создаст `os-openhub-1` |
| Проект | `os` (`COMPOSE_PROJECT_NAME=os` в `.env`). Тома `os_*`. Каталог стека — `/opt/oscript` |
| `daemon.json` | json-file, `max-size` 1g, `max-file` 3, registry-mirrors (gcr, timeweb). Drop-in у `docker.service` нет |
| Сети | `bridge` `172.17.0.0/16`, `os_default` `172.18.0.0/16`, `os_openhub` `172.19.0.0/16` |
| `DOCKER_GID` | 995, совпадает с подстановкой в compose |

Роль на A Docker не переустанавливает. `daemon.json` не затирать. Любую новую возможность Compose проверять командой `docker compose config` на самой A до `up`: Engine старый.

Контейнеры стека: openhub `segateekb/openhub:0.21.0`, nginx, site, lgtm `grafana/otel-lgtm:0.33.1`, hostmetrics, jenkins, minio, openhub_db (Postgres 17), tg_bot, certbot, s3-sync. Образ `segateekb/openhub:0.22.0` скачан и не запущен — модули пинят **0.21.0**. Контейнеры `opm_hub` и `opm_hub_db` в состоянии `Exited`. Сертификат, DNS и том `os_postgres_data` ещё на ноде. В репозитории сервисы, vhost и имя `hub-old.oscript.io` уже сняты.

Тома `os_*`:

| Том | Размер | Куда |
| --- | --- | --- |
| `os_jenkins_home` | 17 ГБ | остаётся на A |
| `os_web_content` | 6,3 ГБ | остаётся на A |
| `os_lgtm_data` | около 2,7–2,8 ГБ | на B |
| `os_minio_data` | около 2,2–2,3 ГБ | на B |
| `os_openhub_data` | 213 МБ | остаётся на A |
| `os_openhub_postgres_data` | около 70 МБ | остаётся на A |
| `os_postgres_data` | 67 МБ | бывший хаб, остаётся на A |

Хеш-тома и `buildx_*` к стеку не относятся.

У `site`, `jenkins` и `tg_bot` в compose опубликованы порты без привязки к адресу (`"3030"`, `"8080"`, `"5000"`). Docker выдал им случайные порты на хосте. Снаружи их держит цепочка `DOCKER-USER`. nginx ходит на эти сервисы по Docker DNS, публикация на хост для сайта не нужна. Убрать её (`expose` вместо `ports`) можно отдельным ужесточением, когда будет ясно, что с хоста этими портами никто не пользуется.

## Файрвол

Политики: `INPUT DROP`, `FORWARD DROP`, `OUTPUT ACCEPT`. IPv6: `IPV6=no` в ufw, в `ip6tables` DROP на всё, кроме lo. `net.ipv4.ip_forward=1`.

ufw включён. В пользовательских правилах открыты 22, 80, 443, 50000 (tcp и udp) и `8888/tcp` из `172.17.0.0/16`.

`/etc/ufw/after.rules` (файл менялся 2026-10-01, `ufw.service` enabled) содержит:

- `DOCKER-USER`: сначала `RETURN` для RELATED,ESTABLISHED; затем `RETURN` с `eth0` на tcp 80, 443, 50000; затем `DROP` с `eth0`;
- разрешение `8888/tcp` на интерфейсах `docker0` и `br+`.

Смысл `DOCKER-USER`: с интернета в контейнеры проходят только 80, 443 и 50000. Правила `ufw allow/deny` на опубликованные порты Docker не действуют — Docker идёт через свои цепочки. Проверка снаружи — `nmap`, не `ufw status`.

`docker.service` не зависит от `ufw.service`. Между их стартом после перезагрузки опубликованные порты могут быть открыты. В роль закладывается drop-in `docker.service.d/ufw.conf` с `After=ufw.service`. В сегодняшнем эталоне этого drop-in нет.

Ручное правило `iptables` на 8888 из истории root не персистентно и дублирует ufw. В роль его не переносить.

## SpoofDPI

Jenkins ходит наружу через `HTTPS_PROXY` и `HTTP_PROXY` `http://host.docker.internal:8888`. В compose `host.docker.internal` задан как `172.17.0.1` (адрес docker0). Прокси — SpoofDPI 1.5.3 (`f31018f`), бинарь `/usr/local/bin/spoofdpi`, владелец файла `andrei`.

Юнит `/etc/systemd/system/spoof-dpi.service`, enabled, работает от root и слушает `0.0.0.0:8888`:

```
ExecStart=/usr/local/bin/spoofdpi -listen-addr 0.0.0.0:8888 --no-tui true --log-level warn
```

От интернета порт закрыт только политикой INPUT и ufw. При `ufw disable` это открытый прокси. Целевое состояние роли: тот же юнит `spoof-dpi.service`, bind только на адрес docker0. Пока роль не применена, живой процесс не перенастраивать в стороне от плана.

## Git на A

Боевой каталог — `/opt/oscript` (сертификаты nginx, логи, файлы `monitoring/`). Владелец `deploy`, группа `docker`, каталоги `2755`. Pull делает `deploy`. Ветка `master`, дерево на `origin/master`. `.env` в режиме `0640`, владелец `deploy`, группа `docker`, в файле есть `COMPOSE_PROJECT_NAME=os`.

Каталог `/home/segate/os-compose` — не git и не боевой compose; это набор старых копий файла.

Внешние проверки доменов — StatusCake. На хостах от него ничего не установлено; в окне переноса паузу ставят в их кабинете.

## Что ещё снимает оператор

- Имена переменных боевого `.env` без значений — сверить с `openhub.env.example`, `minio/.env.example` и корневым compose.
- Публичный IP A — в inventory на B.
- Установлен ли `rsync` на A: окно переноса (этап 7) копирует тома с A на B через `sudo rsync`.
- `iperf3` до B и повторный `ping` уже по WireGuard.
- Свободное место и тип диска на B (под данные MinIO и LGTM с запасом; сами тома около 5 ГБ).
- В UI Jenkins: есть ли Artifact Manager и какой у него endpoint. Пока артефакты в облачном S3.
- После появления окна — что ufw и `DOCKER-USER` поднимаются после перезагрузки. По файлам это уже персистентно; живой reboot ещё не подтверждался.
