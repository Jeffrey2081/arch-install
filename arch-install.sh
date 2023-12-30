#!/bin/bash

# Prompt the user for hostname, username and passwords
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -sp "Enter user password: " USER_PASSWORD
echo
read -sp "Enter root password: " ROOT_PASSWORD
echo

# Connect to the internet and configure the network
pacman -Sy reflector
reflector --country India --protocol https --age 12 --sort rate --save /etc/pacman.d/mirrorlist
pacman -Syy

# Enable parallel downloading in pacman.conf
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

# Partition and format the disk
sgdisk -Z /dev/sda
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" /dev/sda
sgdisk -n 2:0:0 -t 2:8300 -c 2:"Arch Linux" /dev/sda
mkfs.fat -F32 /dev/sda1
mkfs.btrfs /dev/sda2

# Mount the Btrfs root partition and create and mount subvolumes
mount /dev/sda2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@snapshots
umount /mnt
mount -o subvol=@,compress=zstd /dev/sda2 /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o subvol=@home,compress=zstd /dev/sda2 /mnt/home
mount -o subvol=@log,compress=zstd /dev/sda2 /mnt/var/log
mount -o subvol=@pkg,compress=zstd /dev/sda2 /mnt/var/cache/pacman/pkg
mount -o subvol=@snapshots,compress=zstd /dev/sda2 /mnt/.snapshots
mount /dev/sda1 /mnt/boot

# Install the base system and KDE packages
pacstrap /mnt base base-devel linux linux-firmware nano btrfs-progs grub efibootmgr

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system and perform system configurations
arch-chroot /mnt /bin/bash <<EOF
# Set hostname
echo $HOSTNAME > /etc/hostname

# Set timezone
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime

# Set locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable and start SDDM
systemctl enable sddm.service
systemctl start sddm.service

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create non-root user and add to wheel group
useradd -m -G wheel $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Exit chroot 
exit
EOF

#reboot into the new system
sleep 10
umount -R /mnt
