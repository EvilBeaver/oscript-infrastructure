#!/bin/bash

#TODO: внести внутрь compose

docker run --rm -v os_web_content:/mnt/src -v /home/andrei/backup:/mnt/dest busybox tar -zcvf /mnt/dest/"hub-$(date '+%Y-%m-%d').tar.gz" /mnt/src/hub.oscript.io/download/
docker run --rm -v os_web_content:/mnt/src -v /home/andrei/backup:/mnt/dest busybox tar -zcvf /mnt/dest/"oscript-$(date '+%Y-%m-%d').tar.gz" /mnt/src/oscript.io/download/versions/