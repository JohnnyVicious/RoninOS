#!/bin/bash

# journal+console+file:/home/ronindojo/.logs/pre-setup.logs
# Parameters
NEWHOSTNAME="RoninDojo"
RONINUSER="ronindojo"

# Generate random 21 char alphanumeric passwords for root and $RONINUSER
#PASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 21)"
PASSWORD="Ronindojo369"
ROOTPASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 21)"

sleep 60s

# Noticed the SSH service sometimes fails during boot-up, retry after sleep, maybe network init related?
systemctl is-active --quiet ssh.service || systemctl start ssh.service

echo "Making sure the ronin-setup.service is disabled"
systemctl is-enabled --quiet ronin-setup.service && (echo "ronin-setup.service was still enabled, stopping and disabling..."; systemctl disable --now ronin-setup.service)

[ -f /home/ronindojo/.logs/presetup-complete ] && (echo "Pre-setup has already run, disabling service"; systemctl disable --now ronin-pre.service; exit 0;)

echo "Check the hostname $(hostname) and reboot if it needs to be changed to $NEWHOSTNAME"
[ "$(hostname)" != "$NEWHOSTNAME" ] && (echo "Changing hostname $(hostname) to $NEWHOSTNAME and rebooting"; hostnamectl set-hostname "$NEWHOSTNAME";) && shutdown -r now
[ "$(hostname)" != "$NEWHOSTNAME" ] && (echo "Hostname $(hostname) is still not $NEWHOSTNAME, exiting..."; exit 1;)

echo "$(ls -l /home)" # DEBUG ownership of home folder

echo "Add user $RONINUSER to the docker group for sudo-less access to commands"
usermod -aG docker "$RONINUSER"

echo "Enable passwordless sudo for $RONINUSER"
grep -q "${RONINUSER}.*NOPASSWD:ALL" /etc/sudoers || sed -i "/${RONINUSER}/s/ALL) ALL/ALL) NOPASSWD:ALL/" /etc/sudoers

echo "Set and store the random passwords if config.json does not already exist"
if [ ! -f /home/"${RONINUSER}"/.config/RoninDojo/config.json ]; then
    echo "Adding the random generated passwords to info.json, $RONINUSER:$PASSWORD"
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
fi

echo "Check if the .logs folder exists, if not create and initiate logfiles"
[ ! -d /home/ronindojo/.logs ] && mkdir -p /home/ronindojo/.logs && touch /home/ronindojo/.logs/{setup.logs,pre-setup.logs,post.logs}

echo "Set the owner to $RONINUSER for the $RONINUSER home folder and all subfolders" 
# Noticed this does not happen during the Armbian build even if it is in the customize script
# Needed for ronin-setup.service that runs as ronindojo user
chown -R "$RONINUSER":"$RONINUSER" /home/"$RONINUSER"

echo "Check if pre-reqs for the ronin-setup.service are fulfilled, if not set default $RONINUSER password for troubleshooting and exit"
[ ! -f /home/"${RONINUSER}"/.config/RoninDojo/info.json ] && (echo "info.json has not been created!"; sudo chpasswd <<<"$RONINUSER:Ronindojo369"; exit 1;)

echo "Enabling the RoninDojo setup service after everything has been validated"
touch /home/ronindojo/.logs/presetup-complete
systemctl enable --now ronin-setup.service
systemctl disable ronin-pre.service
