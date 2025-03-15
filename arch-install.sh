#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Prompt user for hostname, username, passwords, and disk
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -sp "Enter user password: " USER_PASSWORD && echo
read -sp "Enter root password: " ROOT_PASSWORD && echo
lsblk
echo
read -p "Enter Disk (e.g., /dev/sda or /dev/nvme0n1): " DISK

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

# Detect UEFI or BIOS
if [ -d "/sys/firmware/efi" ]; then
  UEFI=true
else
  UEFI=false
fi

# Ensure reflector and required tools are installed
pacman -Sy --noconfirm reflector rsync curl python unzip || { echo "Failed to install required packages. Exiting."; exit 1; }

# Update mirrorlist using reflector
COUNTRY=$(curl -4 ifconfig.co/country-iso)
echo -ne "Setting up mirrors for faster downloads in $COUNTRY...\n"
reflector --verbose -c "$COUNTRY" -l 5 --sort rate --save /etc/pacman.d/mirrorlist
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf || exit 1

# Partition and format the disk
echo "Partitioning $DISK..."
sgdisk -Z "$DISK" || exit 1  # Wipe existing partitions

if [ "$UEFI" = true ]; then
  sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System Partition" "$DISK" || exit 1
  sgdisk -n 2:0:0 -t 2:8300 -c 2:"Arch Linux" "$DISK" || exit 1
  mkfs.fat -F32 "${DISK}p1" || exit 1
else
  parted "$DISK" --script mklabel msdos
  parted "$DISK" --script mkpart primary ext4 1MiB 100%
  parted "$DISK" --script set 1 boot on
fi

# Dynamic partition detection
if [[ "$UEFI" = true ]]; then
    EFI_PART=$(lsblk -lnpo NAME,PARTTYPE "$DISK" | awk '$2 == "0xef00" {print $1}')
    ROOT_PART=$(lsblk -lnpo NAME,PARTTYPE "$DISK" | awk '$2 == "0x8300" {print $1}')
else
    ROOT_PART=$(lsblk -lnpo NAME "$DISK" | tail -n 1)  # Assume last partition is root
fi

# Fallback for partition names
if [[ -z "$ROOT_PART" || ( "$UEFI" = true && -z "$EFI_PART" ) ]]; then
    if [[ "$DISK" =~ "nvme" ]]; then
        ROOT_PART="${DISK}p2"
        EFI_PART="${DISK}p1"
    else
        ROOT_PART="${DISK}2"
        EFI_PART="${DISK}1"
    fi
fi

# Verify partitions exist
if [[ ! -b "$ROOT_PART" || ( "$UEFI" = true && ! -b "$EFI_PART" ) ]]; then
    echo "Error: Detected partitions do not exist!"
    lsblk
    exit 1
fi

# Format and mount the partitions
if [ "$UEFI" = true ]; then
  mkfs.btrfs "$ROOT_PART" -f || exit 1
  mount "$ROOT_PART" /mnt || exit 1
  for subvol in @ @home @log @pkg @snapshots; do
    btrfs subvolume create "/mnt/$subvol" || exit 1
  done
  umount /mnt || exit 1
  mount -o subvol=@,compress=zstd "$ROOT_PART" /mnt || exit 1
  mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots} || exit 1
  mount -o subvol=@home,compress=zstd "$ROOT_PART" /mnt/home || exit 1
  mount -o subvol=@log,compress=zstd "$ROOT_PART" /mnt/var/log || exit 1
  mount -o subvol=@pkg,compress=zstd "$ROOT_PART" /mnt/var/cache/pacman/pkg || exit 1
  mount -o subvol=@snapshots,compress=zstd "$ROOT_PART" /mnt/.snapshots || exit 1
  mount "$EFI_PART" /mnt/boot || exit 1
else
  mkfs.ext4 "$ROOT_PART"
  mount "$ROOT_PART" /mnt || exit 1
fi

# Install base system
pacstrap /mnt base base-devel linux linux-firmware nano git wget reflector rsync curl python unzip xorg xorg-server xorg-xinit xorg-xrandr xorg-xsetroot btrfs-progs grub efibootmgr \
  wpa_supplicant wireless_tools networkmanager modemmanager mobile-broadband-provider-info \
  usb_modeswitch rp-pppoe nm-connection-editor network-manager-applet || exit 1

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab || exit 1

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF
COUNTRY=\$(curl -4 ifconfig.co/country-iso)
reflector --country \$COUNTRY --latest 5 --age 2 --fastest 5 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf || exit 1

# Configure system
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Configure GRUB
if [ "$UEFI" = true ]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc "$DISK"
fi
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
echo "Setup complete! Press Enter to reboot or Ctrl+C to cancel."
read
reboot
