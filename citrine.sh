#!/usr/bin/env bash

if [[ ! "$EUID" == "0" ]]; then
    echo "Run as root."
    exit 1
fi

script -O /var/log/citrine.log -q -c "./citrine.internal.sh"
cp /var/log/citrine.log /mnt/var/.
echo "Run 'reboot' to restart. :)"
