# place this file in an empty directory
# run "chmod +x reset.branch.sh"
# place the armbian image in the same directory (name must start with "Armbian")
# run "./reset.branch.sh"
# your image file is now edited

set -ex
sudo echo "starting"
sectorsize=$(sudo fdisk -l Armbian* | head -n 2 | tail -n 1 | awk '{print $8}')
startsector=$(sudo fdisk -l Armbian* | tail -n 1 | awk '{print $2}')
startbyte=$(($sectorsize*$startsector))
mkdir ronin_temp_mount
sudo mount -o loop,offset=$startbyte Armbian* ./ronin_temp_mount
sudo sed -i 's|^.*git clone.*$|git clone -b master https://code.samourai.io/ronindojo/RoninDojo /home/ronindojo/RoninDojo|' ronin_temp_mount/usr/local/sbin/ronin-setup.sh
sudo umount ronin_temp_mount
rmdir ronin_temp_mount
echo "done"
