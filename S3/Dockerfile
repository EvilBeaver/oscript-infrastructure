# Используем легкий образ Alpine Linux
FROM alpine:latest

# Устанавливаем rclone, bash и необходимые сертификаты
RUN apk add --no-cache rclone bash ca-certificates

# Создаем директории для данных и конфига
RUN mkdir -p /data /config

# Копируем скрипт управления
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Настройки по умолчанию (можно переопределить при запуске через -e)
ENV SYNC_INTERVAL="12h"
ENV SYNC_SUBDIR="hub.oscript.io"
ENV RCLONE_REMOTE_NAME="yandex"
ENV S3_BUCKET=""
ENV S3_ENDPOINT="https://storage.yandexcloud.net"
ENV S3_ACCESS_KEY_ID=""
ENV S3_SECRET_ACCESS_KEY=""
ENV S3_REGION="ru-central1"

# Запускаем скрипт-воркер
ENTRYPOINT ["/entrypoint.sh"]
