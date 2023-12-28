HOSTNAME="RoninDojo"
USER="ronindojo"
PASSWORD="Ronindojo6669999" # DEBUG purpose only
#PASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c'21')"
ROOTPASSWORD="Ronindojo6669999" ## DEBUG purpose only
#ROOTPASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c'21')"

hostnamectl hostname $HOSTNAME
echo "$(ls -l /home)"
chown -R "$USER":"$USER" /home/"$USER"
mkdir -p /home/"${USER}"/.config/RoninDojo
cat <<EOF >/home/"${USER}"/.config/RoninDojo/info.json
{"user":[{"name":"${USER}","password":"${PASSWORD}"},{"name":"root","password":"${ROOTPASSWORD}"}]}
EOF
[! -f /home/"${USER}"/.config/RoninDojo/info.json] && echo "info.json has not been created!" && exit
systemctl enable --now ronin-setup.service
