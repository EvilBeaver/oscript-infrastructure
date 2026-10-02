-- Приёмная таблица под выгрузку из старого хаба. Запускается в базе сервиса openhub_db
-- перед apply-openhub.sql; данные в неё заливает run.sh командой \copy.
--
-- Таблица временная по смыслу, но не TEMP: psql заливает данные отдельным сеансом.
-- apply-openhub.sql удаляет её, когда перенос зафиксирован.

DROP TABLE IF EXISTS opm_import;

CREATE TABLE opm_import (
    имя_пакета       text,
    версия           text,
    версия_создана   timestamp,
    версия_обновлена timestamp,
    тестовая_сборка  boolean,
    пакет_создан     timestamp,
    пакет_обновлён   timestamp,
    описание         text,
    ключевые_слова   text,
    ссылка_на_проект text,
    автор            text,
    автор_почта      text,
    автор_учётка     text
);
