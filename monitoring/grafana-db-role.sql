-- Роль, под которой Grafana читает каталог хаба для справочного дашборда.
-- Выполняется руками, один раз и после каждой смены списка колонок:
--
--   printf "\\set password '%s'\n" "$GRAFANA_DB_PASSWORD" | cat - monitoring/grafana-db-role.sql \
--     | docker exec -i os_openhub_db_1 psql -U openhub -d openhub -v ON_ERROR_STOP=1 -f -
--
-- Пароль идёт через stdin, а не аргументом: аргументы видны в списке процессов.
--
-- Права выданы на колонки, а не на таблицы: учётки, сессии, токены и настройки роли не видны,
-- как и идентификаторы владельцев и публикаторов. Права на колонки не мешают хабу менять схему;
-- представления мешали бы, поэтому их здесь нет.

select 'create role grafana_ro login'
where not exists (select 1 from pg_roles where rolname = 'grafana_ro') \gexec

alter role grafana_ro with login password :'password'
  nosuperuser nocreatedb nocreaterole noreplication noinherit connection limit 5;
alter role grafana_ro set default_transaction_read_only = on;
alter role grafana_ro set statement_timeout = '15s';

grant connect on database openhub to grafana_ro;
grant usage on schema public to grafana_ro;

grant select ("Идентификатор", "Имя", "Тип", "ПоУмолчанию", "Видимость", "КвотаМб", "ЗанятоБайт", "Создан")
  on "Пулы" to grafana_ro;

grant select ("Идентификатор", "ПулИдентификатор", "ИмяНижнийРегистр", "Имя", "Лицензия", "АдресРепозитория",
              "Устарел", "Скрыт", "Создан", "ПоследняяПубликация")
  on "Пакеты" to grafana_ro;

grant select ("Идентификатор", "ПакетИдентификатор", "Версия", "semverМажор", "semverМинор", "semverПатч",
              "semverПререлиз", "Размер", "Отозвана", "Опубликована")
  on "ВерсииПакетов" to grafana_ro;

grant select ("Идентификатор", "ПакетИдентификатор", "ВерсияИдентификатор", "ДатаДень", "Количество")
  on "СкачиванияАгрегаты" to grafana_ro;

grant select ("Идентификатор", "ПакетИдентификатор", "ВерсияИдентификатор", "Источник",
              "ДовереннаяПубликация", "Зафиксировано")
  on "ПроисхождениеВерсий" to grafana_ro;

grant select ("Идентификатор", "ВерсияИдентификатор", "ИмяПакетаНижнийРегистр", "ИмяПакета", "ДляРазработки")
  on "ЗависимостиВерсий" to grafana_ro;
