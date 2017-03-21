FROM jenkins:2.32.3

# oscript, пакеты и т.п.
COPY tools/* /opt/ci-tools/

RUN dpkg -i tools/*

# todo - настроить внутри контейнера запуск oscript