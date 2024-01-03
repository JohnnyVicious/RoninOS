#!/bin/bash

rm /etc/motd

bash -c "cat <<EOF > /etc/motd
Welcome to RoninDojo!

Website:   ronindojo.io
Wiki:      wiki.ronindojo.io

Nodejs:    $(node -v)
EOF"

touch /tmp/motd-actived
