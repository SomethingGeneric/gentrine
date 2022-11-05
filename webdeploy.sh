#!/usr/bin/env bash

if [[ ! "$EUID" == "0" ]]; then
    echo "Either you aren't root, or your env is fucked"
    exit 1
fi

cd ~

down_c=""

# TODO: other download handlers
which curl
if [[ ! "$?" == "1" ]]; then
    down_c="curl"
else
    echo "No curl?"
    exit 1
fi

for f in {citrine.sh,citrine.internal.sh,continue.sh}; do
    curl -O https://raw.githubusercontent.com/SomethingGeneric/gentrine/main/$f
    chmod +x $f
done

echo "run ./citrine.sh to get started"