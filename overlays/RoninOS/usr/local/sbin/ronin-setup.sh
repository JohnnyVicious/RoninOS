#!/bin/bash

# Function to check for a module and echo its path
_check_npm_module() {
    local module=$1
    if npm list -g | grep -q "@$module@"; then
        return 0  # Success
    else
        return 1  # Failure
    fi
}

_set_troubleshooting_passwords() {
    echo "Resetting psswords of $USER and root to Ronindojo369 for troubleshooting via SSH."
    sudo chpasswd <<<"$USER:Ronindojo369" 
    sudo chpasswd <<<"root:Ronindojo369"
    exit 1
}

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

# Verifying root password from info.json
ROOTPASSWORD_STORED=$(jq -r '.user[] | select(.name=="root") | .password' /home/"${RONINUSER}"/.config/RoninDojo/info.json)
# Attempt a command with the root password
echo "$ROOTPASSWORD_STORED" | sudo -S ls /root >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Verifying root password from info.json : root password is valid."
else
    echo "Verifying root password from info.json : root password $ROOTPASSWORD_STORED is invalid!"
    _set_troubleshooting_passwords
fi

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

    # PM2 installation can fail since path for PM2 is static in function _ronin_ui_install
    # Check if RoninUI is in the list of PM2 processes and is online
    if pm2 ls | grep -q "RoninUI.*online"; then
        echo "RoninUI appears to be successfully installed."    
    else
        echo "RoninUI is not running or not found, trying to correct."        
        cd /home/ronindojo/Ronin-UI || (echo "RoninUI path not found!"; _set_troubleshooting_passwords)        

        # Validate npm modules
        _check_npm_module npm || (echo "Module npm is missing!"; _set_troubleshooting_passwords)
        _check_npm_module corepack || (echo "Module corepack is missing!"; _set_troubleshooting_passwords)
        _check_npm_module pm2 || (echo "Module pm2 is missing!"; _set_troubleshooting_passwords)
        _check_npm_module pnpm || (echo "Module pnpm is missing!"; _set_troubleshooting_passwords)

        # Validate PM2 webapp
        pm2 ls | grep -q "RoninUI" && pm2 delete "RoninUI"    
        pm2 save 1>/dev/null        
        pm2 startup
        npm_path=$(npm list -g | head -1)
        sudo env PATH="$PATH:/usr/bin" "$npm_path"/node_modules/pm2/bin/pm2 startup systemd -u ronindojo --hp /home/ronindojo
        pm2 start pm2.config.js
        pm2 save
        pm2 ls | grep -q "RoninUI.*online" || (echo "Error: PM2 instance RoninUI is still not running, something went wrong during setup!"; _set_troubleshooting_passwords)
        pm2 kill
        sudo systemctl start pm2-ronindojo
    fi

    # TODO: could add some checks to see if install completed succesfully

    # Restore getty
    sudo systemctl start ronin-post.service
    if ! systemctl is-active pm2-ronindojo.service; then
        sudo systemctl start pm2-ronindojo.service
    fi    
    
    # Disable setup services    
    sudo systemctl disable ronin-setup.service            
    sudo systemctl disable --now ronin-pre.service
    
    # Disable passwordless sudo, can be commented while troubleshooting, need to build a warning in RoninUI to display when this is still enabled (system security & makes login possible without password)
    # sudo sed -i '/ronindojo/s/ALL) NOPASSWD:ALL/ALL) ALL/' /etc/sudoers

    # Create the setup-complete file so this service does not run twice by accident
    touch "$HOME"/.logs/setup-complete    
    
fi
