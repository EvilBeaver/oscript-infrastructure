#!/bin/bash

if [ -z "${address}" ] ; then
    echo "address is not set"
    address=$(/sbin/ip address | grep 'inet '| awk '$NF =="eth0" {split($2, a, "/"); print a[1]}')
fi

echo "Docker address: ${address}"

fastcgi-mono-server4 /applications=/:/var/www/oscript.io /socket=tcp:${address}:9001