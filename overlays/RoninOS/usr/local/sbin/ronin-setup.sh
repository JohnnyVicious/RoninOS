#!/bin/bash

echo "RoninDojo IP : $(ip addr show | grep -E '^\s*inet\b' | grep -Ev '127\.0\.0\.1|inet6' | grep -E 'eth|wlan' | awk '{print $2}' | cut -d'/' -f1)" || echo "Something went wrong when getting the IP address."
echo "RoninDojo Model : $(tr -d '\0' < /proc/device-tree/model)" || echo "Something went wrong when getting the board model."

# This service will run as the $USER, passwordless sudo should have been set at this point
echo "Check if passwordless sudo is enabled for user $USER"  
if sudo -n true 2>/dev/null; then
    echo "User $USER has passwordless sudo access."
else
    echo "Error: User $USER does not have passwordless sudo access";
    cat "$HOME"/.config/RoninDojo/config.json
    exit 1;
fi

[ -f "$HOME"/.logs/setup-complete ] && (echo "Setup has already run, you should disable ronin-setup.service by using root."; exit 0;)

[ -f "$HOME"/.config/RoninDojo/config.json ] && (echo "File $HOME/.config/RoninDojo/config.json is missing!"; exit 1;)

while [ ! -f "$HOME"/.logs/presetup-complete ]
do
   echo "waiting until pre-setup is complete..."
   sleep 30s
   if [ -f "$HOME"/.logs/presetup-complete ]; then
      break
   fi
done

echo "Continue only if you can access the service user's home folder"
cd "$HOME" || exit 1;

echo "Give time for Startup to finish before trying to clone the repo"
sleep 75s
REPO="--branch master https://code.samourai.io/ronindojo/RoninDojo.git"
[ ! -d "$HOME"/RoninDojo ] && (echo "Cloning repo : $(echo $REPO)"; git clone $(echo "$REPO") "$HOME"/RoninDojo)
[ ! -d "$HOME"/RoninDojo ] && (echo "Cloning repo failed!"; exit 1;)
cd "$HOME"/RoninDojo || exit 1;

# Source files for default values and generic functions
. Scripts/defaults.sh
. Scripts/functions.sh

# Run main
if _main; then    

    sudo apt-get purge -y --autoremove nodejs npm
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"   
    nvm install 16
    nvm use 16
    nvm alias default 16
    echo "Checking NVM version : $(nvm -v)"

    echo "Installing NPM packages"
    sudo npm i -g npm@8
    sudo npm i -g pnpm@7
    sudo npm i -g pm2

    echo "Checking nodejs version : $(node -v)"
    echo "Checking npm version : $(npm -v)"    
    echo "Checking pnpm version : $(pnpm -v)"
    echo "Checking pm2 version : $(pm2 -v)"

    # Run system setup
    Scripts/Install/install-system-setup.sh system

    # Run RoninDojo install
    Scripts/Install/install-dojo.sh dojo

    # TODO: could add some checks to see if install completed succesfully

    # Restore getty
    sudo systemctl start ronin-post.service
    if ! systemctl is-active pm2-ronindojo.service; then
        sudo systemctl start pm2-ronindojo.service
    fi    
    
    # Disable setup services    
    sudo systemctl disable ronin-setup.service            
    sudo systemctl disable --now ronin-pre.service
    
    # Disable passwordless sudo (can be commented for troubleshooting)
    # sudo sed -i '/ronindojo/s/ALL) NOPASSWD:ALL/ALL) ALL/' /etc/sudoers
    touch "$HOME"/.logs/setup-complete    
    
    echo "[FINAL] Checking nodejs version : $(node -v)"
    echo "[FINAL] Checking npm version : $(npm -v)"    
    echo "[FINAL] Checking pnpm version : $(pnpm -v)"
    echo "[FINAL] Checking pm2 version : $(pm2 -v)"
    sleep 30s
fi
