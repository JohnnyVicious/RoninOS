#!/bin/bash

# This service will run as the $USER, passwordless sudo should have been set at this point

# Continue only if you can access the service user's home folder
cd "$HOME" || exit

# give time for Startup to finish before trying to update the repo. 
sleep 30s 

# Clone Repo
git clone -b master https://code.samourai.io/ronindojo/RoninDojo /home/ronindojo/RoninDojo
cd /home/ronindojo/RoninDojo

# Source files for default values and generic functions
. Scripts/defaults.sh
. Scripts/functions.sh

# Run main
if _main; then
    # Check and enable passwordless sudo
    grep -q "${USER}.*NOPASSWD:ALL" /etc/sudoers || sudo sed -i "/${USER}/s/ALL) ALL/ALL) NOPASSWD:ALL/" /etc/sudoers
    
    # Run system setup
    Scripts/Install/install-system-setup.sh system

    # Run RoninDojo install
    Scripts/Install/install-dojo.sh dojo

    # Restore getty
    sudo systemctl start ronin-post.service
    if ! systemctl is-active pm2-ronindojo.service; then
        sudo systemctl start pm2-ronindojo.service
    fi    
    sudo systemctl disable ronin-setup.service    
    touch /home/ronindojo/.logs/setup-complete
fi
