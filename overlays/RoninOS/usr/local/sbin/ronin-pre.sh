# Parameters
NEWHOSTNAME="RoninDojo"
RONINUSER="ronindojo"

# Generate random passwords for root and $RONINUSER
#PASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c'21')"
PASSWORD="Ronindojo369"
ROOTPASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c'21')"

echo "Making sure the ronin-setup.service is disabled"
systemctl is-enabled --quiet ronin-setup.service && systemctl disable --now ronin-setup.service

echo "Set the hostname and reboot, since this service will be disabled after its run this should not create conflicts when the user changes the hostname"
[ "$(hostname)" != "$NEWHOSTNAME" ] && echo "Changing hostname to $NEWHOSTNAME"; hostnamectl set-hostname "$NEWHOSTNAME" && shutdown -r now

echo "$(ls -l /home)" # DEBUG ownership of home folder

echo "Set the owner for the home folder" # noticed this does not (always?) happen during the Armbian build
chown -R "$RONINUSER":"$RONINUSER" /home/"$RONINUSER"

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
    cat <<EOF >/home/"${USER}"/.logs/pass_gen_timestamp.txt
$GENERATE_MESSAGE
Date and Time: $TIMESTAMP
EOF
fi

[ ! -d /home/ronindojo/.logs ] && mkdir -p /home/ronindojo/.logs && touch /home/ronindojo/.logs/{setup.logs,pre-setup.logs,post.logs}

echo "Check if pre-reqs for the ronin-setup.service are fulfilled, if not set default $RONINUSER password for troubleshooting and exit"
[ ! -f /home/"${USER}"/.config/RoninDojo/info.json ] && (echo "info.json has not been created!"; chpasswd <<<"$RONINUSER:Ronindojo369"; exit 1;)

echo "Enabling the RoninDojo setup service after everything has been validated"
systemctl enable --now ronin-setup.service
