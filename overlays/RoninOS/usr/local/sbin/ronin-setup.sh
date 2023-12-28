#!/bin/bash

# This service will run as the $USER, passwordless sudo should have been set at this point

echo "Continue only if you can access the service user's home folder"
cd "$HOME" || exit

echo "Give time for Startup to finish before trying to update the repo"
sleep 30s 

echo "Clone Repo"
git clone -b master https://code.samourai.io/ronindojo/RoninDojo /home/ronindojo/RoninDojo
cd /home/ronindojo/RoninDojo

# Source files for default values and generic functions
. Scripts/defaults.sh
. Scripts/functions.sh

# Run main
if _main; then
    echo "Check if passwordless sudo is enabled"
    # USER="ronindojo"
    
    if sudo -n true 2>/dev/null; then
        echo "User $USER has passwordless sudo access."
    else
        echo "Error: User $USER does not have passwordless sudo access";
        cat /home/"$USER"/.config/RoninDojo/config.json
        exit 1;
    fi
    
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
