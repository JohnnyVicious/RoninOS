#!/bin/bash

rm /etc/motd

bash -c "cat <<EOF > /etc/motd
Welcome to RoninDojo!

Website:   ronindojo.io
Wiki:      wiki.ronindojo.io

Nodejs:    echo "$(node -v)"
NPM:       echo "$(npm -v)"
PM2:       echo "$(pm2 -v)"
PNPM:      echo "$(pnpm -v)"
Docker:    echo "$(docker --version | grep -oP 'Docker version \K[^,]+')"
EOF"

touch /tmp/motd-actived
