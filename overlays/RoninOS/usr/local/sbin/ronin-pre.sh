#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Parameters
NEWHOSTNAME="RoninDojo"
RONINUSER="ronindojo"

# This service always starts when ronin-setup.service does

echo "$(ls -l /home)" # DEBUG ownership of home folder after Armbian build

[ -f /home/ronindojo/.logs/presetup-complete ] && (echo "Pre-setup has already run."; exit 0;)

echo "Enable passwordless sudo for $RONINUSER"
grep -q "${RONINUSER}.*NOPASSWD:ALL" /etc/sudoers || sed -i "/${RONINUSER}/s/ALL) ALL/ALL) NOPASSWD:ALL/" /etc/sudoers

# ronin-setup.service starts at the same time during boot-up, making sure it is disabled before the wait to avoid conflicts
echo "Making sure the ronin-setup.service is disabled"
systemctl is-enabled --quiet ronin-setup.service && (echo "ronin-setup.service was still enabled, stopping and disabling..."; systemctl disable --now ronin-setup.service)

echo "Check the hostname $(hostname) and reboot if it needs to be changed to $NEWHOSTNAME or an incremented variation..."
# Function to check if a hostname is resolvable and not just pointing to 127.0.0.1
is_hostname_resolvable() {
    # Use nslookup to check if the hostname resolves to a non-loopback address
    local resolved_ip
    resolved_ip=$(nslookup "$1" 2>/dev/null | grep -v "127.0.0.1" | grep 'Address' | awk '{print $2}' | tail -n1)
    
    if [ -z "$resolved_ip" ] || [ "$resolved_ip" = "127.0.0.1" ]; then
        return 1 # Not resolvable or resolves to loopback
    else
        return 0 # Resolvable to a non-loopback address
    fi
}

# Check if the initial hostname resolves to a non-loopback address
if is_hostname_resolvable "$NEWHOSTNAME"; then
    # Find a unique hostname
    suffix=0
    original_hostname=$NEWHOSTNAME
    while is_hostname_resolvable "$NEWHOSTNAME"; do
        ((suffix++))
        if [[ $suffix -gt 99 ]]; then
            echo "Error: Reached suffix limit without finding a unique hostname."
            Exit 1;
        fi
        NEWHOSTNAME="${original_hostname}$(printf "%02d" $suffix)"
    done
else
    echo "Current hostname '$NEWHOSTNAME' is not resolvable or resolves to 127.0.0.1. Keeping it unchanged."
fi

apt-get purge -y --autoremove nodejs npm

echo "Unique hostname determined: $NEWHOSTNAME"
[ "$(hostname)" != "$NEWHOSTNAME" ] && (echo "Changing hostname $(hostname) to $NEWHOSTNAME and rebooting"; hostnamectl set-hostname "$NEWHOSTNAME";) && shutdown -r now
[ "$(hostname)" != "$NEWHOSTNAME" ] && (echo "Hostname $(hostname) is still not $NEWHOSTNAME, exiting..."; exit 1;)

# Wait for other system services to complete
sleep 75s

# Noticed the SSH service sometimes fails during boot-up, retry after sleep, maybe network init related?
systemctl is-active --quiet ssh.service || (echo "SSH not started, trying to start..."; systemctl start ssh.service)

grep -q "127.0.0.1 $(hostname)" /etc/hosts || echo "127.0.0.1 $(hostname)" | sudo tee -a /etc/hosts # Make hostname resolvable to loopback address

echo "Add user $RONINUSER to the docker group for sudo-less access to commands"
usermod -aG docker "$RONINUSER"

echo "Set and store the random passwords if config.json does not already exist"
if [ ! -f /home/"${RONINUSER}"/.config/RoninDojo/config.json ]; then
# Generate random 21 char alphanumeric passwords for root and $RONINUSER
    #PASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 21)"
    PASSWORD="Ronindojo369" # Not entirely sure setting a random password for ronindojo is necessary before the final application install, makes troubleshooting a new build impossible?
    ROOTPASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 21)"
    echo "Adding these passwords to info.json, $RONINUSER will be asked to change password $PASSWORD on first logon of Ronin-UI."
    mkdir -p /home/"${RONINUSER}"/.config/RoninDojo
    chpasswd <<<"root:$ROOTPASSWORD"
    chpasswd <<<"$RONINUSER:$PASSWORD"
    cat <<EOF >/home/"${RONINUSER}"/.config/RoninDojo/info.json
{"user":[{"name":"${RONINUSER}","password":"${PASSWORD}"},{"name":"root","password":"${ROOTPASSWORD}"}]}
EOF
    # add validation for that the setup was done.
    GENERATE_MESSAGE="Your password was randomly generated during System Setup."
    TIMESTAMP=$(date)
    cat <<EOF >/home/"${RONINUSER}"/.logs/pass_gen_timestamp.txt
$GENERATE_MESSAGE
Date and Time: $TIMESTAMP
EOF
    chown -R "$RONINUSER":"$RONINUSER" /home/"${RONINUSER}"/.config/RoninDojo

else
    echo "The config file info.json already exists."

    # Verifying root password from info.json
    ROOTPASSWORD_STORED=$(jq -r '.user[] | select(.name=="root") | .password' /home/"${RONINUSER}"/.config/RoninDojo/info.json)
    # Attempt a command with the root password
    echo "$ROOTPASSWORD_STORED" | sudo -S ls /root >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Verifying root password from info.json : root password is valid."
    else
        echo "Verifying root password from info.json : root password $ROOTPASSWORD_STORED is invalid!"
        echo "Changing root password to $ROOTPASSWORD for troubleshooting"
        chpasswd <<<"root:$ROOTPASSWORD"
        Exit 1;
    fi
fi # end of config.json

echo "Check if the .logs folder exists, if not create and initiate logfiles"
[ ! -d /home/ronindojo/.logs ] && mkdir -p /home/ronindojo/.logs && touch /home/ronindojo/.logs/{setup.logs,pre-setup.logs,post.logs}

echo "Set the owner to $RONINUSER for the $RONINUSER home folder and all subfolders" 
# Noticed this does not happen during the Armbian build even if it is in the customize script
# Needed for ronin-setup.service that runs as ronindojo user, second time after all has been executed since this runs as root and that will be the owner of new files
chown -R "$RONINUSER":"$RONINUSER" /home/"$RONINUSER"

apt-get update && apt-get upgrade -y

echo "Check if pre-reqs for the ronin-setup.service are fulfilled, if not set default $RONINUSER password for troubleshooting and exit"
[ ! -f /home/"${RONINUSER}"/.config/RoninDojo/info.json ] && (echo "info.json has not been created!"; chpasswd <<<"$RONINUSER:Ronindojo369"; exit 1;)

echo "Enabling the RoninDojo setup service after everything has been validated"
touch /home/ronindojo/.logs/presetup-complete
systemctl enable --now ronin-setup.service
systemctl disable --now ronin-pre.service
