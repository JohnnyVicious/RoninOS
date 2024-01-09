#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Parameters
NEWHOSTNAME="RoninDojo"
RONINUSER="ronindojo"

_set_troubleshooting_passwords() {
    echo "Resetting password of $RONINUSER to Ronindojo369 for troubleshooting via SSH."
    chpasswd <<<"$RONINUSER:Ronindojo369" 
}

# This service always starts when ronin-setup.service does

echo "$(ls -l /home)" # DEBUG ownership of home folder after Armbian build

[ -f /home/ronindojo/.logs/presetup-complete ] && (echo "Pre-setup has already run."; exit 0;)

# Function to check if a hostname is resolvable and not just pointing to 127.0.0.1
_is_hostname_resolvable() {
    # Use nslookup to check if the hostname resolves to an IP address and extract the IP address
    local resolved_ip
    resolved_ip=$(nslookup "$1" 2>/dev/null | grep 'Address: ' | tail -n 1 | awk '{print $2}')

    # Get the current machine's IP addresses (excluding loopback)
    local machine_ips
    machine_ips=$(hostname -I | tr ' ' '\n')

    if [ "$resolved_ip" = "127.0.0.1" ]; then
        # Case 1: Hostname is resolvable to loopback
        echo "$1 is resolvable to loopback"
        return 1
    elif [ -z "$resolved_ip" ]; then
        # Case 2: Hostname is not resolvable
        echo "$1 is not resolvable"
        return 0
    else
        # Check if the resolved IP is one of the machine's own IP addresses
        if echo "$machine_ips" | grep -q -w "$resolved_ip"; then
            # Case 3: Hostname resolves to machine's own IP
            echo "$1 is resolvable to the machine's own IP address"
            return 1
        else
            # Case 4: Hostname is resolvable to a non-loopback, non-own IP address
            echo "$1 is resolvable to a non-loopback, non-own IP address"
            return 1
        fi
    fi
}

# Disable ipv6
_check_sysctl_availability() {
    # Check if sysctl command exists
    if ! type sysctl &> /dev/null; then
        echo "sysctl command not found"
        return 1
    fi

    # Check if sysctl configuration directory or file exists
    if [ ! -f /etc/sysctl.conf ] && [ ! -d /etc/sysctl.d/ ]; then
        echo "sysctl configuration not found"
        return 1
    fi

    return 0
}

_disable_ipv6() {
    # Apply sysctl changes to disable IPv6
    if [ ! -f /etc/sysctl.d/40-ipv6.conf ]; then
        echo "Disabling IPv6..."
        echo -e "# Disable IPV6\nnet.ipv6.conf.all.disable_ipv6 = 1" | tee /etc/sysctl.d/40-ipv6.conf >/dev/null
        # Reload sysctl configurations
        sysctl -p /etc/sysctl.d/40-ipv6.conf
        [ -d /proc/sys/net/ipv6 ] && systemctl restart --quiet systemd-sysctl
    else
        echo "IPv6 already disabled."
    fi
}

_update_hosts_file() {
    local new_hostname="$1"
    local old_hostname=$(hostname)

    # Check if the user is root, necessary for changing /etc/hosts
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root."
        return 1
    fi

    # Update /etc/hostname
    echo "$new_hostname" > /etc/hostname
    hostname "$new_hostname"

    # Update /etc/hosts
    sed -i "s/$old_hostname/$new_hostname/g" /etc/hosts

    echo "Hostname updated to $new_hostname"
}

# Perform sysctl checks
if _check_sysctl_availability; then
    _disable_ipv6
else
    echo "Cannot disable IPv6 due to missing sysctl requirements, running on unsupported distro!"
    _set_troubleshooting_passwords
    exit 1
fi

echo "Enable passwordless sudo for $RONINUSER if not already"
grep -q "${RONINUSER}    ALL=(ALL) ALL" /etc/sudoers || ( echo "${RONINUSER} didn't have sudo permissions."; sed -i "/${RONINUSER}/s/ALL) ALL/ALL) ALL/" /etc/sudoers )
grep -q "${RONINUSER}    ALL=(ALL) ALL" /etc/sudoers && ( echo "Changing ${RONINUSER} sudo permissions to passwordless"; echo "${RONINUSER}    ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers )

# ronin-setup.service starts at the same time during boot-up, making sure it is disabled before the wait to avoid conflicts
echo "Making sure the ronin-setup.service is disabled"
systemctl is-enabled --quiet ronin-setup.service && (echo "ronin-setup.service was still enabled, stopping and disabling..."; systemctl disable --now ronin-setup.service)

echo "Check the hostname $(hostname) and reboot if it needs to be changed to $NEWHOSTNAME or an incremented variation..."
# Check if the initial hostname already exists on the network
if _is_hostname_resolvable "$NEWHOSTNAME"; then
    # Find a unique hostname
    suffix=0
    original_hostname=$NEWHOSTNAME
    while _is_hostname_resolvable "$NEWHOSTNAME"; do
        ((suffix++))
        if [[ $suffix -gt 99 ]]; then
            echo "Error: Reached suffix limit without finding a unique hostname."
            _set_troubleshooting_passwords
            exit 1
        fi
        NEWHOSTNAME="${original_hostname}$(printf "%02d" $suffix)"
        echo "Checking hostname ${NEWHOSTNAME}"
    done
else
    echo "Current hostname '$NEWHOSTNAME' is not resolvable or resolves to own IP address. Keeping it unchanged."
fi

echo "Unique hostname determined: $NEWHOSTNAME"
[ "$(hostname)" != "$NEWHOSTNAME" ] && (echo "Changing hostname $(hostname) to $NEWHOSTNAME and rebooting"; _update_hosts_file "${NEWHOSTNAME}" && hostnamectl set-hostname "$NEWHOSTNAME";) && shutdown -r now
[ "$(hostname)" != "$NEWHOSTNAME" ] && (echo "Hostname $(hostname) is still not $NEWHOSTNAME, exiting..."; _set_troubleshooting_passwords; exit 1;)

ip a | grep -q inet6 && echo "Error: IPv6 address found! $(ip a | grep inet6)"

# Wait for other system services to complete
sleep 75s

# Noticed the SSH service sometimes fails during boot-up, retry after sleep, maybe network init related?
systemctl is-active --quiet ssh.service || (echo "SSH not started, trying to start..."; systemctl start ssh.service)

grep -q "127.0.0.1 $(hostname)" /etc/hosts || echo "127.0.0.1 $(hostname)" | tee -a /etc/hosts # Make hostname resolvable to loopback address

echo "Add user $RONINUSER to the docker group for sudo-less access to commands"
usermod -aG docker "$RONINUSER"

echo "Set and store the random passwords in config.json"
[ -f "/home/${RONINUSER}/.config/RoninDojo/info.json" ] && rm -rf "/home/${RONINUSER}/.config/RoninDojo/info.json"
if [ ! -f /home/"${RONINUSER}"/.config/RoninDojo/config.json ]; then
    # Generate random 21 char alphanumeric passwords for root and $RONINUSER
    PASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 21)"
    ROOTPASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 21)"
    echo "Adding these passwords to info.json, $RONINUSER will be asked to change password on first logon of Ronin-UI."
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

fi # end of config.json

echo "Check if the .logs folder exists, if not create and initiate logfiles"
[ ! -d /home/ronindojo/.logs ] && mkdir -p /home/ronindojo/.logs && touch /home/ronindojo/.logs/{setup.logs,pre-setup.logs,post.logs}

echo "Set the owner to $RONINUSER for the $RONINUSER home folder and all subfolders" 
# Noticed this can't work during the Armbian build process since that is running as root
# Needed for ronin-setup.service that runs as $RONINUSER user
chown -R "$RONINUSER":"$RONINUSER" /home/"$RONINUSER"

apt-get update && apt-get upgrade -y

echo "Check if pre-reqs for the ronin-setup.service are fulfilled, if not set default $RONINUSER password for troubleshooting and exit"
[ ! -f /home/"${RONINUSER}"/.config/RoninDojo/info.json ] && (echo "info.json has not been created, halting setup process!"; _set_troubleshooting_passwords; exit 1;)

# DEBUG info
echo "Checking nodejs version : $(node -v)"
echo "Checking npm version : $(npm -v)"    

echo "Enabling the RoninDojo setup service after everything has been validated"
touch /home/ronindojo/.logs/presetup-complete
systemctl enable --now ronin-setup.service
systemctl disable --now ronin-pre.service
