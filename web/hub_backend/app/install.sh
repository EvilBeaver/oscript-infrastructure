#!/bin/bash

mkdir bin
mkdir lib
cp -r /usr/share/oscript/bin/* bin/
cp -r /usr/share/oscript/lib/* lib/
cp ASPNETHandler.dll bin/

opm install -dest lib