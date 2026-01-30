#!/bin/bash

# Настройка rclone через переменные окружения
# Имя remote в env-переменных должно быть в UPPERCASE, а в команде - в lowercase
export RCLONE_CONFIG_YANDEX_TYPE=s3
export RCLONE_CONFIG_YANDEX_PROVIDER=Other
export RCLONE_CONFIG_YANDEX_ACCESS_KEY_ID=${S3_ACCESS_KEY_ID}
export RCLONE_CONFIG_YANDEX_SECRET_ACCESS_KEY=${S3_SECRET_ACCESS_KEY}
export RCLONE_CONFIG_YANDEX_ENDPOINT=${S3_ENDPOINT}
export RCLONE_CONFIG_YANDEX_REGION=${S3_REGION}

if [ -z "$S3_BUCKET" ]; then
    echo "Ошибка: Переменная S3_BUCKET не задана."
    exit 1
fi

SOURCE_DIR="/base_data/${SYNC_SUBDIR}"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Ошибка: Каталог $SOURCE_DIR не найден. Проверьте монтирование volume и переменную SYNC_SUBDIR."
    exit 1
fi

echo "--- Запуск воркера синхронизации S3 ---"
echo "Интервал: $SYNC_INTERVAL"
echo "Бакет: $S3_BUCKET"
echo "Локальный каталог: $SOURCE_DIR"

# Функция синхронизации
do_sync() {
    echo "$(date): Начало синхронизации..."
    # Используем copy, чтобы не удалять файлы в облаке, если они удалены локально
    rclone copy "$SOURCE_DIR" yandex:${S3_BUCKET} --progress
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ]; then
        echo "$(date): Синхронизация завершена успешно."
    else
        echo "$(date): Ошибка при синхронизации! Код выхода: $EXIT_CODE"
    fi
}

# 1. Первичная заливка при старте контейнера
echo "Выполняется первичная заливка..."
do_sync

# 2. Бесконечный цикл для регулярных обновлений
while true; do
    echo "Следующая синхронизация через $SYNC_INTERVAL..."
    sleep $SYNC_INTERVAL
    do_sync
done
