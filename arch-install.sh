#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Prompt the user for hostname, username and passwords
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -sp "Enter user password: " USER_PASSWORD
echo
read -sp "Enter root password: " ROOT_PASSWORD
echo
read "Enter Disk Eg. /dev/sda: " DISK
echo
# Validate user input
if [[ -z "$HOSTNAME" || -z "$USERNAME" || -z "$USER_PASSWORD" || -z "$ROOT_PASSWORD" ]]; then
    echo "All fields are required"
    exit 1
fi

# Connect to the internet and configure the network
pacman -Sy reflector || exit
reflector --country India --protocol https --age 12 --sort rate --save /etc/pacman.d/mirrorlist || exit
pacman -Syy || exit

# Enable parallel downloading in pacman.conf
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf || exit

# Partition and format the disk


echo "Deleting partitions on $disk..."
sudo fdisk $disk <<EOF
p  # Display existing partitions (optional)
d  # Delete partition
w  # Write changes
EOF

echo "Partitions on $disk deleted."



sgdisk -Z /dev/sda || exit
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" /dev/sda || exit
sgdisk -n 2:0:0 -t 2:8300 -c 2:"Arch Linux" /dev/sda || exit
mkfs.fat -F32 /dev/sda1 || exit
mkfs.btrfs /dev/sda2 || exit

# Mount the Btrfs root partition and create and mount subvolumes
mount /dev/sda2 /mnt || exit
btrfs subvolume create /mnt/@ || exit
btrfs subvolume create /mnt/@home || exit
btrfs subvolume create /mnt/@log || exit
btrfs subvolume create /mnt/@pkg || exit
btrfs subvolume create /mnt/@snapshots || exit
umount /mnt || exit
mount -o subvol=@,compress=zstd /dev/sda2 /mnt || exit
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots} || exit
mount -o subvol=@home,compress=zstd /dev/sda2 /mnt/home || exit
mount -o subvol=@log,compress=zstd /dev/sda2 /mnt/var/log || exit
mount -o subvol=@pkg,compress=zstd /dev/sda2 /mnt/var/cache/pacman/pkg || exit
mount -o subvol=@snapshots,compress=zstd /dev/sda2 /mnt/.snapshots || exit
mount /dev/sda1 /mnt/boot || exit

# Install the base system and KDE packages
pacstrap /mnt base base-devel linux linux-firmware nano btrfs-progs grub efibootmgr wpa_supplicant wireless_tools networkmanager modemmanager mobile-broadband-provider-info usb_modeswitch rp-pppoe nm-connection-editor network-manager-applet || exit

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab || exit

# Chroot into the new system and perform system configurations
arch-chroot /mnt /bin/bash <<EOF || exit
# Set hostname
echo $HOSTNAME > /etc/hostname || exit

# Set timezone
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime || exit

# Set locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen || exit
locale-gen || exit
echo "LANG=en_US.UTF-8" > /etc/locale.conf || exit

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB || exit
grub-mkconfig -o /boot/grub/grub.cfg || exit

# Set user
echo "root:$ROOT_PASSWORD" | chpasswd || exit

# Create non-root user and add to wheel group
useradd -m -G wheel $USERNAME || exit
echo "$USERNAME:$USER_PASSWORD" | chpasswd || exit
echo "$USERNAME ALL=(ALL) ALL" |  tee -a /etc/sudoers
#Configure network
systemctl enable NetworkManager.service || exit
systemctl disable dhcpcd.service || exit
systemctl enable wpa_supplicant.service || exit
systemctl start NetworkManager.service || exit
# Exit chroot 
exit
EOF

#reboot into the new system
echo "The system will reboot in 10 seconds..."
sleep 10
umount -R /mnt || exit
reboot
