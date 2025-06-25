#!/bin/bash
set -e

# Arch Linux Automated Install Script
# Hardware: AMD Ryzen 9 9950X, ASRock X670 Taichi, RTX 5090
# Features: Secure Boot, NVIDIA Open, KDE Wayland, Thunderbolt, TPM, Norwegian Keyboard

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DISK="/dev/nvme0n1"
HOSTNAME="archbox"
TIMEZONE="Europe/Oslo"
KEYMAP="no"
LOCALE="nb_NO.UTF-8"
SWAP_SIZE="4G"

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

confirm() {
    echo -e "${BLUE}[CONFIRM]${NC} $1"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "Aborted by user"
    fi
}

check_uefi() {
    if [ ! -d /sys/firmware/efi ]; then
        error "System not booted in UEFI mode. Please enable UEFI in BIOS."
    fi
    log "UEFI boot confirmed"
}

check_internet() {
    if ! ping -c 1 archlinux.org &> /dev/null; then
        error "No internet connection. Please connect to internet first."
    fi
    log "Internet connection confirmed"
}

setup_keyboard() {
    log "Setting up Norwegian keyboard"
    loadkeys no
}

setup_time() {
    log "Setting up NTP"
    timedatectl set-ntp true
}

partition_disk() {
    log "Partitioning disk: $DISK"
    warn "This will DESTROY ALL DATA on $DISK"
    confirm "Proceed with partitioning?"

    # Wipe disk
    sgdisk --zap-all $DISK

    # Create partitions
    sgdisk --new=1:0:+512M --typecode=1:EF00 --change-name=1:"EFI system" $DISK
    sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:"root" $DISK

    # Inform kernel of partition changes
    partprobe $DISK
    sleep 2

    log "Partitioning complete"
}

format_partitions() {
    log "Formatting partitions"
    mkfs.fat -F32 ${DISK}p1
    mkfs.ext4 ${DISK}p2
    log "Formatting complete"
}

mount_partitions() {
    log "Mounting partitions"
    mount ${DISK}p2 /mnt
    mkdir -p /mnt/boot
    mount ${DISK}p1 /mnt/boot
    log "Partitions mounted"
}

install_base() {
    log "Installing base system"
    pacstrap /mnt base base-devel linux-lts linux-firmware amd-ucode grub efibootmgr sbctl nano networkmanager
    log "Base system installed"
}

generate_fstab() {
    log "Generating fstab"
    genfstab -U /mnt >> /mnt/etc/fstab
    log "fstab generated"
}

create_swapfile() {
    log "Creating ${SWAP_SIZE} swapfile"
    fallocate -l $SWAP_SIZE /mnt/swapfile
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile
    # Add swapfile to fstab (fstab already exists from generate_fstab)
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
    log "Swapfile created and activated"
}

configure_system() {
    log "Configuring system in chroot"

    # Create the chroot configuration script
    cat > /mnt/configure_system.sh << 'CHROOT_EOF'
#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log() { echo -e "${GREEN}[CHROOT]${NC} $1"; }
warn() { echo -e "${YELLOW}[CHROOT-WARN]${NC} $1"; }

# Timezone and clock
log "Setting timezone"
ln -sf /usr/share/zoneinfo/Europe/Oslo /etc/localtime
hwclock --systohc

# Locale
log "Setting up locale"
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#nb_NO.UTF-8/nb_NO.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=nb_NO.UTF-8" > /etc/locale.conf
echo "KEYMAP=no" > /etc/vconsole.conf

# Hostname
log "Setting hostname"
echo "archbox" > /etc/hostname

# Root password
log "Setting root password"
echo "root:password123" | chpasswd
warn "Default root password is 'password123' - CHANGE THIS AFTER FIRST BOOT!"

# Install GRUB
log "Installing GRUB"
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable multilib
log "Enabling multilib"
sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm

# Install NVIDIA
log "Installing NVIDIA Open driver"
pacman -S --noconfirm nvidia-open nvidia-utils lib32-nvidia-utils

# Configure GRUB for NVIDIA
log "Configuring GRUB for NVIDIA"
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& nvidia_drm.modeset=1/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Configure initramfs for NVIDIA
log "Configuring initramfs for NVIDIA"
sed -i 's/^MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Secure Boot setup
log "Setting up Secure Boot"
sbctl create-keys

# Try to enroll keys, but don't fail if it doesn't work
if sbctl enroll-keys; then
    log "Secure Boot keys enrolled successfully"
else
    warn "Key enrollment failed. You may need to clear Microsoft keys in BIOS first."
    warn "Go to BIOS -> Secure Boot -> Custom -> Clear All Keys, then run 'sbctl enroll-keys' after first boot."
fi

# Sign EFI binaries
log "Signing EFI binaries"
sbctl sign -s /boot/EFI/GRUB/grubx64.efi
sbctl sign -s /boot/vmlinuz-linux-lts

# Sign NVIDIA modules for all installed kernels
log "Signing NVIDIA kernel modules"
signed_count=0
for kver in /usr/lib/modules/*; do
    if [ -d "$kver" ]; then
        kver_name=$(basename "$kver")
        log "Checking kernel version: $kver_name"
        for mod in "$kver"/kernel/drivers/video/nvidia*.ko*; do
            if [ -e "$mod" ]; then
                log "Signing module: $(basename "$mod") for kernel $kver_name"
                sbctl sign -s "$mod"
                ((signed_count++))
            fi
        done
    fi
done

if [ $signed_count -eq 0 ]; then
    warn "No NVIDIA modules found to sign. This might be normal if modules aren't built yet."
    warn "After first boot, run: sudo mkinitcpio -P && sudo sbctl sign -s /usr/lib/modules/*/kernel/drivers/video/nvidia*.ko*"
else
    log "Signed $signed_count NVIDIA modules"
fi

# Create pacman hooks for auto-signing
log "Creating pacman hooks for auto-signing"
mkdir -p /etc/pacman.d/hooks

cat > /etc/pacman.d/hooks/99-nvidia-sbctl.hook << 'HOOK_EOF'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/kernel/drivers/video/nvidia*.ko*

[Action]
Description = Signing NVIDIA kernel modules with sbctl
When = PostTransaction
Exec = /bin/sh -c 'for kver in /usr/lib/modules/*; do for mod in "$kver"/kernel/drivers/video/nvidia*.ko*; do [ -e "$mod" ] && sbctl sign -s "$mod"; done; done'
HOOK_EOF

cat > /etc/pacman.d/hooks/99-sbctl.hook << 'HOOK_EOF'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = vmlinuz-linux-lts

[Action]
Description = Signing kernel with sbctl
When = PostTransaction
Exec = /usr/bin/sbctl sign -s /boot/vmlinuz-linux-lts
HOOK_EOF

# Install KDE and other packages
log "Installing KDE, Wayland, and other packages"
pacman -S --noconfirm plasma kde-applications plasma-wayland-session sddm xorg-xwayland networkmanager bolt

# Enable services
log "Enabling services"
systemctl enable sddm
systemctl enable NetworkManager
systemctl enable bolt

log "Chroot configuration complete"
CHROOT_EOF

    chmod +x /mnt/configure_system.sh
    arch-chroot /mnt ./configure_system.sh
    rm /mnt/configure_system.sh

    log "System configuration complete"
}

cleanup() {
    log "Cleaning up and unmounting"
    umount -R /mnt 2>/dev/null || true
}

main() {
    log "Starting Arch Linux automated installation"
    log "Target hardware: AMD Ryzen 9 9950X, ASRock X670 Taichi, RTX 5090"

    confirm "This script will install Arch Linux with Secure Boot, NVIDIA, KDE, and Thunderbolt support"

    check_uefi
    check_internet
    setup_keyboard
    setup_time
    partition_disk
    format_partitions
    mount_partitions
    install_base
    generate_fstab
    create_swapfile  # Now called after fstab is generated
    configure_system

    log "Installation complete!"
    echo
    echo -e "${GREEN}=== POST-INSTALL INSTRUCTIONS ===${NC}"
    echo "1. Reboot the system"
    echo "2. Go to BIOS and enable Secure Boot"
    echo "3. If Secure Boot fails, go to BIOS -> Secure Boot -> Custom -> Clear All Keys"
    echo "4. Boot into Arch and run: sudo sbctl enroll-keys"
    echo "5. Change root password from default 'password123'"
    echo "6. Create a user account: useradd -m -G wheel username"
    echo "7. Set user password: passwd username"
    echo "8. Enable sudo: visudo (uncomment %wheel ALL=(ALL:ALL) ALL)"
    echo
    echo -e "${YELLOW}WARNING: Default root password is 'password123' - CHANGE THIS!${NC}"
    echo
    confirm "Reboot now?"
    reboot
}

# Trap to cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
