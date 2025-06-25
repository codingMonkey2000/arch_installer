#!/bin/bash

# ====
# FIXED Arch Linux Installation Script
# ====
# 
# This script provides an interactive, comprehensive Arch Linux installation
# with hardware-specific optimizations, security hardening, and complete
# development environment setup.
#
# FIXES APPLIED:
# - Added missing main function call (primary cause of hanging)
# - Fixed all read commands to use -r flag (prevents backslash mangling)
# - Added proper secure boot support with systemd-boot instead of GRUB
# - Enhanced hardware support for AMD Ryzen 9950X and RTX 5090
# - Improved MediaTek WiFi handling with proper firmware
# - Fixed variable quoting issues
# - Added comprehensive error handling
# - Optimized for Norwegian keyboard layout
#
# Target Hardware:
# - AMD Ryzen 9 9950X
# - ASRock X670E Taichi
# - NVIDIA RTX 5090
# - MediaTek MT7927 WiFi (with workaround)
# - Norwegian keyboard layout
#
# Features:
# - Interactive configuration prompts
# - Complete disk wipe and partitioning
# - Secure Boot with systemd-boot and sbctl
# - Hardware-specific driver installation
# - Comprehensive development tools
# - Security hardening
# - Error handling and recovery
#
# Author: Fixed version for Arch Linux 2025
# Date: June 25, 2025
# ====

set -euo pipefail

# ====
# GLOBAL VARIABLES AND CONFIGURATION
# ====

# Script metadata
readonly SCRIPT_VERSION="2.1.0-FIXED"
readonly SCRIPT_NAME="Arch Linux Fixed Installer"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# User configuration variables (will be set by prompts)
USERNAME=""
HOSTNAME=""
ROOT_PASSWORD=""
USER_PASSWORD=""
SELECTED_DISK=""
TIMEZONE=""
ENABLE_SECURE_BOOT="y"
INSTALL_DEVELOPMENT_TOOLS="y"

# System configuration
readonly KEYMAP="no"  # Norwegian keyboard
readonly LOCALE="en_US.UTF-8"
readonly DEFAULT_SHELL="/bin/bash"

# Package arrays
readonly BASE_PACKAGES=(
    "base" "base-devel" "linux" "linux-lts" "linux-firmware"
    "amd-ucode" "systemd-boot" "efibootmgr" "networkmanager"
    "sudo" "nano" "vim" "git" "wget" "curl" "reflector"
)

readonly DEVELOPMENT_PACKAGES=(
    # Core development tools
    "git" "base-devel" "cmake" "make" "gcc" "clang" "gdb"
    "valgrind" "strace" "ltrace" "perf"
    
    # Programming languages
    "python" "python-pip" "python-virtualenv" "python-pipenv"
    "nodejs" "npm" "yarn" "go" "rust" "rustup"
    "jdk-openjdk" "openjdk-doc" "maven" "gradle"
    "ruby" "php" "lua" "perl"
    
    # Databases
    "postgresql" "postgresql-libs" "mariadb" "sqlite"
    "redis"
    
    # Containers and virtualization
    "docker" "docker-compose" "podman" "qemu-full" "virt-manager"
    
    # Version control and collaboration
    "git-lfs" "mercurial" "subversion"
    
    # Build systems and package managers
    "meson" "ninja" "autoconf" "automake" "libtool"
    "pkgconf" "flatpak"
)

readonly DESKTOP_PACKAGES=(
    # KDE Plasma desktop environment
    "plasma-meta" "plasma-wayland-session" "kde-applications-meta"
    "sddm" "sddm-kcm" "xorg-xwayland"
    
    # Display and graphics
    "xorg-server" "xorg-apps" "mesa" "vulkan-radeon"
    "nvidia-open" "nvidia-utils" "nvidia-settings" "lib32-nvidia-utils"
    
    # Audio
    "pipewire" "pipewire-alsa" "pipewire-pulse" "pipewire-jack"
    "wireplumber" "pavucontrol" "alsa-utils"
    
    # Fonts
    "ttf-dejavu" "ttf-liberation" "noto-fonts" "noto-fonts-emoji"
    "ttf-roboto" "ttf-opensans" "adobe-source-code-pro-fonts"
)

readonly APPLICATION_PACKAGES=(
    # Web browsers
    "firefox" "chromium"
    
    # Communication
    "thunderbird" "telegram-desktop"
    
    # Office and productivity
    "libreoffice-fresh" "okular" "spectacle" "dolphin"
    "kate" "kwrite" "kcalc" "ark" "filelight"
    
    # Media
    "mpv" "vlc" "gimp" "inkscape" "kdenlive" "audacity"
    "obs-studio"
    
    # Development IDEs and editors
    "neovim" "emacs"
    
    # System utilities
    "htop" "btop" "neofetch" "tree" "unzip" "p7zip"
    "rsync" "tmux" "screen" "zsh" "fish"
    "flameshot" "redshift"
    
    # Modern CLI tools
    "exa" "bat" "ripgrep" "fd" "fzf" "zoxide" "starship"
    
    # Gaming
    "steam" "lutris" "wine" "winetricks" "gamemode"
    "mangohud"
    
    # Security and privacy
    "ufw" "fail2ban" "clamav" "rkhunter"
    "keepassxc"
    
    # Network tools
    "nmap" "wireshark-qt" "tcpdump" "iperf3" "mtr"
    "openvpn" "wireguard-tools"
)

# ====
# UTILITY FUNCTIONS
# ====

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${PURPLE}=== $1 ===${NC}\n"
}

# Error handling
error_exit() {
    print_error "$1"
    print_error "Installation failed. Check the logs above for details."
    exit 1
}

# Cleanup function
cleanup() {
    if mountpoint -q /mnt 2>/dev/null; then
        print_status "Cleaning up mounts..."
        umount -R /mnt 2>/dev/null || true
    fi
}

# Set up error handling
trap cleanup EXIT
trap 'error_exit "Script interrupted by user"' INT TERM

# Confirmation prompt - FIXED: Added -r flag to read
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -r -p "$prompt [Y/n]: " response
            response=${response:-y}
        else
            read -r -p "$prompt [y/N]: " response
            response=${response:-n}
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Secure password input - FIXED: Added -r flag to read
read_password() {
    local prompt="$1"
    local password
    local password_confirm
    
    while true; do
        echo -n "$prompt: "
        read -r -s password
        echo
        echo -n "Confirm password: "
        read -r -s password_confirm
        echo
        
        if [[ "$password" == "$password_confirm" ]]; then
            if [[ ${#password} -ge 8 ]]; then
                echo "$password"
                return 0
            else
                print_error "Password must be at least 8 characters long."
            fi
        else
            print_error "Passwords do not match."
        fi
    done
}

# ====
# SYSTEM VALIDATION FUNCTIONS
# ====

check_uefi_boot() {
    print_status "Checking UEFI boot mode..."
    if [[ ! -d /sys/firmware/efi ]]; then
        error_exit "System is not booted in UEFI mode. Please enable UEFI in BIOS settings."
    fi
    print_success "UEFI boot mode confirmed"
}

check_internet_connection() {
    print_status "Checking internet connectivity..."
    if ! ping -c 3 archlinux.org &>/dev/null; then
        error_exit "No internet connection. Please configure network and try again."
    fi
    print_success "Internet connection confirmed"
}

update_system_clock() {
    print_status "Updating system clock..."
    timedatectl set-ntp true
    print_success "System clock synchronized"
}

# ====
# USER INPUT FUNCTIONS - FIXED: Added -r flag to all read commands
# ====

get_user_input() {
    print_header "System Configuration"
    
    # Username
    while [[ -z "$USERNAME" ]]; do
        read -r -p "Enter username: " USERNAME
        if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            print_error "Invalid username. Use lowercase letters, numbers, underscore, and hyphen only."
            USERNAME=""
        fi
    done
    
    # Hostname - FIXED: This was the main hanging point
    while [[ -z "$HOSTNAME" ]]; do
        read -r -p "Enter hostname: " HOSTNAME
        if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
            print_error "Invalid hostname. Use letters, numbers, and hyphens only."
            HOSTNAME=""
        fi
    done
    
    # Passwords
    ROOT_PASSWORD=$(read_password "Enter root password")
    USER_PASSWORD=$(read_password "Enter user password")
    
    # Timezone
    print_status "Available timezones:"
    timedatectl list-timezones | grep -E "(Europe|America|Asia)" | head -20
    read -r -p "Enter timezone (e.g., Europe/Oslo): " TIMEZONE
    if ! timedatectl list-timezones | grep -q "^$TIMEZONE$"; then
        print_warning "Invalid timezone. Using Europe/Oslo as default."
        TIMEZONE="Europe/Oslo"
    fi
    
    # Optional features
    if confirm "Enable Secure Boot setup?" "y"; then
        ENABLE_SECURE_BOOT="y"
    else
        ENABLE_SECURE_BOOT="n"
    fi
    
    if confirm "Install complete development environment?" "y"; then
        INSTALL_DEVELOPMENT_TOOLS="y"
    else
        INSTALL_DEVELOPMENT_TOOLS="n"
    fi
}

select_disk() {
    print_header "Disk Selection"
    
    print_warning "WARNING: The selected disk will be completely wiped!"
    echo
    
    # List available disks
    print_status "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL | grep -E "(nvme|sd[a-z])"
    echo
    
    while [[ -z "$SELECTED_DISK" ]]; do
        read -r -p "Enter disk to install to (e.g., /dev/nvme0n1 or /dev/sda): " SELECTED_DISK
        
        if [[ ! -b "$SELECTED_DISK" ]]; then
            print_error "Invalid disk selection."
            SELECTED_DISK=""
            continue
        fi
        
        # Show disk info
        print_status "Selected disk information:"
        lsblk "$SELECTED_DISK"
        echo
        
        if confirm "This will COMPLETELY WIPE $SELECTED_DISK. Continue?" "n"; then
            break
        else
            SELECTED_DISK=""
        fi
    done
}

# ====
# DISK MANAGEMENT FUNCTIONS
# ====

prepare_disk() {
    print_header "Preparing Disk"
    
    print_status "Wiping disk $SELECTED_DISK..."
    
    # Unmount any existing partitions
    umount -R /mnt 2>/dev/null || true
    
    # Wipe disk signatures
    wipefs -af "$SELECTED_DISK"
    
    # Create new GPT partition table
    sgdisk -Z "$SELECTED_DISK"
    sgdisk -o "$SELECTED_DISK"
    
    # Create partitions
    print_status "Creating partitions..."
    
    # EFI System Partition (1GB)
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI System" "$SELECTED_DISK"
    
    # Root partition (remaining space)
    sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux filesystem" "$SELECTED_DISK"
    
    # Inform kernel of partition changes
    partprobe "$SELECTED_DISK"
    sleep 2
    
    print_success "Partitions created successfully"
}

format_partitions() {
    print_header "Formatting Partitions"
    
    # Determine partition naming scheme
    if [[ "$SELECTED_DISK" =~ nvme ]]; then
        local efi_partition="${SELECTED_DISK}p1"
        local root_partition="${SELECTED_DISK}p2"
    else
        local efi_partition="${SELECTED_DISK}1"
        local root_partition="${SELECTED_DISK}2"
    fi
    
    print_status "Formatting EFI partition..."
    mkfs.fat -F32 -n "EFI" "$efi_partition"
    
    print_status "Formatting root partition..."
    mkfs.ext4 -L "ROOT" "$root_partition"
    
    print_success "Partitions formatted successfully"
}

mount_partitions() {
    print_header "Mounting Partitions"
    
    # Determine partition naming scheme
    if [[ "$SELECTED_DISK" =~ nvme ]]; then
        local efi_partition="${SELECTED_DISK}p1"
        local root_partition="${SELECTED_DISK}p2"
    else
        local efi_partition="${SELECTED_DISK}1"
        local root_partition="${SELECTED_DISK}2"
    fi
    
    print_status "Mounting root partition..."
    mount "$root_partition" /mnt
    
    print_status "Creating and mounting EFI directory..."
    mkdir -p /mnt/boot
    mount "$efi_partition" /mnt/boot
    
    print_success "Partitions mounted successfully"
}

# ====
# BASE SYSTEM INSTALLATION
# ====

install_base_system() {
    print_header "Installing Base System"
    
    print_status "Updating package databases..."
    pacman -Sy
    
    print_status "Installing base packages..."
    pacstrap /mnt "${BASE_PACKAGES[@]}"
    
    print_status "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
    
    print_success "Base system installed successfully"
}

# FIXED: Improved system configuration with systemd-boot instead of GRUB
configure_system() {
    print_header "Configuring System"
    
    # Create configuration script to run in chroot
    cat > /mnt/configure_system.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Set timezone
ln -sf /usr/share/zoneinfo/$1 /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "nb_NO.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set keyboard layout
echo "KEYMAP=no" > /etc/vconsole.conf

# Set hostname
echo "$2" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $2.localdomain $2
HOSTS_EOF

# Configure mkinitcpio for NVIDIA and AMD
sed -i 's/MODULES=()/MODULES=(amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf

# Generate initramfs
mkinitcpio -P

# Install and configure systemd-boot (FIXED: Using systemd-boot instead of GRUB)
bootctl install

# Create systemd-boot entries
mkdir -p /boot/loader/entries

cat > /boot/loader/loader.conf << LOADER_EOF
default arch.conf
timeout 3
console-mode max
editor no
LOADER_EOF

cat > /boot/loader/entries/arch.conf << ARCH_ENTRY_EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=LABEL=ROOT rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1
ARCH_ENTRY_EOF

cat > /boot/loader/entries/arch-lts.conf << ARCH_LTS_ENTRY_EOF
title   Arch Linux LTS
linux   /vmlinuz-linux-lts
initrd  /amd-ucode.img
initrd  /initramfs-linux-lts.img
options root=LABEL=ROOT rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1
ARCH_LTS_ENTRY_EOF

# Enable NetworkManager
systemctl enable NetworkManager

# Set root password
echo "root:$3" | chpasswd

# Create user
useradd -m -G wheel,audio,video,optical,storage,docker -s /bin/bash "$4"
echo "$4:$5" | chpasswd

# Configure sudo
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Create pacman hook for NVIDIA
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/nvidia.hook << NVIDIA_HOOK_EOF
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia-open
Target=linux
Target=linux-lts

[Action]
Description=Update initramfs for NVIDIA
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'
NVIDIA_HOOK_EOF

# Create systemd-boot update hook
cat > /etc/pacman.d/hooks/95-systemd-boot.hook << SYSTEMD_BOOT_HOOK_EOF
[Trigger]
Type=Package
Operation=Upgrade
Target=systemd

[Action]
Description=Gracefully upgrading systemd-boot...
When=PostTransaction
Exec=/usr/bin/systemctl restart systemd-boot-update.service
SYSTEMD_BOOT_HOOK_EOF

EOF

    # Make script executable and run it
    chmod +x /mnt/configure_system.sh
    arch-chroot /mnt ./configure_system.sh "$TIMEZONE" "$HOSTNAME" "$ROOT_PASSWORD" "$USERNAME" "$USER_PASSWORD"
    
    # Remove the script
    rm /mnt/configure_system.sh
    
    print_success "System configuration completed"
}

# ====
# HARDWARE-SPECIFIC CONFIGURATION - ENHANCED for RTX 5090 and Ryzen 9950X
# ====

install_nvidia_drivers() {
    print_header "Installing NVIDIA RTX 5090 Drivers"
    
    print_status "Installing NVIDIA open-source drivers (recommended for RTX 5090)..."
    arch-chroot /mnt pacman -S --noconfirm nvidia-open nvidia-utils nvidia-settings lib32-nvidia-utils
    
    print_status "Configuring NVIDIA settings..."
    
    # Create NVIDIA configuration
    cat > /mnt/etc/X11/xorg.conf.d/20-nvidia.conf << 'EOF'
Section "Device"
    Identifier "NVIDIA Card"
    Driver "nvidia"
    VendorName "NVIDIA Corporation"
    Option "NoLogo" "true"
    Option "UseEDID" "false"
    Option "ConnectedMonitor" "DFP"
    Option "TripleBuffer" "true"
    Option "UseEvents" "false"
EndSection
EOF

    # Configure NVIDIA power management
    cat > /mnt/etc/modprobe.d/nvidia.conf << 'EOF'
# Enable NVIDIA power management
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

    print_success "NVIDIA drivers installed and configured"
}

# ENHANCED: Better MediaTek WiFi support
configure_mediatek_workaround() {
    print_header "MediaTek MT7927 Wireless Configuration"
    
    print_status "Installing MediaTek firmware and drivers..."
    
    # Install wireless tools and firmware
    arch-chroot /mnt pacman -S --noconfirm wireless_tools wpa_supplicant iw linux-firmware
    
    # Try to install MediaTek firmware if available
    if arch-chroot /mnt pacman -S --noconfirm linux-firmware-mediatek 2>/dev/null; then
        print_success "MediaTek firmware installed"
    else
        print_warning "MediaTek firmware package not available"
    fi
    
    # Create information file for user - FIXED: Proper quoting
    cat > "/mnt/home/$USERNAME/WIRELESS_INFO.txt" << 'EOF'
MEDIATEK MT7927 WIRELESS CARD COMPATIBILITY NOTICE
====

Your system contains a MediaTek MT7927 wireless card. Support status:

CURRENT STATUS:
- Basic MediaTek firmware has been installed
- The mt76 driver may provide limited support
- Full functionality is not guaranteed

SOLUTIONS IF WIFI DOESN'T WORK:
1. Replace the M.2 wireless card with a supported model:
   - Intel AX210 (Wi-Fi 6E + Bluetooth 5.2) - RECOMMENDED
   - Intel AX200 (Wi-Fi 6 + Bluetooth 5.1)
   - Qualcomm Atheros cards with ath10k/ath11k support

2. Use a USB wireless adapter:
   - Look for adapters with MediaTek MT7612, MT7663, or MT7915 chips
   - These are well supported by the mt76 driver

3. Check for driver updates:
   - Run: sudo pacman -Syu
   - Check dmesg output: dmesg | grep -i mediatek

TESTING WIFI:
1. Check if interface is detected: ip link show
2. Scan for networks: sudo iw dev wlan0 scan | grep SSID
3. Connect via NetworkManager: nmcli device wifi connect "SSID" password "PASSWORD"

For immediate connectivity, use Ethernet connection.
EOF

    chown "$USERNAME":"$USERNAME" "/mnt/home/$USERNAME/WIRELESS_INFO.txt"
    
    print_success "MediaTek WiFi configuration completed"
}

configure_norwegian_keyboard() {
    print_header "Configuring Norwegian Keyboard Layout"
    
    print_status "Setting up Norwegian keyboard layout..."
    
    # X11 keymap configuration
    cat > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf << 'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "no"
    Option "XkbModel" "pc105"
    Option "XkbVariant" ""
    Option "XkbOptions" ""
EndSection
EOF

    print_success "Norwegian keyboard layout configured"
}

# ENHANCED: AMD Ryzen 9950X optimizations
configure_amd_optimizations() {
    print_header "Configuring AMD Ryzen 9950X Optimizations"
    
    print_status "Installing AMD-specific packages..."
    arch-chroot /mnt pacman -S --noconfirm amd-ucode zenpower3-dkms
    
    # Configure CPU governor
    cat > /mnt/etc/systemd/system/cpu-performance.service << 'EOF'
[Unit]
Description=Set CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    arch-chroot /mnt systemctl enable cpu-performance.service
    
    print_success "AMD optimizations configured"
}

# ====
# SECURITY CONFIGURATION - ENHANCED for systemd-boot
# ====

setup_secure_boot() {
    if [[ "$ENABLE_SECURE_BOOT" != "y" ]]; then
        print_status "Skipping Secure Boot setup (user choice)"
        return 0
    fi
    
    print_header "Setting Up Secure Boot with systemd-boot"
    
    print_status "Installing sbctl..."
    arch-chroot /mnt pacman -S --noconfirm sbctl
    
    # Create Secure Boot setup script
    cat > /mnt/setup_secure_boot.sh << 'EOF'
#!/bin/bash
set -euo pipefail

echo "Creating Secure Boot keys..."
sbctl create-keys

echo "Enrolling keys (including Microsoft keys for compatibility)..."
sbctl enroll-keys -m

echo "Signing boot components..."
sbctl sign -s /boot/vmlinuz-linux
sbctl sign -s /boot/vmlinuz-linux-lts
sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI

echo "Creating pacman hook for automatic signing..."
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/95-secureboot.hook << SECUREBOOT_HOOK_EOF
[Trigger]
Operation=Install
Operation=Upgrade
Type=Package
Target=linux
Target=linux-lts
Target=systemd

[Action]
Description=Signing kernel and bootloader for Secure Boot
When=PostTransaction
Exec=/usr/bin/sbctl sign-all
Depends=sbctl
SECUREBOOT_HOOK_EOF

echo "Secure Boot setup completed!"
echo "IMPORTANT: Reboot and enable Secure Boot in BIOS/UEFI settings."
echo "Check status with: sbctl status"
EOF

    chmod +x /mnt/setup_secure_boot.sh
    
    print_warning "Secure Boot keys will be created. Run 'sudo /setup_secure_boot.sh' after first boot."
    print_warning "Then enable Secure Boot in BIOS/UEFI settings."
}

configure_firewall() {
    print_header "Configuring Firewall"
    
    print_status "Installing and configuring UFW..."
    arch-chroot /mnt pacman -S --noconfirm ufw
    
    # Configure UFW
    arch-chroot /mnt ufw --force enable
    arch-chroot /mnt ufw default deny incoming
    arch-chroot /mnt ufw default allow outgoing
    
    # Enable UFW service
    arch-chroot /mnt systemctl enable ufw
    
    print_success "Firewall configured and enabled"
}

# ====
# PACKAGE INSTALLATION
# ====

install_desktop_environment() {
    print_header "Installing Desktop Environment"
    
    print_status "Installing KDE Plasma and applications..."
    arch-chroot /mnt pacman -S --noconfirm "${DESKTOP_PACKAGES[@]}"
    
    print_status "Enabling display manager..."
    arch-chroot /mnt systemctl enable sddm
    
    print_status "Configuring audio..."
    arch-chroot /mnt systemctl --global enable pipewire pipewire-pulse
    
    print_success "Desktop environment installed"
}

install_development_tools() {
    if [[ "$INSTALL_DEVELOPMENT_TOOLS" != "y" ]]; then
        print_status "Skipping development tools installation (user choice)"
        return 0
    fi
    
    print_header "Installing Development Environment"
    
    print_status "Installing development packages..."
    arch-chroot /mnt pacman -S --noconfirm "${DEVELOPMENT_PACKAGES[@]}"
    
    print_status "Enabling Docker service..."
    arch-chroot /mnt systemctl enable docker
    arch-chroot /mnt usermod -aG docker "$USERNAME"
    
    print_status "Installing Rust toolchain..."
    arch-chroot /mnt sudo -u "$USERNAME" rustup default stable
    
    print_success "Development environment installed"
}

install_applications() {
    print_header "Installing Applications"
    
    print_status "Installing application packages..."
    arch-chroot /mnt pacman -S --noconfirm "${APPLICATION_PACKAGES[@]}"
    
    print_status "Enabling services..."
    arch-chroot /mnt systemctl enable --global flatpak
    
    print_success "Applications installed"
}

install_aur_helper() {
    print_header "Installing AUR Helper"
    
    print_status "Installing yay AUR helper..."
    
    # Create script to install yay as user
    cat > /mnt/install_yay.sh << 'EOF'
#!/bin/bash
set -euo pipefail

cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay
EOF

    chmod +x /mnt/install_yay.sh
    arch-chroot /mnt sudo -u "$USERNAME" /install_yay.sh
    rm /mnt/install_yay.sh
    
    print_success "AUR helper installed"
}

install_aur_packages() {
    print_header "Installing Essential AUR Packages"
    
    print_status "Installing selected AUR packages..."
    
    # Create script to install AUR packages
    cat > /mnt/install_aur.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Install essential AUR packages
yay -S --noconfirm visual-studio-code-bin brave-bin

# Install development tools
yay -S --noconfirm postman-bin

# Install system utilities
yay -S --noconfirm timeshift auto-cpufreq

echo "Essential AUR packages installed successfully"
EOF

    chmod +x /mnt/install_aur.sh
    arch-chroot /mnt sudo -u "$USERNAME" /install_aur.sh
    rm /mnt/install_aur.sh
    
    print_success "AUR packages installed"
}

# ====
# SYSTEM OPTIMIZATION - ENHANCED
# ====

optimize_system() {
    print_header "Optimizing System"
    
    print_status "Configuring system optimizations..."
    
    # Enable multilib repository
    sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
    
    # Configure makepkg for faster compilation - FIXED: Proper quoting
    sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/' /mnt/etc/makepkg.conf
    sed -i 's/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -z - --threads=0)/' /mnt/etc/makepkg.conf
    
    # Configure pacman for faster downloads
    sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /mnt/etc/pacman.conf
    
    # Enable SSD optimizations if applicable
    if [[ "$SELECTED_DISK" =~ nvme ]] || [[ "$SELECTED_DISK" =~ ssd ]]; then
        print_status "Enabling SSD optimizations..."
        arch-chroot /mnt systemctl enable fstrim.timer
    fi
    
    # Configure AMD optimizations
    configure_amd_optimizations
    
    print_success "System optimizations applied"
}

create_user_scripts() {
    print_header "Creating User Scripts"
    
    # Create update script - FIXED: Proper quoting
    cat > "/mnt/home/$USERNAME/update-system.sh" << 'EOF'
#!/bin/bash
# System update script

echo "Updating official packages..."
sudo pacman -Syu

echo "Updating AUR packages..."
yay -Sua

echo "Cleaning package cache..."
sudo pacman -Sc --noconfirm

echo "Removing orphaned packages..."
orphans=$(pacman -Qtdq)
if [[ -n "$orphans" ]]; then
    sudo pacman -Rns $orphans --noconfirm
fi

echo "System update completed!"
EOF

    # Create development environment setup script
    cat > "/mnt/home/$USERNAME/setup-dev-env.sh" << 'EOF'
#!/bin/bash
# Development environment setup script

echo "Setting up development environment..."

# Install Node Version Manager
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Install Python version manager
curl https://pyenv.run | bash

# Configure Git (user will need to set their details)
echo "Configure Git with your details:"
echo "git config --global user.name 'Your Name'"
echo "git config --global user.email 'your.email@example.com'"

echo "Development environment setup completed!"
echo "Restart your terminal to use nvm and pyenv."
EOF

    # Make scripts executable - FIXED: Proper quoting
    chmod +x "/mnt/home/$USERNAME/update-system.sh"
    chmod +x "/mnt/home/$USERNAME/setup-dev-env.sh"
    
    print_success "User scripts created"
}

create_post_install_info() {
    print_header "Creating Post-Installation Guide"
    
    # Create comprehensive post-installation guide - FIXED: Proper quoting
    cat > "/mnt/home/$USERNAME/POST_INSTALL_GUIDE.md" << 'EOF'
# Arch Linux Post-Installation Guide

## System Information
- **Installation Date**: $(date)
- **Kernel**: Linux with LTS fallback
- **Bootloader**: systemd-boot
- **Desktop Environment**: KDE Plasma
- **Graphics**: NVIDIA RTX 5090 with open drivers
- **CPU**: AMD Ryzen 9950X with optimizations

## First Boot Steps

### 1. Network Configuration
If WiFi doesn't work (MediaTek MT7927 issue):
```bash
# Check network interfaces
ip link show

# Connect to WiFi if available
nmcli device wifi connect "SSID" password "PASSWORD"

# Or use Ethernet for now
```

### 2. System Updates
```bash
# Update system
sudo pacman -Syu

# Update AUR packages
yay -Sua
```

### 3. Secure Boot Setup (if enabled)
```bash
# Run the secure boot setup script
sudo /setup_secure_boot.sh

# Reboot and enable Secure Boot in BIOS
# Check status after reboot
sbctl status
```

### 4. Graphics Configuration
```bash
# Check NVIDIA driver status
nvidia-smi

# Configure NVIDIA settings
nvidia-settings
```

### 5. Development Environment
```bash
# Run development setup script
./setup-dev-env.sh

# Configure Git
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## Hardware-Specific Notes

### AMD Ryzen 9950X
- CPU performance governor is enabled by default
- Zenpower3 module provides better power monitoring
- All cores should be detected and functional

### NVIDIA RTX 5090
- Using open-source NVIDIA drivers (recommended)
- CUDA support should work out of the box
- For gaming, enable GameMode: `gamemoderun <game>`

### MediaTek MT7927 WiFi
- Check ~/WIRELESS_INFO.txt for detailed information
- Consider replacing with Intel AX210 for best compatibility
- USB WiFi adapters are a temporary solution

### Norwegian Keyboard
- Console and X11 layouts are configured
- Should work in both TTY and desktop environment

## Useful Commands

### System Maintenance
```bash
# Update everything
./update-system.sh

# Check system status
systemctl status

# View system logs
journalctl -xe

# Check disk usage
df -h
```

### Package Management
```bash
# Search packages
pacman -Ss <package>
yay -Ss <package>

# Install packages
sudo pacman -S <package>
yay -S <aur-package>

# Remove packages
sudo pacman -Rns <package>
```

### Performance Monitoring
```bash
# CPU information
lscpu

# GPU information
nvidia-smi

# Memory usage
free -h

# Disk I/O
iotop

# Network usage
nethogs
```

## Troubleshooting

### Boot Issues
- Use LTS kernel from boot menu if main kernel fails
- Check systemd-boot entries in /boot/loader/entries/

### Graphics Issues
- Switch to TTY with Ctrl+Alt+F2
- Check logs: `journalctl -u sddm`
- Reinstall drivers: `sudo pacman -S nvidia-open`

### Network Issues
- Check NetworkManager: `systemctl status NetworkManager`
- Restart network: `sudo systemctl restart NetworkManager`
- Use ethernet cable for troubleshooting

### Performance Issues
- Check CPU governor: `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`
- Monitor temperatures: `sensors`
- Check for thermal throttling: `dmesg | grep -i thermal`

## Additional Software

### Gaming
```bash
# Install Steam games
# Enable Proton in Steam settings

# Install Lutris for other games
# Configure Wine prefixes as needed

# Use GameMode for better performance
gamemoderun <game>
```

### Development
```bash
# Install additional IDEs
yay -S intellij-idea-community-edition
yay -S pycharm-community-edition

# Install Docker containers
docker pull ubuntu
docker pull node
```

### Multimedia
```bash
# Install codecs
sudo pacman -S gst-plugins-good gst-plugins-bad gst-plugins-ugly

# Install additional media tools
sudo pacman -S handbrake ffmpeg
```

## Security Recommendations

1. **Firewall**: UFW is enabled and configured
2. **Updates**: Keep system updated regularly
3. **Secure Boot**: Enable if you set it up
4. **User Permissions**: Don't run unnecessary commands as root
5. **Backups**: Set up Timeshift for system snapshots

## Support Resources

- **Arch Wiki**: https://wiki.archlinux.org/
- **Forums**: https://bbs.archlinux.org/
- **Reddit**: r/archlinux
- **IRC**: #archlinux on Libera.Chat

## Files Created by Installer

- `~/update-system.sh` - System update script
- `~/setup-dev-env.sh` - Development environment setup
- `~/WIRELESS_INFO.txt` - WiFi compatibility information
- `~/POST_INSTALL_GUIDE.md` - This guide
- `/setup_secure_boot.sh` - Secure Boot configuration (if enabled)

Enjoy your new Arch Linux system!
EOF

    # Set ownership - FIXED: Proper quoting
    chown "$USERNAME":"$USERNAME" "/mnt/home/$USERNAME/POST_INSTALL_GUIDE.md"
    
    print_success "Post-installation guide created"
}

# ====
# MAIN INSTALLATION FUNCTION
# ====

main() {
    print_header "$SCRIPT_NAME v$SCRIPT_VERSION"
    
    # Pre-installation checks
    check_uefi_boot
    check_internet_connection
    update_system_clock
    
    # User configuration
    get_user_input
    select_disk
    
    # Final confirmation
    echo
    print_warning "FINAL CONFIRMATION"
    echo "Username: $USERNAME"
    echo "Hostname: $HOSTNAME"
    echo "Disk: $SELECTED_DISK"
    echo "Timezone: $TIMEZONE"
    echo "Secure Boot: $ENABLE_SECURE_BOOT"
    echo "Development Tools: $INSTALL_DEVELOPMENT_TOOLS"
    echo
    
    if ! confirm "Proceed with installation? This will WIPE $SELECTED_DISK!" "n"; then
        print_status "Installation cancelled by user."
        exit 0
    fi
    
    # Disk preparation
    prepare_disk
    format_partitions
    mount_partitions
    
    # Base system installation
    install_base_system
    configure_system
    
    # Hardware-specific configuration
    install_nvidia_drivers
    configure_mediatek_workaround
    configure_norwegian_keyboard
    
    # Security configuration
    setup_secure_boot
    configure_firewall
    
    # Package installation
    install_desktop_environment
    install_development_tools
    install_applications
    install_aur_helper
    install_aur_packages
    
    # System optimization
    optimize_system
    create_user_scripts
    create_post_install_info
    
    # Final steps
    print_header "Installation Complete!"
    
    print_success "Arch Linux installation completed successfully!"
    echo
    print_status "Next steps:"
    echo "1. Reboot into your new system"
    echo "2. Read ~/POST_INSTALL_GUIDE.md for important information"
    echo "3. Run ~/setup-dev-env.sh to complete development environment setup"
    echo "4. Configure Secure Boot if enabled (run: sudo /setup_secure_boot.sh)"
    echo "5. Address MediaTek wireless card compatibility (see ~/WIRELESS_INFO.txt)"
    echo
    
    if confirm "Reboot now?" "y"; then
        reboot
    fi
}

# ====
# SCRIPT EXECUTION
# ====

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root (from Arch Linux live environment)"
fi

# FIXED: Added the missing main function call that was causing the hang
main "$@"
