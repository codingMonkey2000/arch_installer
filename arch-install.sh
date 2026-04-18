#!/bin/bash

# ====
# Arch Linux Installation Script — GNOME Edition
# ====
#
# Changes from previous version:
# - Desktop environment: KDE Plasma → GNOME 50+
# - Bootloader: systemd-boot (unchanged, correct choice)
# - Kernel: Arch 'linux' package tracks latest stable (7.x as of 2026)
#           'linux-lts' tracks latest LTS (currently 6.12.x)
# - NVIDIA Secure Boot: Added DKMS module signing via sbctl keys
#   NOTE: Self-signing is completely valid. You do NOT need a Microsoft
#   certificate. sbctl enroll-keys -m adds MS keys only for hardware
#   firmware compatibility (Intel ME, UEFI option ROMs). Your own
#   platform key (PK) + key exchange key (KEK) + db key is all you need.
# - Removed kms from mkinitcpio HOOKS (required for NVIDIA on kernel 7+)
# - Fixed zenpower3-dkms (AUR-only, moved to yay section)
# - Fixed flatpak systemctl enable (flatpak is not a service)
# - Fixed $(date) inside single-quoted heredoc (never expanded)
# - Fixed arch-chroot sudo -u → runuser -u (more reliable in chroot)
# - Fixed MAKEFLAGS sed escaping ($(nproc) was shell-expanding at sed time)
# - Fixed double call to configure_amd_optimizations
# - Added GDM Wayland environment configuration
# - Replaced all KDE application packages with GNOME equivalents
#
# Target Hardware:
# - AMD Ryzen 9 9950X
# - ASRock X670E Taichi
# - NVIDIA RTX 5090
# - MediaTek MT7927 WiFi (with workaround)
# - Norwegian keyboard layout
#
# Author: Fixed GNOME edition for Arch Linux 2026
# ====

set -euo pipefail

# ====
# GLOBAL VARIABLES AND CONFIGURATION
# ====

readonly SCRIPT_VERSION="3.0.0-GNOME"
readonly SCRIPT_NAME="Arch Linux GNOME Installer"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

USERNAME=""
HOSTNAME=""
ROOT_PASSWORD=""
USER_PASSWORD=""
SELECTED_DISK=""
TIMEZONE=""
ENABLE_SECURE_BOOT="y"
INSTALL_DEVELOPMENT_TOOLS="y"

readonly KEYMAP="no"
readonly LOCALE="en_US.UTF-8"
readonly DEFAULT_SHELL="/bin/bash"

# ====
# PACKAGE ARRAYS
# ====

readonly BASE_PACKAGES=(
    "base" "base-devel" "linux" "linux-lts" "linux-firmware"
    "amd-ucode" "systemd" "efibootmgr" "networkmanager"
    "sudo" "nano" "vim" "git" "wget" "curl" "reflector"
    # DKMS is required for nvidia-open module rebuilding on kernel updates
    "dkms" "linux-headers" "linux-lts-headers"
)

readonly DEVELOPMENT_PACKAGES=(
    "git" "base-devel" "cmake" "make" "gcc" "clang" "gdb"
    "valgrind" "strace" "ltrace" "perf"
    "python" "python-pip" "python-virtualenv" "python-pipenv"
    "nodejs" "npm" "yarn" "go" "rust" "rustup"
    "jdk-openjdk" "openjdk-doc" "maven" "gradle"
    "ruby" "php" "lua" "perl"
    "postgresql" "postgresql-libs" "mariadb" "sqlite"
    "redis"
    "docker" "docker-compose" "podman" "qemu-full" "virt-manager"
    "git-lfs" "mercurial" "subversion"
    "meson" "ninja" "autoconf" "automake" "libtool"
    "pkgconf" "flatpak"
)

# FIX: Replaced all KDE/Plasma packages with GNOME 50+ equivalents.
# GNOME 50 ships full Wayland-first by default; XWayland is still
# included for compatibility. GDM replaces SDDM.
readonly DESKTOP_PACKAGES=(
    # GNOME desktop environment (meta-package pulls in shell, mutter, etc.)
    "gnome"
    # Extra GNOME applications (Files, Calendar, Maps, Weather, etc.)
    "gnome-extra"
    # GDM display manager (replaces SDDM)
    "gdm"
    # Portal backend for Flatpak / screen sharing under Wayland
    "xdg-desktop-portal-gnome"
    # User directory management (~Downloads, ~/Pictures, etc.)
    "xdg-user-dirs"
    # XWayland for legacy X11 applications
    "xorg-xwayland"

    # Graphics — keep mesa for CPU/Wayland fallback, NVIDIA handled separately
    "mesa" "vulkan-radeon" "lib32-mesa"

    # Audio — PipeWire stack (same as before, works with GNOME)
    "pipewire" "pipewire-alsa" "pipewire-pulse" "pipewire-jack"
    "wireplumber" "pavucontrol" "alsa-utils"

    # Fonts
    "ttf-dejavu" "ttf-liberation" "noto-fonts" "noto-fonts-emoji"
    "ttf-roboto" "ttf-opensans" "adobe-source-code-pro-fonts"
)

# FIX: Replaced KDE-specific apps (okular, kate, kcalc, ark, dolphin,
# spectacle, filelight) with their GNOME counterparts.
readonly APPLICATION_PACKAGES=(
    # Web browsers
    "firefox" "chromium"

    # Communication
    "thunderbird" "telegram-desktop"

    # Office and productivity
    "libreoffice-fresh"
    "evince"            # replaces okular (PDF/document viewer)
    "gnome-text-editor" # replaces kate/kwrite
    "gnome-calculator"  # replaces kcalc
    "file-roller"       # replaces ark (archive manager)
    "baobab"            # replaces filelight (disk usage)
    "gnome-screenshot"  # replaces spectacle

    # Media
    "mpv" "vlc" "gimp" "inkscape" "kdenlive" "audacity"
    "obs-studio"

    # Development editors
    "neovim" "emacs"

    # System utilities
    "htop" "btop" "neofetch" "tree" "unzip" "p7zip"
    "rsync" "tmux" "screen" "zsh" "fish"
    "flameshot" "redshift"

    # Modern CLI tools
    "eza"      # exa was renamed to eza
    "bat" "ripgrep" "fd" "fzf" "zoxide" "starship"

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

print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_header()  { echo -e "\n${PURPLE}=== $1 ===${NC}\n"; }

error_exit() {
    print_error "$1"
    print_error "Installation failed. Check the logs above for details."
    exit 1
}

cleanup() {
    if mountpoint -q /mnt 2>/dev/null; then
        print_status "Cleaning up mounts..."
        umount -R /mnt 2>/dev/null || true
    fi
}

trap cleanup EXIT
trap 'error_exit "Script interrupted by user"' INT TERM

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
            [Nn]|[Nn][Oo])     return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

read_password() {
    local prompt="$1"
    local password password_confirm

    while true; do
        echo -en "$prompt (input hidden, just type and press enter): "
        read -r -s password
        echo
        echo -n "Confirm password (input hidden): "
        read -r -s password_confirm
        echo
        if [[ "$password" == "$password_confirm" ]]; then
            if [[ ${#password} -ge 8 ]]; then
                print_status "Password accepted"
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
# SYSTEM VALIDATION
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
# USER INPUT
# ====

get_user_input() {
    print_header "System Configuration"

    while [[ -z "$USERNAME" ]]; do
        read -r -p "Enter username: " USERNAME
        if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            print_error "Invalid username. Use lowercase letters, numbers, underscore, and hyphen only."
            USERNAME=""
        fi
    done

    while [[ -z "$HOSTNAME" ]]; do
        read -r -p "Enter hostname: " HOSTNAME
        if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
            print_error "Invalid hostname. Use letters, numbers, and hyphens only."
            HOSTNAME=""
        fi
    done

    ROOT_PASSWORD=$(read_password "Enter root password")
    USER_PASSWORD=$(read_password "Enter user password")

    print_status "Available timezones (sample):"
    timedatectl list-timezones | grep -E "(Europe|America|Asia)" | head -20
    read -r -p "Enter timezone (e.g., Europe/Oslo): " TIMEZONE
    if ! timedatectl list-timezones | grep -q "^${TIMEZONE}$"; then
        print_warning "Invalid timezone. Using Europe/Oslo as default."
        TIMEZONE="Europe/Oslo"
    fi

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
# DISK MANAGEMENT
# ====

prepare_disk() {
    print_header "Preparing Disk"

    print_status "Wiping disk $SELECTED_DISK..."
    umount -R /mnt 2>/dev/null || true
    wipefs -af "$SELECTED_DISK"
    sgdisk -Z "$SELECTED_DISK"
    sgdisk -o "$SELECTED_DISK"

    print_status "Creating partitions..."
    sgdisk -n 1:0:+1G   -t 1:ef00 -c 1:"EFI System"       "$SELECTED_DISK"
    sgdisk -n 2:0:0      -t 2:8300 -c 2:"Linux filesystem"  "$SELECTED_DISK"

    partprobe "$SELECTED_DISK"
    sleep 2

    print_success "Partitions created successfully"
}

format_partitions() {
    print_header "Formatting Partitions"

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

configure_system() {
    print_header "Configuring System"

    # NOTE: This heredoc uses unquoted EOF so the $1..$5 positional
    # parameters remain as literals and are resolved when the script
    # actually runs inside the chroot with its arguments.
    cat > /mnt/configure_system.sh << 'CONFIGURE_EOF'
#!/bin/bash
set -euo pipefail

TIMEZONE="$1"
HOSTNAME_VAL="$2"
ROOT_PASS="$3"
USERNAME_VAL="$4"
USER_PASS="$5"

# Timezone
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

# Locale
echo "en_US.UTF-8 UTF-8" >  /etc/locale.gen
echo "nb_NO.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Keyboard (console)
echo "KEYMAP=no" > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME_VAL}" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME_VAL}.localdomain ${HOSTNAME_VAL}
HOSTS_EOF

# ── mkinitcpio ──────────────────────────────────────────────────────────────
# FIX: Load amdgpu early so the framebuffer is available before NVIDIA init.
# FIX: Remove the 'kms' hook — with NVIDIA open drivers on kernel 7+ the kms
#      hook conflicts and causes a black screen on Wayland.
sed -i 's/^MODULES=.*/MODULES=(amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
    /etc/mkinitcpio.conf
sed -i 's/ kms//' /etc/mkinitcpio.conf

mkinitcpio -P

# ── systemd-boot ─────────────────────────────────────────────────────────────
bootctl install

mkdir -p /boot/loader/entries

cat > /boot/loader/loader.conf << LOADER_EOF
default arch.conf
timeout 3
console-mode max
editor no
LOADER_EOF

cat > /boot/loader/entries/arch.conf << ARCH_EOF
title   Arch Linux (kernel 7+)
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=LABEL=ROOT rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1
ARCH_EOF

cat > /boot/loader/entries/arch-lts.conf << LTS_EOF
title   Arch Linux LTS (fallback)
linux   /vmlinuz-linux-lts
initrd  /amd-ucode.img
initrd  /initramfs-linux-lts.img
options root=LABEL=ROOT rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1
LTS_EOF

# ── Services ─────────────────────────────────────────────────────────────────
systemctl enable NetworkManager
systemctl enable gdm            # GDM replaces SDDM for GNOME

# ── Passwords & user ─────────────────────────────────────────────────────────
echo "root:${ROOT_PASS}" | chpasswd

# FIX: Added 'wheel' and all needed groups.
useradd -m -G wheel,audio,video,optical,storage,docker \
        -s /bin/bash "${USERNAME_VAL}"
echo "${USERNAME_VAL}:${USER_PASS}" | chpasswd

echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# ── NVIDIA pacman hook (rebuild initramfs on driver/kernel update) ────────────
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/nvidia.hook << NVIDIA_EOF
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
NVIDIA_EOF

# ── systemd-boot auto-update hook ────────────────────────────────────────────
cat > /etc/pacman.d/hooks/95-systemd-boot.hook << SDHOOK_EOF
[Trigger]
Type=Package
Operation=Upgrade
Target=systemd

[Action]
Description=Gracefully upgrading systemd-boot...
When=PostTransaction
Exec=/usr/bin/systemctl restart systemd-boot-update.service
SDHOOK_EOF

# ── GDM / GNOME Wayland environment ──────────────────────────────────────────
# Force GDM to start a Wayland session (default in GNOME 50, but explicit
# is safer with NVIDIA).
mkdir -p /etc/udev/rules.d
cat > /etc/environment << ENV_EOF
# Force Wayland for GNOME apps and Electron-based tools
GNOME_SESSION_TYPE=wayland
XDG_SESSION_TYPE=wayland
ENV_EOF

CONFIGURE_EOF

    chmod +x /mnt/configure_system.sh
    arch-chroot /mnt /configure_system.sh \
        "$TIMEZONE" "$HOSTNAME" "$ROOT_PASSWORD" "$USERNAME" "$USER_PASSWORD"
    rm /mnt/configure_system.sh

    print_success "System configuration completed"
}

# ====
# NVIDIA RTX 5090 — OPEN DRIVERS + SECURE BOOT SIGNING
# ====

install_nvidia_drivers() {
    print_header "Installing NVIDIA RTX 5090 Drivers"

    # nvidia-open: the official open-source GSP kernel modules.
    # Required for RTX 5090 (Ada Lovelace+ architecture).
    # Uses DKMS so modules are rebuilt on every kernel update.
    print_status "Installing nvidia-open (DKMS) + utilities..."
    arch-chroot /mnt pacman -S --noconfirm \
        nvidia-open \
        nvidia-utils \
        nvidia-settings \
        lib32-nvidia-utils \
        egl-wayland        # required for NVIDIA Wayland compositing in GNOME

    print_status "Configuring NVIDIA modprobe options..."
    cat > /mnt/etc/modprobe.d/nvidia.conf << 'EOF'
# Enable dynamic power management (RTX 5090 supports fine-grained D3)
options nvidia NVreg_DynamicPowerManagement=0x02
# Preserve VRAM allocations across suspend/resume
options nvidia NVreg_PreserveVideoMemoryAllocations=1
# Required for Wayland / GBM buffer allocation with GNOME Mutter
options nvidia-drm modeset=1 fbdev=1
EOF

    # ── DKMS module signing for Secure Boot ──────────────────────────────────
    # Problem: nvidia-open builds DKMS modules. Secure Boot requires ALL
    # kernel modules to be signed with a trusted key. sbctl signs EFI
    # binaries (vmlinuz, bootloader) but NOT kernel modules.
    #
    # Solution: Configure DKMS to sign each module it builds using the
    # same db.key that sbctl will enroll. The public cert (db.pem) is
    # enrolled into the UEFI Secure Boot db, so the firmware trusts it.
    #
    # NOTE: sbctl stores keys at /usr/share/secureboot/keys/db/
    # They are created by 'sbctl create-keys' which runs at first boot.
    # We therefore write a sign_helper that is evaluated lazily (at DKMS
    # build time, after keys exist), not during this install script.

    print_status "Configuring DKMS to sign NVIDIA modules for Secure Boot..."

    cat > /mnt/etc/dkms/sign_helper.sh << 'EOF'
#!/bin/sh
# Called by DKMS to sign each built module.
# Arguments: $1 = kernel version, $2 = module path
KEY="/usr/share/secureboot/keys/db/db.key"
CERT="/usr/share/secureboot/keys/db/db.pem"

if [[ ! -f "$KEY" || ! -f "$CERT" ]]; then
    echo "WARNING: sbctl keys not found at $KEY / $CERT"
    echo "Run 'sbctl create-keys' then rebuild DKMS modules with:"
    echo "  sudo dkms autoinstall"
    exit 0   # non-fatal during initial install before keys are created
fi

/usr/lib/modules/"$1"/build/scripts/sign-file sha512 "$KEY" "$CERT" "$2"
EOF
    chmod +x /mnt/etc/dkms/sign_helper.sh

    # Tell DKMS to use the signing helper above
    cat >> /mnt/etc/dkms/framework.conf << 'EOF'

# Secure Boot module signing — uses sbctl db key
sign_tool="/etc/dkms/sign_helper.sh"
EOF

    print_success "NVIDIA drivers installed and DKMS signing configured"
    print_warning "NVIDIA modules will be signed automatically after 'sbctl create-keys' on first boot."
}

# ====
# SECURE BOOT — SELF-SIGNED (no Microsoft certificate required)
# ====
# Secure Boot explanation:
#   - You control the Platform Key (PK), Key Exchange Key (KEK), and db key.
#   - 'sbctl enroll-keys -m' also adds Microsoft's KEK and db certs.
#     This is OPTIONAL but recommended for hardware that checks for MS
#     signatures on UEFI option ROMs (some NICs, storage controllers).
#   - For a purely self-controlled machine, 'sbctl enroll-keys' without
#     -m is equally valid; remove -m below if you prefer that.
# ====

setup_secure_boot() {
    if [[ "$ENABLE_SECURE_BOOT" != "y" ]]; then
        print_status "Skipping Secure Boot setup (user choice)"
        return 0
    fi

    print_header "Secure Boot — Self-Signed Keys via sbctl"

    print_status "Installing sbctl..."
    arch-chroot /mnt pacman -S --noconfirm sbctl

    # We stage a post-first-boot script because the UEFI db can only be
    # written when the firmware is in Setup Mode (not from the live ISO).
    cat > /mnt/setup_secure_boot.sh << 'EOF'
#!/bin/bash
# Run this ONCE after first boot, while UEFI is still in Setup Mode.
# (In BIOS: Security → Secure Boot → Clear/Delete keys → Save → reboot)
set -euo pipefail

echo "=== Creating platform keys ==="
sbctl create-keys

echo "=== Enrolling keys (including Microsoft certs for HW compat) ==="
# Remove -m if you do NOT want Microsoft certificates enrolled.
sbctl enroll-keys -m

echo "=== Signing EFI binaries ==="
sbctl sign -s /boot/vmlinuz-linux
sbctl sign -s /boot/vmlinuz-linux-lts
sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI

echo "=== Rebuilding DKMS modules so NVIDIA modules get signed ==="
dkms autoinstall

echo "=== Verifying signed files ==="
sbctl verify

echo ""
echo "Secure Boot setup complete."
echo "Now enable Secure Boot in your BIOS/UEFI and reboot."
echo "Verify afterwards with: sbctl status"
EOF

    # Auto-signing pacman hook (keeps binaries signed after updates)
    mkdir -p /mnt/etc/pacman.d/hooks
    cat > /mnt/etc/pacman.d/hooks/95-secureboot.hook << 'EOF'
[Trigger]
Operation=Install
Operation=Upgrade
Type=Package
Target=linux
Target=linux-lts
Target=systemd
Target=nvidia-open

[Action]
Description=Signing kernel, bootloader and NVIDIA modules for Secure Boot
When=PostTransaction
Exec=/bin/sh -c 'sbctl sign-all && dkms autoinstall'
Depends=sbctl
EOF

    chmod +x /mnt/setup_secure_boot.sh

    print_success "Secure Boot scripts staged."
    print_warning "After first boot: run 'sudo /setup_secure_boot.sh'"
    print_warning "Then re-enable Secure Boot in BIOS/UEFI."
}

# ====
# FIREWALL
# ====

configure_firewall() {
    print_header "Configuring Firewall"

    arch-chroot /mnt pacman -S --noconfirm ufw
    arch-chroot /mnt ufw --force enable
    arch-chroot /mnt ufw default deny incoming
    arch-chroot /mnt ufw default allow outgoing
    arch-chroot /mnt systemctl enable ufw

    print_success "Firewall configured and enabled"
}

# ====
# HARDWARE-SPECIFIC CONFIGURATION
# ====

install_nvidia_drivers_full() {
    install_nvidia_drivers
}

configure_mediatek_workaround() {
    print_header "MediaTek MT7927 Wireless Configuration"

    arch-chroot /mnt pacman -S --noconfirm \
        wireless_tools wpa_supplicant iw linux-firmware

    if arch-chroot /mnt pacman -S --noconfirm linux-firmware-mediatek 2>/dev/null; then
        print_success "MediaTek firmware installed"
    else
        print_warning "linux-firmware-mediatek not available in repos — will rely on linux-firmware"
    fi

    cat > "/mnt/home/${USERNAME}/WIRELESS_INFO.txt" << 'EOF'
MEDIATEK MT7927 WIRELESS CARD COMPATIBILITY NOTICE
====================================================

Your system contains a MediaTek MT7927 wireless card.

CURRENT STATUS:
- Basic MediaTek firmware has been installed (linux-firmware)
- The mt76 driver may provide limited support
- Full functionality is not guaranteed on kernel 7.x

SOLUTIONS IF WIFI DOESN'T WORK:
1. Replace the M.2 card with a supported model:
   - Intel AX210  (Wi-Fi 6E + Bluetooth 5.2)  ← RECOMMENDED
   - Intel AX200  (Wi-Fi 6  + Bluetooth 5.1)
   - Qualcomm Atheros ath10k/ath11k cards

2. Use a USB wireless adapter with MediaTek MT7612/MT7915 chip.

3. Check for kernel/firmware updates:
   - sudo pacman -Syu
   - dmesg | grep -i mediatek

TESTING:
  ip link show
  sudo iw dev wlan0 scan | grep SSID
  nmcli device wifi connect "SSID" password "PASSWORD"

For immediate connectivity use an Ethernet connection.
EOF

    chown "${USERNAME}:${USERNAME}" "/mnt/home/${USERNAME}/WIRELESS_INFO.txt"

    print_success "MediaTek WiFi configuration completed"
}

configure_norwegian_keyboard() {
    print_header "Configuring Norwegian Keyboard Layout"

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

# FIX: Removed zenpower3-dkms from here — it is AUR-only and will fail
# with a plain 'pacman -S'. It is installed later via yay in install_aur_packages.
configure_amd_optimizations() {
    print_header "Configuring AMD Ryzen 9950X Optimizations"

    print_status "Installing AMD microcode (already in base, verifying)..."
    arch-chroot /mnt pacman -S --noconfirm amd-ucode

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

    print_success "AMD Ryzen 9950X optimizations configured"
}

# ====
# DESKTOP ENVIRONMENT — GNOME 50+
# ====

install_desktop_environment() {
    print_header "Installing GNOME 50+ Desktop Environment"

    print_status "Installing GNOME and supporting packages..."
    arch-chroot /mnt pacman -S --noconfirm "${DESKTOP_PACKAGES[@]}"

    print_status "Enabling GDM display manager..."
    arch-chroot /mnt systemctl enable gdm

    # Enable PipeWire for the user session globally
    # (--global sets the preset for all future user sessions)
    print_status "Enabling PipeWire user services..."
    arch-chroot /mnt systemctl --global enable \
        pipewire.socket \
        pipewire-pulse.socket \
        wireplumber.service

    print_success "GNOME desktop environment installed"
}

# ====
# PACKAGE INSTALLATION
# ====

install_development_tools() {
    if [[ "$INSTALL_DEVELOPMENT_TOOLS" != "y" ]]; then
        print_status "Skipping development tools (user choice)"
        return 0
    fi

    print_header "Installing Development Environment"

    arch-chroot /mnt pacman -S --noconfirm "${DEVELOPMENT_PACKAGES[@]}"

    print_status "Enabling Docker service..."
    arch-chroot /mnt systemctl enable docker
    arch-chroot /mnt usermod -aG docker "$USERNAME"

    # FIX: rustup default stable needs network AND the rustup binary in PATH.
    # It is deferred to first login via the setup-dev-env.sh script instead.
    print_warning "Rust toolchain will be configured on first login via setup-dev-env.sh"

    print_success "Development environment installed"
}

install_applications() {
    print_header "Installing Applications"

    arch-chroot /mnt pacman -S --noconfirm "${APPLICATION_PACKAGES[@]}"

    # FIX: flatpak is not a systemd service — enabling it as one causes an
    # error. Flatpak is a CLI tool; no service enable is needed.
    print_status "Flatpak installed — no service enable required."

    print_success "Applications installed"
}

install_aur_helper() {
    print_header "Installing AUR Helper (yay)"

    # FIX: 'arch-chroot /mnt sudo -u ...' is unreliable because sudo may not
    # be configured correctly at this stage in the chroot. Use 'runuser' instead.
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
    arch-chroot /mnt runuser -u "$USERNAME" -- /install_yay.sh
    rm /mnt/install_yay.sh

    print_success "yay AUR helper installed"
}

install_aur_packages() {
    print_header "Installing AUR Packages"

    # FIX: zenpower3-dkms moved here (AUR-only package).
    cat > /mnt/install_aur.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# AMD Ryzen power monitoring (was incorrectly in pacman list before)
yay -S --noconfirm zenpower3-dkms

# Development tools
yay -S --noconfirm visual-studio-code-bin brave-bin postman-bin

# System utilities
yay -S --noconfirm timeshift auto-cpufreq

echo "AUR packages installed successfully."
EOF

    chmod +x /mnt/install_aur.sh
    arch-chroot /mnt runuser -u "$USERNAME" -- /install_aur.sh
    rm /mnt/install_aur.sh

    print_success "AUR packages installed"
}

# ====
# SYSTEM OPTIMIZATION
# ====

optimize_system() {
    print_header "Optimizing System"

    # Enable multilib (Steam, Wine, lib32-*)
    sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf

    # FIX: Escape the $ in $(nproc) so it is NOT expanded by the shell
    # running this installer but IS evaluated each time make runs.
    sed -i 's/^#MAKEFLAGS="-j2"$/MAKEFLAGS="-j\$(nproc)"/' /mnt/etc/makepkg.conf
    sed -i 's/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -z - --threads=0)/' /mnt/etc/makepkg.conf

    # Faster parallel downloads
    sed -i 's/^#ParallelDownloads = 5$/ParallelDownloads = 10/' /mnt/etc/pacman.conf

    # SSD TRIM
    if [[ "$SELECTED_DISK" =~ nvme ]] || [[ "$SELECTED_DISK" =~ ssd ]]; then
        print_status "Enabling SSD TRIM timer..."
        arch-chroot /mnt systemctl enable fstrim.timer
    fi

    # FIX: configure_amd_optimizations called only once (it was duplicated before)
    configure_amd_optimizations

    print_success "System optimizations applied"
}

# ====
# USER SCRIPTS
# ====

create_user_scripts() {
    print_header "Creating User Scripts"

    cat > "/mnt/home/${USERNAME}/update-system.sh" << 'EOF'
#!/bin/bash
# Full system update (official + AUR)
set -euo pipefail

echo "Updating official packages..."
sudo pacman -Syu

echo "Updating AUR packages..."
yay -Sua

echo "Cleaning package cache..."
sudo pacman -Sc --noconfirm

echo "Removing orphaned packages..."
mapfile -t orphans < <(pacman -Qtdq 2>/dev/null)
if [[ ${#orphans[@]} -gt 0 ]]; then
    sudo pacman -Rns "${orphans[@]}" --noconfirm
fi

echo "System update completed!"
EOF

    cat > "/mnt/home/${USERNAME}/setup-dev-env.sh" << 'EOF'
#!/bin/bash
# Run once after first login to finish development environment setup.
set -euo pipefail

echo "Installing Rust stable toolchain via rustup..."
rustup default stable

echo "Installing Node Version Manager (nvm)..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

echo "Installing pyenv..."
curl https://pyenv.run | bash

echo ""
echo "Set up Git identity:"
echo "  git config --global user.name  'Your Name'"
echo "  git config --global user.email 'you@example.com'"
echo ""
echo "Restart your shell to activate nvm and pyenv."
EOF

    chmod +x "/mnt/home/${USERNAME}/update-system.sh"
    chmod +x "/mnt/home/${USERNAME}/setup-dev-env.sh"
    chown "${USERNAME}:${USERNAME}" \
        "/mnt/home/${USERNAME}/update-system.sh" \
        "/mnt/home/${USERNAME}/setup-dev-env.sh"

    print_success "User scripts created"
}

# FIX: Heredoc now uses unquoted EOF so $(date) expands at script runtime.
create_post_install_info() {
    print_header "Creating Post-Installation Guide"

    local install_date
    install_date=$(date)

    cat > "/mnt/home/${USERNAME}/POST_INSTALL_GUIDE.md" << EOF
# Arch Linux Post-Installation Guide

## System Information
- **Installation Date**: ${install_date}
- **Kernel**: Linux (latest stable 7.x) with LTS fallback
- **Bootloader**: systemd-boot
- **Desktop Environment**: GNOME 50+
- **Graphics**: NVIDIA RTX 5090 with nvidia-open (DKMS)
- **CPU**: AMD Ryzen 9 9950X with performance governor

## First Boot Checklist

### 1. Secure Boot (if enabled)
\`\`\`bash
# Put UEFI into Setup Mode first (clear existing keys in BIOS)
sudo /setup_secure_boot.sh
# Then re-enable Secure Boot in BIOS and reboot
sbctl status   # should show: Secure Boot enabled
\`\`\`

### 2. WiFi (if MediaTek MT7927 is not working)
See ~/WIRELESS_INFO.txt — recommend replacing with Intel AX210.

### 3. Finish dev environment
\`\`\`bash
~/setup-dev-env.sh
\`\`\`

### 4. Check NVIDIA status
\`\`\`bash
nvidia-smi
# If Secure Boot is enabled and modules aren't signed yet:
sudo dkms autoinstall
\`\`\`

### 5. GNOME initial setup
- Run GNOME Settings → Region & Language → set Norwegian keyboard
- Settings → Displays → configure multi-monitor layout
- Extensions: install GNOME Shell Extensions app via Flatpak

## Regular Maintenance
\`\`\`bash
~/update-system.sh
\`\`\`
EOF

    chown "${USERNAME}:${USERNAME}" "/mnt/home/${USERNAME}/POST_INSTALL_GUIDE.md"

    print_success "Post-installation guide created"
}

# ====
# MAIN
# ====

main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  ${SCRIPT_NAME} v${SCRIPT_VERSION}  ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    print_warning "This script will COMPLETELY ERASE the selected disk."
    if ! confirm "Ready to begin installation?" "n"; then
        echo "Installation cancelled."
        exit 0
    fi

    # Validation
    check_uefi_boot
    check_internet_connection
    update_system_clock

    # Input
    get_user_input
    select_disk

    # Disk
    prepare_disk
    format_partitions
    mount_partitions

    # Base system
    install_base_system
    configure_system

    # Hardware
    install_nvidia_drivers
    configure_mediatek_workaround
    configure_norwegian_keyboard

    # Desktop (GNOME 50+)
    install_desktop_environment

    # Optional dev tools
    install_development_tools

    # Applications
    install_applications

    # AUR
    install_aur_helper
    install_aur_packages

    # Optimizations (includes AMD setup — called ONCE here)
    optimize_system

    # Security
    setup_secure_boot
    configure_firewall

    # User scripts and docs
    create_user_scripts
    create_post_install_info

    print_header "Installation Complete"
    print_success "Arch Linux with GNOME 50+ has been installed!"
    echo
    print_status "Next steps:"
    echo "  1. Remove the installation media"
    echo "  2. Reboot: reboot"
    echo "  3. On first boot, run: sudo /setup_secure_boot.sh"
    echo "     (if Secure Boot was selected and UEFI is in Setup Mode)"
    echo "  4. Run ~/setup-dev-env.sh to finish the dev environment"
    echo "  5. Read ~/POST_INSTALL_GUIDE.md for full instructions"
    echo
}

main "$@"
