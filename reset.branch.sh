# place this file in an empty directory
# run "chmod +x reset.branch.sh"
# place the armbian image in the same directory (name must start with "Armbian_23")
# run "./reset.branch.sh"
# your image file is now edited

set -ex
sectorsize=$(fdisk -l Armbian_23* | head -n 2 | tail -n 1 | awk '{print $8}')
startsector=$(fdisk -l Armbian_23* | tail -n 1 | awk '{print $2}')
startbyte=$(($sectorsize*$startsector))
mkdir ronin_temp_mount
mount -o loop,offset=$startbyte Armbian_23* ./ronin_temp_mount
sed -i 's|^.*git clone.*$|git clone -b master https://code.samourai.io/ronindojo/RoninDojo /home/ronindojo/RoninDojo|' ronin_temp_mount/usr/local/sbin/ronin-setup.sh
umount ronin_temp_mount
rmdir ronin_temp_mount