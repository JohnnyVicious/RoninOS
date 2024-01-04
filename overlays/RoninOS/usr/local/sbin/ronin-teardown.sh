#!/bin/bash

[ ! -f /home/ronindojo/.logs/presetup-complete ] && (sleep 30s; exit 0;)

while [ ! -f /home/ronindojo/.logs/setup-complete ]
do
   echo "Waiting to resurrect PM2."
   sleep 30s
   if [ -f /home/ronindojo/.logs/setup-complete ]; then
      echo "Detected RoninDojo setup completion."
      if ! systemctl is-active pm2-ronindojo.service; then
        echo "Starting pm2-ronindojo.service"
        sudo systemctl start pm2-ronindojo.service
      else 
         echo "pm2-ronindojo.service already started"
      fi
      break
   fi
done
