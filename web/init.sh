#!/bin/bash

# install compose

curl -L https://github.com/docker/compose/releases/download/1.11.2/docker-compose-`uname -s`-`uname -m` > docker-compose
mv docker-compose /usr/local/bin/
chmod +x /usr/local/bin/docker-compose

# install git

apt-get install -y git


