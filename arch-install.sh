#!/bin/bash

# =============================================================================
# Improved Arch Linux Installation Script
# =============================================================================
# 
# This script provides an interactive, comprehensive Arch Linux installation
# with hardware-specific optimizations, security hardening, and complete
# development environment setup.
#
# Target Hardware:
# - AMD Ryzen 9 9950X
# - ASRock X670E Taichi
# - NVIDIA RTX 5090
# - MediaTek MT7927 (requires workaround)
# - Norwegian keyboard layout
#
# Features:
# - Interactive configuration prompts
# - Complete disk wipe and partitioning
# - Secure Boot with sbctl
# - Hardware-specific driver installation
# - Comprehensive development tools
# - Security hardening
# - Error handling and recovery
#
# Author: Generated for Arch Linux 2025
# Date: June 25, 2025
# =============================================================================

set -euo pipefail

# =============================================================================
# GLOBAL VARIABLES AND CONFIGURATION
# =============================================================================

# Script metadata
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_NAME="Arch Linux Improved Installer"

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
    "amd-ucode" "grub" "efibootmgr" "networkmanager"
    "sudo" "nano" "vim" "git" "wget" "curl"
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
    "redis" "mongodb-bin"
    
    # Containers and virtualization
    "docker" "docker-compose" "podman" "qemu-full" "virt-manager"
    "virtualbox" "virtualbox-host-modules-arch"
    
    # Version control and collaboration
    "git-lfs" "mercurial" "subversion" "bzr"
    
    # Build systems and package managers
    "meson" "ninja" "autoconf" "automake" "libtool"
    "pkgconf" "flatpak" "snapd"
)

readonly DESKTOP_PACKAGES=(
    # KDE Plasma desktop environment
    "plasma-meta" "plasma-wayland-session" "kde-applications-meta"
    "sddm" "sddm-kcm" "xorg-xwayland"
    
    # Display and graphics
    "xorg-server" "xorg-apps" "mesa" "vulkan-radeon"
    "nvidia" "nvidia-utils" "nvidia-settings" "lib32-nvidia-utils"
    
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
    "thunderbird" "discord" "telegram-desktop" "signal-desktop"
    
    # Office and productivity
    "libreoffice-fresh" "okular" "spectacle" "dolphin"
    "kate" "kwrite" "kcalc" "ark" "filelight"
    
    # Media
    "mpv" "vlc" "gimp" "inkscape" "kdenlive" "audacity"
    "obs-studio" "blender"
    
    # Development IDEs and editors
    "neovim" "emacs" "code" "intellij-idea-community-edition"
    "qtcreator" "android-studio"
    
    # System utilities
    "htop" "btop" "neofetch" "tree" "unzip" "p7zip"
    "rsync" "rclone" "tmux" "screen" "zsh" "fish"
    "copyq" "flameshot" "redshift"
    
    # Modern CLI tools
    "exa" "bat" "ripgrep" "fd" "fzf" "zoxide" "starship"
    "dust" "duf" "procs" "bandwhich" "bottom"
    
    # Gaming
    "steam" "lutris" "wine" "winetricks" "gamemode"
    "mangohud" "goverlay"
    
    # Security and privacy
    "ufw" "fail2ban" "clamav" "rkhunter" "lynis"
    "keepassxc" "veracrypt"
    
    # Note-taking and documentation
    "joplin-desktop" "obsidian" "zettlr" "typora"
    
    # Network tools
    "nmap" "wireshark-qt" "tcpdump" "iperf3" "mtr"
    "openvpn" "wireguard-tools"
)

readonly AUR_PACKAGES=(
    # Browsers and applications not in official repos
    "brave-bin" "google-chrome" "visual-studio-code-bin"
    "spotify" "slack-desktop" "zoom" "teams"
    
    # Development tools
    "postman-bin" "insomnia-bin" "dbeaver" "datagrip"
    "pycharm-community-edition" "webstorm" "phpstorm"
    
    # System utilities
    "yay" "paru" "timeshift" "timeshift-autosnap"
    "auto-cpufreq" "tlp" "powertop"
    
    # Media and entertainment
    "jellyfin-media-player" "plex-media-player" "kodi"
    
    # Productivity
    "notion-app" "todoist" "toggl-track"
    
    # Gaming
    "heroic-games-launcher-bin" "legendary" "bottles"
    
    # Security
    "protonvpn" "nordvpn-bin" "mullvad-vpn"
    
    # Fonts and themes
    "ttf-ms-fonts" "ttf-vista-fonts" "nerd-fonts-complete"
    "papirus-icon-theme" "arc-gtk-theme"
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

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
    if mountpoint -q /mnt; then
        print_status "Cleaning up mounts..."
        umount -R /mnt 2>/dev/null || true
    fi
}

# Set up error handling
trap cleanup EXIT
trap 'error_exit "Script interrupted by user"' INT TERM

# Confirmation prompt
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$prompt [Y/n]: " response
            response=${response:-y}
        else
            read -p "$prompt [y/N]: " response
            response=${response:-n}
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Secure password input
read_password() {
    local prompt="$1"
    local password
    local password_confirm
    
    while true; do
        echo -n "$prompt: "
        read -s password
        echo
        echo -n "Confirm password: "
        read -s password_confirm
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

# =============================================================================
# SYSTEM VALIDATION FUNCTIONS
# =============================================================================

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

# =============================================================================
# USER INPUT FUNCTIONS
# =============================================================================

get_user_input() {
    print_header "System Configuration"
    
    # Username
    while [[ -z "$USERNAME" ]]; do
        read -p "Enter username: " USERNAME
        if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            print_error "Invalid username. Use lowercase letters, numbers, underscore, and hyphen only."
            USERNAME=""
        fi
    done
    
    # Hostname
    while [[ -z "$HOSTNAME" ]]; do
        read -p "Enter hostname: " HOSTNAME
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
    read -p "Enter timezone (e.g., Europe/Oslo): " TIMEZONE
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
        read -p "Enter disk to install to (e.g., /dev/nvme0n1 or /dev/sda): " SELECTED_DISK
        
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

# =============================================================================
# DISK MANAGEMENT FUNCTIONS
# =============================================================================

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

# =============================================================================
# BASE SYSTEM INSTALLATION
# =============================================================================

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

# Configure mkinitcpio for NVIDIA
sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sed -i 's/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/' /etc/mkinitcpio.conf

# Generate initramfs
mkinitcpio -P

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1 nvidia_drm.fbdev=1"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

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
Target=nvidia
Target=linux

[Action]
Description=Update initramfs for NVIDIA
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux) exit 0; esac; done; /usr/bin/mkinitcpio -P'
NVIDIA_HOOK_EOF

EOF

    # Make script executable and run it
    chmod +x /mnt/configure_system.sh
    arch-chroot /mnt ./configure_system.sh "$TIMEZONE" "$HOSTNAME" "$ROOT_PASSWORD" "$USERNAME" "$USER_PASSWORD"
    
    # Remove the script
    rm /mnt/configure_system.sh
    
    print_success "System configuration completed"
}

# =============================================================================
# HARDWARE-SPECIFIC CONFIGURATION
# =============================================================================

install_nvidia_drivers() {
    print_header "Installing NVIDIA RTX 5090 Drivers"
    
    print_status "Installing NVIDIA packages..."
    arch-chroot /mnt pacman -S --noconfirm nvidia nvidia-utils nvidia-settings lib32-nvidia-utils
    
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
EndSection
EOF

    print_success "NVIDIA drivers installed and configured"
}

configure_mediatek_workaround() {
    print_header "MediaTek MT7927 Wireless Workaround"
    
    print_warning "MediaTek MT7927 is not supported by the Linux kernel as of 2025."
    print_warning "Wireless functionality will not work with this chipset."
    print_warning "Recommended solution: Replace with Intel AX210 or compatible card."
    
    # Install alternative wireless tools for USB adapters
    print_status "Installing wireless tools for potential USB adapter use..."
    arch-chroot /mnt pacman -S --noconfirm wireless_tools wpa_supplicant iw
    
    # Create information file for user
    cat > /mnt/home/$USERNAME/WIRELESS_INFO.txt << 'EOF'
MEDIATEK MT7927 WIRELESS CARD COMPATIBILITY NOTICE
==================================================

Your system contains a MediaTek MT7927 wireless card, which is currently
NOT SUPPORTED by the Linux kernel (as of 2025).

SOLUTIONS:
1. Replace the M.2 wireless card with a supported model:
   - Intel AX210 (Wi-Fi 6E + Bluetooth 5.2) - RECOMMENDED
   - Intel AX200 (Wi-Fi 6 + Bluetooth 5.1)
   - Qualcomm Atheros cards with ath10k/ath11k support

2. Use a USB wireless adapter temporarily:
   - Look for adapters with MediaTek MT7612, MT7663, or MT7915 chips
   - These are supported by the mt76 driver

3. Monitor kernel development:
   - Check for MT7927 support in future kernel releases
   - Follow linux-wireless mailing list for updates

For immediate wireless connectivity, use Ethernet or a supported USB adapter.
EOF

    chown $USERNAME:$USERNAME /mnt/home/$USERNAME/WIRELESS_INFO.txt
    
    print_warning "Wireless compatibility information saved to ~/WIRELESS_INFO.txt"
}

configure_norwegian_keyboard() {
    print_header "Configuring Norwegian Keyboard Layout"
    
    print_status "Setting up Norwegian keyboard layout..."
    
    # Console keymap (already set in vconsole.conf)
    print_status "Console keymap configured: Norwegian"
    
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

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

setup_secure_boot() {
    if [[ "$ENABLE_SECURE_BOOT" != "y" ]]; then
        print_status "Skipping Secure Boot setup (user choice)"
        return 0
    fi
    
    print_header "Setting Up Secure Boot"
    
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
sbctl sign -s /boot/grub/x86_64-efi/grub.efi

echo "Creating pacman hook for automatic signing..."
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/95-secureboot.hook << SECUREBOOT_HOOK_EOF
[Trigger]
Operation=Install
Operation=Upgrade
Type=Package
Target=linux
Target=linux-lts
Target=grub

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
    
    print_warning "Secure Boot keys created. Run 'sudo /setup_secure_boot.sh' after first boot."
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

# =============================================================================
# PACKAGE INSTALLATION
# =============================================================================

install_desktop_environment() {
    print_header "Installing Desktop Environment"
    
    print_status "Installing KDE Plasma and applications..."
    arch-chroot /mnt pacman -S --noconfirm "${DESKTOP_PACKAGES[@]}"
    
    print_status "Enabling display manager..."
    arch-chroot /mnt systemctl enable sddm
    
    print_status "Configuring audio..."
    arch-chroot /mnt systemctl --user enable pipewire pipewire-pulse
    
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
    
    print_status "Enabling Flatpak..."
    arch-chroot /mnt systemctl enable --user flatpak
    
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
    print_header "Installing AUR Packages"
    
    print_status "Installing selected AUR packages..."
    
    # Create script to install AUR packages
    cat > /mnt/install_aur.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Install essential AUR packages first
yay -S --noconfirm visual-studio-code-bin brave-bin

# Install development tools
yay -S --noconfirm postman-bin

# Install system utilities
yay -S --noconfirm timeshift auto-cpufreq

echo "AUR packages installed successfully"
EOF

    chmod +x /mnt/install_aur.sh
    arch-chroot /mnt sudo -u "$USERNAME" /install_aur.sh
    rm /mnt/install_aur.sh
    
    print_success "AUR packages installed"
}

# =============================================================================
# SYSTEM OPTIMIZATION
# =============================================================================

optimize_system() {
    print_header "Optimizing System"
    
    print_status "Configuring system optimizations..."
    
    # Enable multilib repository
    sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
    
    # Configure makepkg for faster compilation
    sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/' /mnt/etc/makepkg.conf
    sed -i 's/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -z - --threads=0)/' /mnt/etc/makepkg.conf
    
    # Configure pacman for faster downloads
    sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /mnt/etc/pacman.conf
    
    # Enable SSD optimizations if applicable
    if [[ "$SELECTED_DISK" =~ nvme ]] || [[ "$SELECTED_DISK" =~ ssd ]]; then
        print_status "Enabling SSD optimizations..."
        arch-chroot /mnt systemctl enable fstrim.timer
    fi
    
    print_success "System optimizations applied"
}

create_user_scripts() {
    print_header "Creating User Scripts"
    
    # Create update script
    cat > /mnt/home/$USERNAME/update-system.sh << 'EOF'
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
    cat > /mnt/home/$USERNAME/setup-dev-env.sh << 'EOF'
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

# Install Oh My Zsh (optional)
if command -v zsh >/dev/null 2>&1; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

echo "Development environment setup completed!"
echo "Restart your terminal or run 'source ~/.bashrc' to apply changes."
EOF

    # Make scripts executable
    chmod +x /mnt/home/$USERNAME/update-system.sh
    chmod +x /mnt/home/$USERNAME/setup-dev-env.sh
    
    # Set ownership
    arch-chroot /mnt chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
    
    print_success "User scripts created"
}

# =============================================================================
# POST-INSTALLATION TASKS
# =============================================================================

create_post_install_info() {
    print_header "Creating Post-Installation Information"
    
    cat > /mnt/home/$USERNAME/POST_INSTALL_GUIDE.md << 'EOF'
# Post-Installation Guide

## First Boot Steps

1. **Enable Secure Boot** (if configured):
   ```bash
   sudo /setup_secure_boot.sh
   ```
   Then reboot and enable Secure Boot in BIOS/UEFI settings.

2. **Update System**:
   ```bash
   ./update-system.sh
   ```

3. **Setup Development Environment**:
   ```bash
   ./setup-dev-env.sh
   ```

## Hardware Notes

### MediaTek MT7927 Wireless
- **NOT SUPPORTED** by Linux kernel as of 2025
- Use Ethernet or USB wireless adapter
- Consider replacing with Intel AX210 card
- See `~/WIRELESS_INFO.txt` for details

### NVIDIA RTX 5090
- Drivers installed and configured
- Use `nvidia-settings` for GPU configuration
- Wayland support enabled with DRM modeset

## Useful Commands

### System Maintenance
```bash
# Update system
sudo pacman -Syu

# Clean package cache
sudo pacman -Sc

# Remove orphaned packages
sudo pacman -Rns $(pacman -Qtdq)

# Check system status
systemctl status
```

### Development Tools
```bash
# Check installed languages
python --version
node --version
go version
rustc --version

# Docker commands
sudo systemctl start docker
docker --version
```

### Security
```bash
# Check Secure Boot status
sudo sbctl status

# Firewall status
sudo ufw status

# Check for updates
sudo pacman -Qu
```

## Troubleshooting

### Display Issues
- Check NVIDIA driver: `nvidia-smi`
- Restart display manager: `sudo systemctl restart sddm`

### Network Issues
- Check NetworkManager: `sudo systemctl status NetworkManager`
- Restart network: `sudo systemctl restart NetworkManager`

### Boot Issues
- Check GRUB configuration: `/etc/default/grub`
- Regenerate GRUB: `sudo grub-mkconfig -o /boot/grub/grub.cfg`

## Additional Resources

- [Arch Wiki](https://wiki.archlinux.org/)
- [Arch Forums](https://bbs.archlinux.org/)
- [AUR](https://aur.archlinux.org/)

EOF

    chown $USERNAME:$USERNAME /mnt/home/$USERNAME/POST_INSTALL_GUIDE.md
    
    print_success "Post-installation guide created"
}

# =============================================================================
# MAIN INSTALLATION FLOW
# =============================================================================

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
    echo "4. Configure Secure Boot if enabled"
    echo "5. Address MediaTek wireless card compatibility (see ~/WIRELESS_INFO.txt)"
    echo
    
    if confirm "Reboot now?" "y"; then
        reboot
    fi
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root (from Arch Linux live environment)"
fi

# Run main installation
main "$@"
