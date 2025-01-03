#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Prompt the user for hostname, username, passwords, and disk
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -sp "Enter user password: " USER_PASSWORD
echo
read -sp "Enter root password: " ROOT_PASSWORD
echo
read -p "Enter Disk (e.g., /dev/sda): " DISK

# Validate user input
if [[ -z "$HOSTNAME" || -z "$USERNAME" || -z "$USER_PASSWORD" || -z "$ROOT_PASSWORD" || -z "$DISK" ]]; then
  echo "All fields are required"
  exit 1
fi

# Validate disk existence
if [ ! -b "$DISK" ]; then
  echo "Invalid disk: $DISK"
  exit 1
fi

# Ensure reflector is installed and configure pacman
pacman -S --noconfirm reflector || { echo "Failed to install reflector. Exiting."; exit 1; }

# Update mirrorlist using reflector
reflector --country 'India' --latest 5 --age 2 --fastest 5 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || { echo "Failed to update mirrors."; exit 1; }
pacman -Syy --noconfirm || exit 1

# Enable parallel downloads in pacman.conf
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf || exit 1

# Partition and format the disk
echo "Partitioning $DISK..."
sgdisk -Z "$DISK" || exit 1
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" "$DISK" || exit 1
sgdisk -n 2:0:0 -t 2:8300 -c 2:"Arch Linux" "$DISK" || exit 1
mkfs.fat -F32 "${DISK}1" || exit 1
mkfs.btrfs "${DISK}2" || exit 1

# Mount and create Btrfs subvolumes
mount "${DISK}2" /mnt || exit 1
for subvol in @ @home @log @pkg @snapshots; do
  btrfs subvolume create "/mnt/$subvol" || exit 1
done
umount /mnt || exit 1

# Mount subvolumes
mount -o subvol=@,compress=zstd "${DISK}2" /mnt || exit 1
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots} || exit 1
mount -o subvol=@home,compress=zstd "${DISK}2" /mnt/home || exit 1
mount -o subvol=@log,compress=zstd "${DISK}2" /mnt/var/log || exit 1
mount -o subvol=@pkg,compress=zstd "${DISK}2" /mnt/var/cache/pacman/pkg || exit 1
mount -o subvol=@snapshots,compress=zstd "${DISK}2" /mnt/.snapshots || exit 1
mount "${DISK}1" /mnt/boot || exit 1

# Install base system and KDE packages
pacstrap /mnt base base-devel linux linux-firmware nano btrfs-progs grub efibootmgr \
  wpa_supplicant wireless_tools networkmanager modemmanager mobile-broadband-provider-info \
  usb_modeswitch rp-pppoe nm-connection-editor network-manager-applet || exit 1

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab || exit 1

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF
# Configure system
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Set root and user passwords
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "$USERNAME ALL=(ALL) ALL" >> /etc/sudoers

# Enable network services
systemctl enable NetworkManager.service
EOF

# Cleanup and reboot
umount -R /mnt || exit 1
echo "Setup complete. Rebooting in 10 seconds..."
sleep 10
reboot
