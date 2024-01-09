#!/bin/bash

# Add user ronndojo and add to sudoers
useradd -s /bin/bash -m -c "ronindojo" ronindojo -p "$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c'21')"
echo "ronindojo    ALL=(ALL) ALL" >> /etc/sudoers
# Add user tor
useradd -c "tor" tor

#removes the first user login requirement with monitor and keyboard
rm /root/.not_logged_in_yet 

#echo "set hostname"
#hostname -b "ronindebian"

# RoninDojo part
TMPDIR=/var/tmp
RONINUSER="ronindojo"
# Setting a random password for the users is only necessary before the final application install, makes troubleshooting a new build impossible
PASSWORD="Ronindojo369"
ROOTPASSWORD="Ronindojo369"
FULLNAME="RoninDojo"
TIMEZONE="UTC"
LOCALE="en_US.UTF-8"
NEWHOSTNAME="RoninDojo"
KEYMAP="us"

_create_oem_install() {
    pam-auth-update --package	
    # Setting root password    
    chpasswd <<<"root:$ROOTPASSWORD"

    # Adding user $RONINUSER (split up to avoid non-exec in case of error, groups were invalid before so user didn't get added to any)
    useradd -m -G users "$RONINUSER"
    usermod -s /bin/bash "$RONINUSER"
    for group in sys audio input video lp; do usermod -aG "$group" "$RONINUSER"; done
    chown -R "${RONINUSER}":"${RONINUSER}" /home/"${RONINUSER}"

    # Set User and WorkingDirectory in ronin-setup.service unit file
    sed -i -e "s/User=.*$/User=${RONINUSER}/" \
        -e "s/WorkingDirectory=.*$/WorkingDirectory=\/home\/${RONINUSER}/" /usr/lib/systemd/system/ronin-setup.service

    # Setting full name to $FULLNAME
    chfn -f "$FULLNAME" "$RONINUSER" &>/dev/null

    # Setting password for $RONINUSER
    chpasswd <<<"$RONINUSER:$PASSWORD"

    # Save Linux user credentials for UI access
    [ -f "/home/${RONINUSER}/.config/RoninDojo/info.json" ] && rm -rf "/home/${RONINUSER}/.config/RoninDojo/info.json"
    mkdir -p /home/"${RONINUSER}"/.config/RoninDojo
    cat <<EOF >/home/"${RONINUSER}"/.config/RoninDojo/info.json
{"user":[{"name":"${RONINUSER}","password":"${PASSWORD}"},{"name":"root","password":"${ROOTPASSWORD}"}]}
EOF
    chown -R "${RONINUSER}":"${RONINUSER}" /home/"${RONINUSER}"/.config

    # Setting timezone to $TIMEZONE (does not work on Armbian build)
    timedatectl set-timezone $TIMEZONE &>/dev/null
    timedatectl set-ntp true &>/dev/null

    # Generating $LOCALE locale (does not work on Armbian build)
    sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen &>/dev/null
    locale-gen &>/dev/null
    localectl set-locale $LOCALE &>/dev/null

    if [ -f /etc/sway/inputs/default-keyboard ]; then
        sed -i "s/us/$KEYMAP/" /etc/sway/inputs/default-keyboard

        if [ "$KEYMAP" = "uk" ]; then
            sed -i "s/uk/gb/" /etc/sway/inputs/default-keyboard
        fi
    fi

    # Setting hostname to $NEWHOSTNAME (does not work on Armbian build)
    hostnamectl set-hostname $NEWHOSTNAME &>/dev/null

    # Resizing partition (does not work on Armbian build)
    resize-fs &>/dev/null

    # (does not work on Armbian build)
    loadkeys "$KEYMAP"

    # Configuration complete. Cleaning up
    #rm /root/.bash_profile

    # Avahi setup
    sed -i 's/hosts: .*$/hosts: files mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] dns mdns/' /etc/nsswitch.conf
    sed -i 's/.*host-name=.*$/host-name=ronindojo/' /etc/avahi/avahi-daemon.conf
    if ! systemctl is-enabled --quiet avahi-daemon; then
        systemctl enable --quiet avahi-daemon
    fi

    # sshd setup
    sed -i -e "s/PermitRootLogin yes/#PermitRootLogin prohibit-password/" \
        -e "s/PermitEmptyPasswords yes/#PermitEmptyPasswords no/" /etc/ssh/sshd_config

    # Set sudo timeout to 1 hour
    sed -i '/env_reset/a Defaults\ttimestamp_timeout=60' /etc/sudoers

    # Enable passwordless sudo
    sed -i '/ronindojo/s/ALL) ALL/ALL) NOPASSWD:ALL/' /etc/sudoers # change to no password

    # Not sure what the (security) motivation is for this, commented because home routers often use .local (FEEDBACK)
    # echo -e "domain .local\nnameserver 1.1.1.1\nnameserver 1.0.0.1" >> /etc/resolv.conf
    
    # Setup logs for outputs (does not work on Armbian build since INCLUDE_HOME_DIR is not used)
    mkdir -p /home/ronindojo/.logs
    touch /home/ronindojo/.logs/pre-setup.logs
    touch /home/ronindojo/.logs/setup.logs
    touch /home/ronindojo/.logs/post.logs
    chown -R ronindojo:ronindojo /home/ronindojo/.logs
}

check_and_install() {
    dpkg -s "$1" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "[check_and_install] Installing $1..."
        apt-get install -y "$1"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to install $1."
            exit 1
        fi
    fi
}

_service_checks(){  
    # Not sure if this works on Armbian build, assuming they all get enabled by default in the image
    if ! systemctl is-enabled tor.service; then
        systemctl enable tor.service
    fi

    if ! systemctl is-enabled --quiet avahi-daemon.service; then
        systemctl disable systemd-resolved.service &>/dev/null
        systemctl enable avahi-daemon.service
    fi

    if ! systemctl is-enabled motd.service; then
        systemctl enable motd.service
    fi
    
    if ! systemctl is-enabled ronin-pre.service; then
        systemctl enable ronin-pre.service
    fi

    if ! systemctl is-enabled ronin-setup.service; then
        # Changed: service will get enabled after the ronin-pre.service ran succesfully
	systemctl enable ronin-setup.service
    fi

    if ! systemctl is-enabled ronin-post.service; then
        systemctl enable ronin-post.service
    fi
    systemctl daemon-reload
}

_prep_install(){
    echo "Installing Nodejs"
    apt-get install -y nodejs  
    # Get the major version of the installed Node.js
    NODE_VERSION=$(node -v | grep -oP 'v(\d+)' | grep -oP '\d+')

    # If Node.js version is less than 16, run the curl command
    if [ "$NODE_VERSION" -lt 16 ]; then
        curl -sL https://deb.nodesource.com/setup_16.x | bash -
	apt-get update # not really needed
        apt-get install -y nodejs
    fi    
    if [ "$NODE_VERSION" -gt 16 ]; then
    	apt-get remove -y nodejs
        apt install -y curl gpg gnupg2 software-properties-common apt-transport-https lsb-release ca-certificates
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
	NODE_MAJOR=16
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
	echo "Package: nodejs" | tee -a /etc/apt/preferences.d/preferences
        echo "Pin: origin deb.nodesource.com" | tee -a /etc/apt/preferences.d/preferences
        echo "Pin-Priority: 1001" | tee -a /etc/apt/preferences.d/preferences
        apt update && apt install -y --no-install-recommends nodejs        
    fi
    apt-mark hold nodejs    
    apt-get install -y npm

    echo "Installing Docker on $DISTRO release $RELEASE"
    mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/"$DISTRO"/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO \
    $RELEASE stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
    for pkg in "${packages[@]}"; do check_and_install "$pkg"; done

    echo "Installing docker-compose"
    ARCHICTECTURE="aarch64"
    curl -L https://github.com/docker/compose/releases/download/v2.0.1/docker-compose-linux-"$ARCHITECTURE" -o /usr/bin/docker-compose
    chmod +x /usr/bin/docker-compose

    echo "Installing NPM modules" # Commented: does not work on Armbian build, setup service will install running as user
    # npm i npm@8 -g
    # npm i pnpm@7 -g
    # npm i pm2 -g
}

_ronin_ui_avahi_service() {
    if [ ! -f /etc/avahi/services/http.service ]; then
        tee "/etc/avahi/services/http.service" <<EOF >/dev/null
<?xml version="1.0" standalone='no'?><!--*-nxml-*-->
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<!-- This advertises the RoninDojo vhost -->
<service-group>
 <name replace-wildcards="yes">%h Web Application</name>
  <service>
   <type>_http._tcp</type>
   <port>80</port>
  </service>
</service-group>
EOF
    fi

    sed -i 's/hosts: .*$/hosts: files mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] dns mdns/' /etc/nsswitch.conf

    if ! grep -q "host-name=ronindojo" /etc/avahi/avahi-daemon.conf; then
        sed -i 's/.*host-name=.*$/host-name=ronindojo/' /etc/avahi/avahi-daemon.conf
    fi

    if ! systemctl is-enabled --quiet avahi-daemon; then
        systemctl enable --quiet avahi-daemon
    fi

    return 0
}


_rand_passwd() {
    local _length
    _length="${1:-16}"

    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c"${_length}"
}

# Install Ronin UI. This function is the same we utilize in the RoninDojo repo. Only modifying slightly since this runs during build and not organic setup.
_install_ronin_ui(){

    echo "Installing Ronin-UI"
    roninui_version_file="https://ronindojo.io/downloads/RoninUI/version.json"

    gui_api=$(_rand_passwd 69)
    gui_jwt=$(_rand_passwd 69)

    cd /home/ronindojo || exit

    echo "Installing Ronin-UI : pnpm" # (does not work on Armbian build)
    npm i -g pnpm@7

    test -d /home/ronindojo/Ronin-UI || mkdir /home/ronindojo/Ronin-UI
    cd /home/ronindojo/Ronin-UI || exit

    wget -q "${roninui_version_file}" -O /tmp/version.json 2>/dev/null

    _file=$(jq -r .file /tmp/version.json)
    _shasum=$(jq -r .sha256 /tmp/version.json)

    wget -q https://ronindojo.io/downloads/RoninUI/"$_file" 2>/dev/null

    if ! echo "${_shasum} ${_file}" | sha256sum --check --status; then
        _bad_shasum=$(sha256sum ${_file})
        echo "Ronin UI archive verification failed! Valid sum is ${_shasum}, got ${_bad_shasum} instead..."
    fi
      
    tar xzf "$_file"

    rm "$_file" /tmp/version.json

    # Mark Ronin UI initialized if necessary
    if [ -e "${ronin_ui_init_file}" ]; then
        echo -e "{\"initialized\": true}\n" > ronin-ui.dat
    fi

    # Generate .env file
    echo "JWT_SECRET=$gui_jwt" > .env
    echo "NEXT_TELEMETRY_DISABLED=1" >> .env

    if [ "${roninui_version_staging}" = true ] ; then
        echo -e "VERSION_CHECK=staging\n" >> .env
    fi

    _ronin_ui_avahi_service

    chown -R $RONINUSER:$RONINUSER /home/"$RONINUSER"/Ronin-UI
}

# The debian default was incompatible with our setup. This sets tor to match RoninDojo requirements and removes the debian variants.
_prep_tor(){
	mkdir -p /mnt/usb/tor
	chown -R tor:tor /mnt/usb/tor
	sed -i '$a\User tor\nDataDirectory /mnt/usb/tor' /etc/tor/torrc
    sed -i '$ a\
HiddenServiceDir /mnt/usb/tor/hidden_service_ronin_backend/\
HiddenServiceVersion 3\
HiddenServicePort 80 127.0.0.1:8470\
' /etc/tor/torrc

    cp -Rv /tmp/RoninOS/overlays/RoninOS/example.tor.service /usr/lib/systemd/system/tor.service
    rm -rf /usr/lib/systemd/system/tor@* #remove unnecessary debian installed services
}

_get_systemd_unit_path() {
    # Use systemd's 'systemctl' command to get the system unit path
    local unit_path=$(systemctl show -p UnitPath --value)

    # If UnitPath is not found, fallback to default paths
    if [ -z "$unit_path" ]; then
        echo "/lib/systemd/system:/usr/lib/systemd/system:/etc/systemd/system"
    else
        echo "$unit_path"
    fi
}

# Dynamically check the systemd paths for a service file
_check_service_file() {
    local service_file=$1
    local unit_path
    unit_path=$(_get_systemd_unit_path)

    # Check each path in the unit path for the service file
    IFS=':' read -ra paths <<< "$unit_path"
    for path in "${paths[@]}"; do
        if [ -f "${path}/${service_file}" ]; then
            return 0 # Success, file found
        fi
    done

    return 1 # Failure, file not found
}

# This installs all required packages needed for RoninDojo. Clones the RoninOS repo so it can be copied to appropriate locations. Then runs all the functions defined above.
main(){
    # REPO= "https://code.samourai.io/ronindojo/RoninOS.git"
    REPO="-b fix_armbian_setup https://github.com/JohnnyVicious/RoninOS.git"

    if [ -f /etc/armbian-release ]; then
    	echo "Running on Armbian."
        ARMBIANBUILD=1
    else
        echo "Not running on Armbian."
	ARMBIANBUILD=0
    fi
    
    apt-get update    
    
    # Do NOT clean-up older packages, Armbian build will suggest to use 'apt autoremove', that would break building in ronin-setup.sh
    
    # List of universal packages to install
    packages=(
        man-db git avahi-daemon nginx fail2ban
        net-tools htop unzip wget ufw rsync jq python3 python3-pip
        pipenv gdisk gcc curl apparmor ca-certificates gnupg libevent-dev netcat-openbsd make
	zlib1g-dev libssl-dev make automake autoconf musl-dev coreutils gpg
 	smartmontools gnupg2 software-properties-common apt-transport-https lsb-release
    )

    apt install -y lsb-release
    export DISTRO="$(lsb_release -is | tr '[:upper:]' '[:lower:]')"
    RELEASE="$(lsb_release -cs | tr '[:upper:]' '[:lower:]')"

    case $DISTRO in
        debian)
            case $RELEASE in
                bullseye)
                    echo "Debian Bullseye detected."
      		    release_specific_packages=( tor/bullseye-backports openjdk-11-jdk ) # 0.4.7.x tor 
        	    packages=("${packages[@]}" "${release_specific_packages[@]}")
                    ;;
                bookworm)
                    echo "Debian Bookworm detected."                    
		    release_specific_packages=( tor openjdk-17-jdk )
        	    packages=("${packages[@]}" "${release_specific_packages[@]}")
                    ;;
                *)
                    echo "Unsupported Debian release: $release"
		    exit 1;
                    ;;
            esac
            ;;
        ubuntu)
            case $RELEASE in
                jammy)
                    echo "Ubuntu Jammy (22.04) detected."
		    release_specific_packages=( tor openjdk-11-jdk )
        	    packages=("${packages[@]}" "${release_specific_packages[@]}")
                    ;;
                lunar)
                    echo "Ubuntu Lunar (23.04) detected."
		    release_specific_packages=( tor openjdk-11-jdk )
        	    packages=("${packages[@]}" "${release_specific_packages[@]}")
                   ;;
                *)
                    echo "Unsupported Ubuntu release: $release"
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "This script is intended for Ubuntu or Debian. Detected: $DISTRO $RELEASE"
            exit 1
            ;;
    esac

    # Check and install each package
    for pkg in "${packages[@]}"; do check_and_install "$pkg"; done

    # clone the original RoninOS    
    git clone $(echo "$REPO") /tmp/RoninOS
    cp -Rv /tmp/RoninOS/overlays/RoninOS/usr/* /usr/
    cp -Rv /tmp/RoninOS/overlays/RoninOS/etc/* /etc/  

    # Check if the ronin-setup.service exists
    if _check_service_file "ronin-setup.service"; then    
        echo "Setup service is PRESENT! Keep going!"
        _create_oem_install
        _prep_install
        _prep_tor
        # group pm2 does not exist (Armbian build)
	# usermod -aG pm2 ronindojo        
	mkdir -p /usr/share/nginx/logs
        rm -rf /etc/nginx/sites-enabled/default        
	_install_ronin_ui # TODO: unsure if this is usefull during build phase, gets executed by the setup service anyways
        usermod -aG docker $RONINUSER # sudoless docker command access
	chmod +x /usr/local/sbin/*.sh
        systemctl enable oem-boot.service
	_service_checks # Armbian confirmed
 	apt-get update && apt-get upgrade -y
  	chown -R "${RONINUSER}":"${RONINUSER}" /home/"${RONINUSER}"
        echo "Setup is complete"
    else
        echo "ronin-setup.service is missing, something went wrong!"
    	exit 1
    fi
}

# Run main setup function.
main
