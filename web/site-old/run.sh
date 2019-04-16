#!/bin/bash

if [ -z "${address}" ] ; then
    echo "address is not set"
    all=$(/sbin/ip address | grep 'inet '| awk '{split($2, a, "/"); print a[1]}')
    echo "$all"
    
    address=$(/sbin/ip address | grep 'inet '| awk '$NF =="eth0" {split($2, a, "/"); print a[1]}')
fi

echo "Docker address: ${address}"

mkdir -p /var/www/old.oscript.io

fastcgi-mono-server4 /applications=/:/var/www/old.oscript.io /socket=tcp:${address}:9001