# 🏴‍☠️ Arch Installer

A minimal Arch Linux installer script designed to automate the installation process with `archinstall`.

<img src="https://upload.wikimedia.org/wikipedia/commons/thumb/1/13/Arch_Linux_%22Crystal%22_icon.svg/640px-Arch_Linux_%22Crystal%22_icon.svg.png" width="128" height="128" alt="Arch Linux"/>

## 🚀 Features
- **⚡ Fully Automated Installation**: Installs Arch Linux with minimal user input.
- **🛠️ Uses `archinstall`**: Ensures a smooth and streamlined setup.
- **💡 Customizable**: Modify scripts to fit your specific needs.

## 📥 Installation

### Prerequisites
- 🖥️ A USB drive (at least 2GB recommended)
- 💾 A system capable of booting from USB

### Steps

1. 🔗 Download the latest Arch Linux ISO from [archlinux.org](https://archlinux.org/download/).
2. 📀 Create a bootable USB using `dd` or a tool like Balena Etcher:
   ```bash
   sudo dd if=archlinux.iso of=/dev/sdX bs=4M status=progress && sync
   ```
   (Replace `/dev/sdX` with your USB drive.)

3. 🏁 Boot from the USB.

4. 🌐 Connect to WiFi (if using a wireless connection):
   To connect to WiFi, use:
   ```bash
   iwctl
   ```
   Then, inside `iwctl`:
   ```bash
   station wlan0 scan
   station wlan0 get-networks
   station wlan0 connect <network_name>
   ```
   Replace `<network_name>` with your WiFi SSID and enter the password when prompted.

5. 📦 Install necessary packages and run the installer script:
   ```bash
   pacman -Sy pacman-contrib git
   git clone https://github.com/Jeffrey2081/arch-install.git
   cd arch-install
   ./install.sh
   ```
## 🤝 Contributing
Pull requests and improvements are welcome! Feel free to fork and customize.

## 🔗 Connect with Me
[![Instagram](https://img.shields.io/badge/Instagram-%23E4405F.svg?style=for-the-badge&logo=instagram&logoColor=white)](https://www.instagram.com/jeffrey__2081/)

---

⚡ Powered by Arch Linux 🚀
