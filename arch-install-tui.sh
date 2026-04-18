#!/bin/bash
# ================================================================
#  Arch Linux GNOME — Graphical TUI Installer
#  Uses 'dialog' for a full graphical terminal interface.
#  dialog is pre-installed on the Arch Linux live ISO.
#
#  Usage:
#    chmod +x arch-install-tui.sh
#    ./arch-install-tui.sh
#
#  Navigation:
#    Tab / Arrow keys — move between buttons/fields
#    Enter            — confirm / select
#    Esc              — go back / cancel
# ================================================================

# Do NOT use -e globally; dialog returns non-zero on Cancel/ESC
# and we handle those explicitly.
set -uo pipefail

# ── Constants ────────────────────────────────────────────────────────────────

readonly VERSION="1.0.0"
readonly BACKTITLE="  Arch Linux  ∙  GNOME 50+  ∙  RTX 5090  ∙  Ryzen 9950X  ∙  v${VERSION}  "
readonly LOG_FILE="/tmp/arch-install.log"

# ── Configuration state (populated by wizard) ────────────────────────────────

CFG_USERNAME=""
CFG_HOSTNAME=""
CFG_ROOT_PASS=""
CFG_USER_PASS=""
CFG_DISK=""
CFG_TIMEZONE="Europe/Oslo"
CFG_SECURE_BOOT="yes"
CFG_DEV_TOOLS="yes"
CFG_WIPE_CONFIRMED="no"

# ── Package lists (same as arch-install-fixed.sh) ────────────────────────────

BASE_PACKAGES="base base-devel linux linux-lts linux-firmware amd-ucode \
systemd efibootmgr networkmanager sudo nano vim git wget curl reflector \
dkms linux-headers linux-lts-headers"

DESKTOP_PACKAGES="gnome gnome-extra gdm xdg-desktop-portal-gnome \
xdg-user-dirs xorg-xwayland mesa vulkan-radeon lib32-mesa \
pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
pavucontrol alsa-utils ttf-dejavu ttf-liberation noto-fonts \
noto-fonts-emoji ttf-roboto ttf-opensans adobe-source-code-pro-fonts"

NVIDIA_PACKAGES="nvidia-open nvidia-utils nvidia-settings lib32-nvidia-utils egl-wayland"

DEV_PACKAGES="cmake make gcc clang gdb valgrind strace python python-pip \
python-virtualenv nodejs npm go rust rustup jdk-openjdk maven \
postgresql-libs mariadb sqlite redis docker docker-compose podman \
git-lfs meson ninja flatpak"

APP_PACKAGES="firefox thunderbird libreoffice-fresh evince gnome-text-editor \
gnome-calculator file-roller baobab gnome-screenshot mpv vlc gimp \
inkscape kdenlive audacity obs-studio neovim emacs htop btop neofetch \
tree unzip p7zip rsync tmux zsh fish flameshot eza bat ripgrep fd \
fzf zoxide starship steam lutris wine gamemode mangohud keepassxc \
ufw fail2ban clamav rkhunter nmap wireshark-qt openvpn wireguard-tools"

SBCTL_PACKAGES="sbctl"

# ─────────────────────────────────────────────────────────────────────────────
#  DIALOG WRAPPER
# ─────────────────────────────────────────────────────────────────────────────
# dlg: runs dialog, captures result in $DLGRESULT, returns dialog's exit code.
# Usage:  dlg --msgbox "..." || return
#         echo "$DLGRESULT"     — holds user input / selection

DLGRESULT=""

dlg() {
    local tmpfile
    tmpfile=$(mktemp /tmp/dlg-XXXXXX)
    dialog \
        --colors \
        --backtitle "$BACKTITLE" \
        "$@" 2>"$tmpfile"
    local rc=$?
    DLGRESULT=$(cat "$tmpfile")
    rm -f "$tmpfile"
    return $rc
}

# ── Logging ──────────────────────────────────────────────────────────────────

log()  { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }
loge() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >> "$LOG_FILE"; }

# Run a command and log it; show an error dialog on failure.
run() {
    log "RUN: $*"
    if ! "$@" >> "$LOG_FILE" 2>&1; then
        loge "Command failed: $*"
        dlg --title " ✗ Error " \
            --msgbox "\nThe following command failed:\n\n  $*\n\nSee the log for details:\n  $LOG_FILE" \
            12 68
        return 1
    fi
}

# ── Cleanup ───────────────────────────────────────────────────────────────────

cleanup() {
    dialog --clear
    if mountpoint -q /mnt 2>/dev/null; then
        umount -R /mnt 2>/dev/null || true
    fi
    log "Installer exited."
}
trap cleanup EXIT

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 0 — WELCOME
# ─────────────────────────────────────────────────────────────────────────────

screen_welcome() {
    dlg \
        --title " Welcome " \
        --yes-label " Begin " \
        --no-label "  Exit  " \
        --yesno \
"
\ZbArch Linux — GNOME 50+ Installer\ZB
\Z6──────────────────────────────────\Zn

This wizard will guide you through a complete installation of
Arch Linux with the GNOME 50 desktop environment, optimised for:

  \Z3●\Zn  AMD Ryzen 9 9950X
  \Z3●\Zn  NVIDIA RTX 5090  (nvidia-open DKMS drivers)
  \Z3●\Zn  ASRock X670E Taichi
  \Z3●\Zn  Norwegian keyboard layout
  \Z3●\Zn  Secure Boot via sbctl (self-signed, no MS cert required)

\Z1WARNING:\Zn  The selected disk will be \ZbCOMPLETELY ERASED\ZB.
            Make sure you have backed up any important data.

\Z6──────────────────────────────────\Zn
Press \Zb Begin \ZB to start or \Zb Exit \ZB to quit.
" \
        18 68 || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 1 — PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

screen_preflight() {
    local checks=""
    local all_ok=1

    # UEFI check
    if [[ -d /sys/firmware/efi ]]; then
        checks+="\Z2  ✔\Zn  UEFI boot mode detected\n"
    else
        checks+="\Z1  ✗\Zn  Not booted in UEFI mode — check BIOS settings\n"
        all_ok=0
    fi

    # Internet check
    if ping -c 1 -W 3 archlinux.org &>/dev/null 2>&1; then
        checks+="\Z2  ✔\Zn  Internet connection available\n"
    else
        checks+="\Z1  ✗\Zn  No internet connection — configure network first\n"
        all_ok=0
    fi

    # dialog availability
    if command -v dialog &>/dev/null; then
        checks+="\Z2  ✔\Zn  dialog is installed\n"
    else
        checks+="\Z1  ✗\Zn  dialog not found (pacman -S dialog)\n"
        all_ok=0
    fi

    # Sync clock
    timedatectl set-ntp true &>/dev/null || true
    checks+="\Z2  ✔\Zn  System clock synchronised\n"

    if [[ $all_ok -eq 0 ]]; then
        dlg \
            --title " ✗ Pre-flight Checks Failed " \
            --msgbox "\nOne or more checks failed:\n\n${checks}\nPlease resolve the issues above and re-run the installer." \
            16 64
        return 1
    fi

    dlg \
        --title " ✔ Pre-flight Checks " \
        --msgbox "\nAll systems ready:\n\n${checks}\nPress Enter to continue." \
        14 60
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 2 — USER ACCOUNT
# ─────────────────────────────────────────────────────────────────────────────

screen_user_account() {
    while true; do
        # Mixed form: fields 0=normal, 1=normal, 2=password, 3=password
        dlg \
            --title " User Account " \
            --mixedform \
"
\ZbCreate your user account and set passwords.\ZB

Username must be lowercase, starting with a letter.
Passwords must be at least 8 characters.
" \
            16 64 5 \
            "Username    :"  1 1  "$CFG_USERNAME"    1 16  28 32  0 \
            "Hostname    :"  2 1  "$CFG_HOSTNAME"    2 16  28 63  0 \
            "Root password :" 3 1 ""                 3 16  28 64  1 \
            "Root confirm  :" 4 1 ""                 4 16  28 64  1 \
            "User password :" 5 1 ""                 5 16  28 64  1 \
            || return 1

        # Parse form output (one value per line)
        local fields=()
        while IFS= read -r line; do
            fields+=("$line")
        done <<< "$DLGRESULT"

        local uname="${fields[0]:-}"
        local hname="${fields[1]:-}"
        local rpass="${fields[2]:-}"
        local rpass2="${fields[3]:-}"
        local upass="${fields[4]:-}"

        # Validation
        local errs=""
        [[ ! "$uname" =~ ^[a-z_][a-z0-9_-]*$ ]] && \
            errs+="\Z1  ✗\Zn  Invalid username (lowercase, starts with letter)\n"
        [[ ! "$hname" =~ ^[a-zA-Z0-9-]+$ ]] && \
            errs+="\Z1  ✗\Zn  Invalid hostname (letters, numbers, hyphens only)\n"
        [[ ${#rpass} -lt 8 ]] && \
            errs+="\Z1  ✗\Zn  Root password too short (minimum 8 characters)\n"
        [[ "$rpass" != "$rpass2" ]] && \
            errs+="\Z1  ✗\Zn  Root passwords do not match\n"
        [[ ${#upass} -lt 8 ]] && \
            errs+="\Z1  ✗\Zn  User password too short (minimum 8 characters)\n"

        if [[ -n "$errs" ]]; then
            dlg \
                --title " ✗ Validation Errors " \
                --msgbox "\nPlease fix the following:\n\n${errs}" \
                12 60
            CFG_USERNAME="$uname"
            CFG_HOSTNAME="$hname"
            continue
        fi

        CFG_USERNAME="$uname"
        CFG_HOSTNAME="$hname"
        CFG_ROOT_PASS="$rpass"
        CFG_USER_PASS="$upass"
        return 0
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 3 — TIMEZONE
# ─────────────────────────────────────────────────────────────────────────────

screen_timezone() {
    # Build a list of common European/American/Asian timezones for the menu
    local items=()
    local zone
    while IFS= read -r zone; do
        local tag="${zone}"
        local desc="${zone}"
        # Mark current selection
        if [[ "$zone" == "$CFG_TIMEZONE" ]]; then
            items+=("$tag" "← current" "on")
        else
            items+=("$tag" "" "off")
        fi
    done < <(timedatectl list-timezones 2>/dev/null | grep -E "^(Europe|America|Asia|Australia|Africa|Pacific)/" | head -120)

    dlg \
        --title " Timezone " \
        --default-item "$CFG_TIMEZONE" \
        --radiolist \
"
Select your timezone.
Use \Zb↑↓\ZB to navigate, \ZbSpace\ZB to select.
" \
        22 60 14 \
        "${items[@]}" \
        || return 1

    [[ -n "$DLGRESULT" ]] && CFG_TIMEZONE="$DLGRESULT"
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 4 — DISK SELECTION
# ─────────────────────────────────────────────────────────────────────────────

screen_disk() {
    # Build menu from available block devices
    local items=()
    local line
    while IFS= read -r line; do
        local dev model size
        dev=$(echo "$line"  | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        model=$(echo "$line"| awk '{$1=$2=""; print $0}' | xargs)
        items+=("/dev/${dev}" "${size}  ${model}")
    done < <(lsblk -d -o NAME,SIZE,MODEL | grep -E "^(nvme|sd|vd)" 2>/dev/null)

    if [[ ${#items[@]} -eq 0 ]]; then
        dlg \
            --title " ✗ No Disks Found " \
            --msgbox "\nNo suitable block devices were detected.\nCheck your hardware and try again." \
            8 54
        return 1
    fi

    dlg \
        --title " Disk Selection " \
        --menu \
"
\Z1WARNING: The selected disk will be COMPLETELY ERASED.\Zn

Choose the target installation disk:
" \
        16 68 6 \
        "${items[@]}" \
        || return 1

    CFG_DISK="$DLGRESULT"

    # Show disk details and get final confirmation
    local disk_info
    disk_info=$(lsblk "$CFG_DISK" 2>/dev/null || echo "(unable to read disk info)")

    dlg \
        --title " ⚠  Confirm Disk Wipe " \
        --defaultno \
        --yes-label "  ERASE & INSTALL  " \
        --no-label "  Go Back  " \
        --yesno \
"
\Z1This will PERMANENTLY DESTROY all data on:\Zn

  \Zb${CFG_DISK}\ZB

Disk information:
${disk_info}

\Z1There is NO undo. Are you absolutely sure?\Zn
" \
        16 68 || { CFG_DISK=""; return 1; }

    CFG_WIPE_CONFIRMED="yes"
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 5 — FEATURE SELECTION
# ─────────────────────────────────────────────────────────────────────────────

screen_features() {
    local sb_default="on"
    local dev_default="on"
    [[ "$CFG_SECURE_BOOT" == "no" ]] && sb_default="off"
    [[ "$CFG_DEV_TOOLS"  == "no" ]] && dev_default="off"

    dlg \
        --title " Feature Selection " \
        --checklist \
"
Select the components to install.
Use \ZbSpace\ZB to toggle, \ZbEnter\ZB to confirm.

All selections include: GNOME 50+, NVIDIA drivers,
AMD optimisations, Norwegian keyboard, firewall.
" \
        16 68 4 \
        "SECURE_BOOT"  "Secure Boot setup (sbctl, self-signed keys)"      "$sb_default"  \
        "DEV_TOOLS"    "Full development environment (Docker, Rust, etc.)" "$dev_default" \
        "AUR_HELPER"   "Install yay AUR helper + AUR packages"             "on"           \
        "GAMING"       "Gaming stack (Steam, Lutris, Wine, MangoHud)"      "on"           \
        || return 1

    # Reset then re-apply from checklist output
    CFG_SECURE_BOOT="no"
    CFG_DEV_TOOLS="no"

    local sel="$DLGRESULT"
    [[ "$sel" == *"SECURE_BOOT"* ]] && CFG_SECURE_BOOT="yes"
    [[ "$sel" == *"DEV_TOOLS"*   ]] && CFG_DEV_TOOLS="yes"
    # GAMING and AUR_HELPER stored for install phase
    CFG_GAMING="no";    [[ "$sel" == *"GAMING"*     ]] && CFG_GAMING="yes"
    CFG_AUR="no";       [[ "$sel" == *"AUR_HELPER"* ]] && CFG_AUR="yes"
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 6 — SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

screen_summary() {
    local sb_label="No"
    local dev_label="No"
    [[ "$CFG_SECURE_BOOT" == "yes" ]] && sb_label="Yes (sbctl, self-signed)"
    [[ "$CFG_DEV_TOOLS"   == "yes" ]] && dev_label="Yes"

    dlg \
        --title " Installation Summary " \
        --yes-label "  ▶  Install Now  " \
        --no-label "  ◀  Go Back  " \
        --yesno \
"
Review your configuration before installation begins.

  \ZbUsername\ZB        :  ${CFG_USERNAME}
  \ZbHostname\ZB        :  ${CFG_HOSTNAME}
  \ZbTimezone\ZB        :  ${CFG_TIMEZONE}
  \ZbTarget disk\ZB     :  ${CFG_DISK}
  \ZbSecure Boot\ZB     :  ${sb_label}
  \ZbDev tools\ZB       :  ${dev_label}
  \ZbAUR helper\ZB      :  ${CFG_AUR}
  \ZbGaming stack\ZB    :  ${CFG_GAMING}
  \ZbKernel\ZB          :  linux (7.x) + linux-lts (fallback)
  \ZbDesktop\ZB         :  GNOME 50+  /  GDM  /  Wayland
  \ZbGraphics\ZB        :  NVIDIA RTX 5090 (nvidia-open DKMS)
  \ZbBootloader\ZB      :  systemd-boot
  \ZbKeyboard\ZB        :  Norwegian (no)

\Z1Once you press Install Now, the disk will be erased.\Zn
" \
        22 68 || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
#  INSTALLATION — HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Send a gauge progress update.
# Usage:  gauge_update <percent> <message>
gauge_update() {
    printf '%s\nXXX\n%s\nXXX\n' "$1" "$2"
}

# Partition naming helper (nvme uses p1/p2, sata uses 1/2)
efi_part() {
    if [[ "$CFG_DISK" =~ nvme ]]; then echo "${CFG_DISK}p1"
    else echo "${CFG_DISK}1"; fi
}
root_part() {
    if [[ "$CFG_DISK" =~ nvme ]]; then echo "${CFG_DISK}p2"
    else echo "${CFG_DISK}2"; fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  INSTALLATION STEPS
# ─────────────────────────────────────────────────────────────────────────────

step_partition() {
    log "=== PARTITIONING ==="
    umount -R /mnt 2>/dev/null || true
    run wipefs   -af "$CFG_DISK"
    run sgdisk   -Z  "$CFG_DISK"
    run sgdisk   -o  "$CFG_DISK"
    run sgdisk   -n 1:0:+1G  -t 1:ef00 -c 1:"EFI System"      "$CFG_DISK"
    run sgdisk   -n 2:0:0    -t 2:8300 -c 2:"Linux filesystem" "$CFG_DISK"
    run partprobe "$CFG_DISK"
    sleep 2
}

step_format() {
    log "=== FORMATTING ==="
    run mkfs.fat -F32 -n "EFI"  "$(efi_part)"
    run mkfs.ext4 -L  "ROOT"    "$(root_part)"
}

step_mount() {
    log "=== MOUNTING ==="
    run mount "$(root_part)" /mnt
    mkdir -p /mnt/boot
    run mount "$(efi_part)"  /mnt/boot
}

step_pacstrap() {
    log "=== PACSTRAP BASE ==="
    pacman -Sy --noconfirm >> "$LOG_FILE" 2>&1 || true
    # shellcheck disable=SC2086
    run pacstrap /mnt $BASE_PACKAGES
    run genfstab -U /mnt >> /mnt/etc/fstab
}

step_configure() {
    log "=== SYSTEM CONFIGURATION ==="
    cat > /mnt/do_configure.sh << CONF_EOF
#!/bin/bash
set -euo pipefail
TZ="\$1"; HN="\$2"; RP="\$3"; UN="\$4"; UP="\$5"

ln -sf "/usr/share/zoneinfo/\${TZ}" /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" >  /etc/locale.gen
echo "nb_NO.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=no"        > /etc/vconsole.conf

echo "\${HN}" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${HN}.localdomain \${HN}
HOSTS

# mkinitcpio: load AMD early, remove kms hook (conflicts with nvidia on 7.x)
sed -i 's/^MODULES=.*/MODULES=(amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sed -i 's/ kms//' /etc/mkinitcpio.conf
mkinitcpio -P

# systemd-boot
bootctl install
mkdir -p /boot/loader/entries
cat > /boot/loader/loader.conf << LDR
default arch.conf
timeout 3
console-mode max
editor no
LDR
cat > /boot/loader/entries/arch.conf << ARC
title   Arch Linux (kernel 7+)
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=LABEL=ROOT rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1
ARC
cat > /boot/loader/entries/arch-lts.conf << LTS
title   Arch Linux LTS (fallback)
linux   /vmlinuz-linux-lts
initrd  /amd-ucode.img
initrd  /initramfs-linux-lts.img
options root=LABEL=ROOT rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1
LTS

# Pacman hooks
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/nvidia.hook << NVH
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
Exec=/bin/sh -c 'while read -r trg; do case \\\$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'
NVH
cat > /etc/pacman.d/hooks/95-systemd-boot.hook << SDH
[Trigger]
Type=Package
Operation=Upgrade
Target=systemd
[Action]
Description=Upgrading systemd-boot...
When=PostTransaction
Exec=/usr/bin/systemctl restart systemd-boot-update.service
SDH

# Services
systemctl enable NetworkManager
systemctl enable gdm

# Wayland environment
cat > /etc/environment << ENV
GNOME_SESSION_TYPE=wayland
XDG_SESSION_TYPE=wayland
ENV

# Accounts
echo "root:\${RP}" | chpasswd
useradd -m -G wheel,audio,video,optical,storage,docker -s /bin/bash "\${UN}"
echo "\${UN}:\${UP}" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Pacman tuning
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
sed -i 's/^#ParallelDownloads = 5\$/ParallelDownloads = 10/' /etc/pacman.conf
sed -i 's/^#MAKEFLAGS="-j2"\$/MAKEFLAGS="-j\$(nproc)"/' /etc/makepkg.conf
CONF_EOF
    chmod +x /mnt/do_configure.sh
    run arch-chroot /mnt /do_configure.sh \
        "$CFG_TIMEZONE" "$CFG_HOSTNAME" \
        "$CFG_ROOT_PASS" "$CFG_USERNAME" "$CFG_USER_PASS"
    rm -f /mnt/do_configure.sh
}

step_nvidia() {
    log "=== NVIDIA RTX 5090 DRIVERS ==="
    # shellcheck disable=SC2086
    run arch-chroot /mnt pacman -S --noconfirm $NVIDIA_PACKAGES

    cat > /mnt/etc/modprobe.d/nvidia.conf << 'EOF'
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia-drm modeset=1 fbdev=1
EOF

    # DKMS signing helper for Secure Boot
    cat > /mnt/etc/dkms/sign_helper.sh << 'EOF'
#!/bin/sh
KEY="/usr/share/secureboot/keys/db/db.key"
CERT="/usr/share/secureboot/keys/db/db.pem"
if [[ ! -f "$KEY" || ! -f "$CERT" ]]; then
    echo "WARNING: sbctl keys not found — run 'sbctl create-keys' then 'dkms autoinstall'"
    exit 0
fi
/usr/lib/modules/"$1"/build/scripts/sign-file sha512 "$KEY" "$CERT" "$2"
EOF
    chmod +x /mnt/etc/dkms/sign_helper.sh
    echo 'sign_tool="/etc/dkms/sign_helper.sh"' >> /mnt/etc/dkms/framework.conf
}

step_desktop() {
    log "=== GNOME 50+ DESKTOP ==="
    # shellcheck disable=SC2086
    run arch-chroot /mnt pacman -S --noconfirm $DESKTOP_PACKAGES
    run arch-chroot /mnt systemctl --global enable \
        pipewire.socket pipewire-pulse.socket wireplumber.service

    # Norwegian keyboard for X11/Wayland
    mkdir -p /mnt/etc/X11/xorg.conf.d
    cat > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf << 'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "no"
    Option "XkbModel" "pc105"
EndSection
EOF
}

step_applications() {
    log "=== APPLICATIONS ==="
    local pkgs="$APP_PACKAGES"

    # Remove gaming packages if not selected
    if [[ "$CFG_GAMING" != "yes" ]]; then
        pkgs=$(echo "$pkgs" | tr ' ' '\n' | \
            grep -vE "^(steam|lutris|wine|winetricks|gamemode|mangohud)$" | \
            tr '\n' ' ')
    fi

    # shellcheck disable=SC2086
    run arch-chroot /mnt pacman -S --noconfirm $pkgs

    if [[ "$CFG_DEV_TOOLS" == "yes" ]]; then
        # shellcheck disable=SC2086
        run arch-chroot /mnt pacman -S --noconfirm $DEV_PACKAGES
        run arch-chroot /mnt systemctl enable docker
        run arch-chroot /mnt usermod -aG docker "$CFG_USERNAME"
    fi
}

step_amd_optimise() {
    log "=== AMD RYZEN 9950X OPTIMISATIONS ==="
    run arch-chroot /mnt systemctl enable fstrim.timer
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
    run arch-chroot /mnt systemctl enable cpu-performance.service
}

step_firewall() {
    log "=== FIREWALL ==="
    run arch-chroot /mnt pacman -S --noconfirm ufw
    arch-chroot /mnt ufw --force enable >> "$LOG_FILE" 2>&1 || true
    arch-chroot /mnt ufw default deny incoming >> "$LOG_FILE" 2>&1 || true
    arch-chroot /mnt ufw default allow outgoing >> "$LOG_FILE" 2>&1 || true
    run arch-chroot /mnt systemctl enable ufw
}

step_secure_boot() {
    if [[ "$CFG_SECURE_BOOT" != "yes" ]]; then return 0; fi
    log "=== SECURE BOOT PREP ==="
    run arch-chroot /mnt pacman -S --noconfirm sbctl

    # Auto-signing pacman hook
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
Description=Signing kernel/bootloader/NVIDIA for Secure Boot
When=PostTransaction
Exec=/bin/sh -c 'sbctl sign-all && dkms autoinstall'
Depends=sbctl
EOF

    # First-boot setup script
    cat > /mnt/setup_secure_boot.sh << 'EOF'
#!/bin/bash
# Run ONCE after first boot while UEFI is in Setup Mode.
# (BIOS: Security → Secure Boot → Clear keys → Save → reboot into installer)
set -euo pipefail
echo "Creating Secure Boot keys..."
sbctl create-keys
echo "Enrolling keys (+ Microsoft certs for hardware compat)..."
sbctl enroll-keys -m
echo "Signing EFI binaries..."
sbctl sign -s /boot/vmlinuz-linux
sbctl sign -s /boot/vmlinuz-linux-lts
sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
echo "Signing NVIDIA DKMS modules..."
dkms autoinstall
echo "Verifying..."
sbctl verify
echo ""
echo "Done. Enable Secure Boot in BIOS and reboot."
echo "Verify with: sbctl status"
EOF
    chmod +x /mnt/setup_secure_boot.sh
}

step_user_scripts() {
    log "=== USER SCRIPTS ==="
    local home="/mnt/home/${CFG_USERNAME}"
    local install_date
    install_date=$(date)

    cat > "${home}/update-system.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
echo "Updating official packages..."
sudo pacman -Syu
echo "Updating AUR packages..."
yay -Sua
echo "Removing orphaned packages..."
mapfile -t orphans < <(pacman -Qtdq 2>/dev/null)
[[ ${#orphans[@]} -gt 0 ]] && sudo pacman -Rns "${orphans[@]}" --noconfirm
echo "Done."
EOF

    cat > "${home}/setup-dev-env.sh" << 'EOF'
#!/bin/bash
echo "Installing Rust toolchain..."
rustup default stable
echo "Installing nvm..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
echo "Installing pyenv..."
curl https://pyenv.run | bash
echo "Done. Restart your shell."
EOF

    # Post-install guide — note: uses unquoted EOF so $install_date expands
    cat > "${home}/POST_INSTALL_GUIDE.md" << EOF
# Arch Linux Post-Installation Guide
Installed: ${install_date}

## Kernel
- linux (latest stable, 7.x)
- linux-lts (fallback)

## First boot checklist

### 1. Secure Boot (if enabled)
Put UEFI into Setup Mode (clear keys in BIOS), then:
\`\`\`bash
sudo /setup_secure_boot.sh
\`\`\`
Re-enable Secure Boot in BIOS, then verify: \`sbctl status\`

### 2. Dev environment
\`\`\`bash
~/setup-dev-env.sh
\`\`\`

### 3. NVIDIA check
\`\`\`bash
nvidia-smi
\`\`\`

### 4. WiFi
If MediaTek MT7927 is not working, replace card with Intel AX210.
See ~/WIRELESS_INFO.txt for details.
EOF

    # MediaTek notice
    cat > "${home}/WIRELESS_INFO.txt" << 'EOF'
MEDIATEK MT7927 WIRELESS CARD
==============================
Full Linux support is not guaranteed for this chipset.
RECOMMENDED: Replace with Intel AX210 (Wi-Fi 6E + BT 5.2).

If you want to test current driver status:
  dmesg | grep -i mediatek
  ip link show

Connect via Ethernet until WiFi is confirmed working.
EOF

    chmod +x "${home}/update-system.sh" "${home}/setup-dev-env.sh"
    chown -R "${CFG_USERNAME}:${CFG_USERNAME}" "${home}/"
}

step_aur() {
    if [[ "$CFG_AUR" != "yes" ]]; then return 0; fi
    log "=== AUR HELPER + AUR PACKAGES ==="
    cat > /mnt/install_yay.sh << 'EOF'
#!/bin/bash
set -euo pipefail
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay
yay -S --noconfirm zenpower3-dkms visual-studio-code-bin brave-bin postman-bin timeshift auto-cpufreq
EOF
    chmod +x /mnt/install_yay.sh
    run arch-chroot /mnt runuser -u "$CFG_USERNAME" -- /install_yay.sh
    rm -f /mnt/install_yay.sh
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 7 — INSTALLATION WITH PROGRESS GAUGE
# ─────────────────────────────────────────────────────────────────────────────

screen_install() {
    : > "$LOG_FILE"
    log "Installation started at $(date)"
    log "Config: user=$CFG_USERNAME host=$CFG_HOSTNAME disk=$CFG_DISK tz=$CFG_TIMEZONE"

    # We run installation steps in a subshell whose stdout feeds --gauge.
    # Each step calls gauge_update <pct> <message> then performs its work.
    # Errors are caught by the run() helper which appends to $LOG_FILE.

    (
        set +e  # don't abort the gauge subshell on errors; run() handles them

        gauge_update  2  "Partitioning ${CFG_DISK}..."
        step_partition

        gauge_update  6  "Formatting partitions..."
        step_format

        gauge_update  9  "Mounting partitions..."
        step_mount

        gauge_update 12  "Updating mirrors (reflector)..."
        reflector --country Norway,Germany --sort rate \
            --save /etc/pacman.d/mirrorlist >> "$LOG_FILE" 2>&1 || true

        gauge_update 15  "Installing base system (pacstrap)..."
        step_pacstrap

        gauge_update 35  "Configuring system (locale, bootloader, users)..."
        step_configure

        gauge_update 48  "Installing NVIDIA RTX 5090 drivers (DKMS)..."
        step_nvidia

        gauge_update 57  "Installing GNOME 50+ desktop environment..."
        step_desktop

        gauge_update 70  "Installing applications..."
        step_applications

        gauge_update 80  "Applying AMD Ryzen 9950X optimisations..."
        step_amd_optimise

        gauge_update 83  "Configuring firewall..."
        step_firewall

        gauge_update 86  "Configuring Secure Boot..."
        step_secure_boot

        gauge_update 90  "Creating user scripts and guides..."
        step_user_scripts

        gauge_update 93  "Installing AUR helper and AUR packages..."
        step_aur

        gauge_update 98  "Final sync..."
        sync

        gauge_update 100 "Installation complete!"
        log "Installation finished at $(date)"

    ) | dialog \
        --colors \
        --backtitle "$BACKTITLE" \
        --title " Installing Arch Linux " \
        --gauge \
"
  Installing Arch Linux GNOME on ${CFG_DISK}
  Full log available at: ${LOG_FILE}

  This will take 15–40 minutes depending on your internet speed.
  Please do not interrupt the process.
" \
        12 72 0
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 8 — COMPLETION
# ─────────────────────────────────────────────────────────────────────────────

screen_complete() {
    # Check if installation actually succeeded by looking at log for errors
    local had_errors=0
    grep -qi "ERROR:" "$LOG_FILE" 2>/dev/null && had_errors=1

    if [[ $had_errors -eq 1 ]]; then
        dlg \
            --title " ⚠  Installation Completed with Warnings " \
            --yes-label "  View Log  " \
            --no-label "  Reboot  " \
            --yesno \
"
Installation finished, but errors were detected.
Review the log before rebooting.

  Log file: ${LOG_FILE}

Press \ZbView Log\ZB to inspect, or \ZbReboot\ZB to continue anyway.
" \
            10 64
        if [[ $? -eq 0 ]]; then
            dlg \
                --title " Installation Log " \
                --textbox "$LOG_FILE" \
                22 80
        fi
    else
        dlg \
            --title " ✔  Installation Complete " \
            --msgbox \
"
\Z2Arch Linux GNOME has been installed successfully!\Zn

  Username :  ${CFG_USERNAME}
  Hostname :  ${CFG_HOSTNAME}
  Disk     :  ${CFG_DISK}

\ZbNext steps after reboot:\ZB
  1. Remove the installation media
  2. Boot into Arch Linux
  3. Log in as ${CFG_USERNAME}
  4. If Secure Boot was selected, run:
       sudo /setup_secure_boot.sh
  5. Run ~/setup-dev-env.sh for Rust/nvm/pyenv
  6. Read ~/POST_INSTALL_GUIDE.md

Press Enter to reboot.
" \
            20 64
    fi

    dlg \
        --title " Reboot " \
        --defaultno \
        --yesno \
"\nReboot now? (Make sure to remove the installation media first.)" \
        7 60 \
    && reboot
}

# ─────────────────────────────────────────────────────────────────────────────
#  WIZARD RUNNER — navigate forward/back through screens
# ─────────────────────────────────────────────────────────────────────────────

run_wizard() {
    local screens=(
        screen_welcome
        screen_preflight
        screen_user_account
        screen_timezone
        screen_disk
        screen_features
        screen_summary
    )
    local i=0
    local total=${#screens[@]}

    while true; do
        if [[ $i -ge $total ]]; then break; fi
        if [[ $i -lt 0 ]]; then i=0; fi

        # Run the screen function
        if "${screens[$i]}"; then
            (( i++ ))
        else
            # User pressed Cancel/Esc — go back one step
            if [[ $i -eq 0 ]]; then
                # On welcome screen, confirm quit
                dlg \
                    --title " Exit " \
                    --defaultno \
                    --yesno "\nExit the installer?" \
                    6 36 \
                && exit 0 || true
            else
                (( i-- ))
            fi
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # Ensure dialog is available
    if ! command -v dialog &>/dev/null; then
        echo "ERROR: 'dialog' is not installed."
        echo "Install it with: pacman -S dialog"
        exit 1
    fi

    # Ensure running as root
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This installer must be run as root."
        echo "Try: sudo ./$(basename "$0")"
        exit 1
    fi

    # Initialise log
    : > "$LOG_FILE"
    log "=== Arch Linux GNOME TUI Installer v${VERSION} ==="

    # Run wizard (welcome → summary)
    run_wizard

    # Execute installation
    screen_install

    # Show completion screen
    screen_complete
}

main "$@"
