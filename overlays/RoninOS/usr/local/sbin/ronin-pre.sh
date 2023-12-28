# Parameters
NEWHOSTNAME="RoninDojo"
USER="ronindojo"

# Generate random passwords for root and $USER
PASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c'21')"
ROOTPASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c'21')"

# Make sure the ronin-setup.service is disabled
systemctl is-enabled --quiet ronin-setup.service && sudo systemctl disable --now ronin-setup.service

# Set the hostname and reboot, since this service will be disabled after its run this should not create conflicts when the user changes the hostname
[ "$(hostname)" != "$NEWHOSTNAME" ] && sudo hostnamectl set-hostname "$NEWHOSTNAME" && sudo reboot

echo "$(ls -l /home)" # DEBUG

# Set the owner for the home folder, noticed this does not (always?) happen during the Armbian build
chown -R "$USER":"$USER" /home/"$USER"

# Enable passwordless sudo for $USER
grep -q "${USER}.*NOPASSWD:ALL" /etc/sudoers || sudo sed -i "/${USER}/s/ALL) ALL/ALL) NOPASSWD:ALL/" /etc/sudoers

# Set and store the random passwords if config.json does not already exist
if [ ! -f /home/"${USER}"/.config/RoninDojo/config.json ]; then
    echo "Adding the random generated passwords to info.json"
    mkdir -p /home/"${USER}"/.config/RoninDojo
    chpasswd <<<"root:$ROOTPASSWORD"
    chpasswd <<<"$USER:$PASSWORD"
    cat <<EOF >/home/"${USER}"/.config/RoninDojo/info.json
{"user":[{"name":"${USER}","password":"${PASSWORD}"},{"name":"root","password":"${ROOTPASSWORD}"}]}
EOF
fi

# Check if pre-reqs for the ronin-setup.service are fulfilled
[ ! -f /home/"${USER}"/.config/RoninDojo/info.json ] && (echo "info.json has not been created!"; chpasswd <<<"$USER:Ronindojo369"; exit)

# Only enable the RoninDojo setup service after everything has been validated
systemctl enable --now ronin-setup.service
