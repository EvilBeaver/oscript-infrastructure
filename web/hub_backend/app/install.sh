#!/bin/bash

mkdir bin
mkdir lib

echo folders created

cp -rv /usr/share/oscript/bin/* bin/
cp -rv /usr/share/oscript/lib/* lib/
echo oscript copied
cp ASPNETHandler.dll bin/
echo handler copied

echo starting opm
opm install -dest lib
echo done