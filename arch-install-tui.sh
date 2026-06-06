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

readonly VERSION="1.2.2-full-fixed"
readonly BACKTITLE="  Arch Linux  ∙  GNOME 50+  ∙  v${VERSION}  "
readonly LOG_FILE="/tmp/arch-install.log"
RUN_CONTEXT="normal"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly HTML_PREVIEW_FILE="${SCRIPT_DIR}/arch-install-preview.html"
readonly HTML_PREVIEW_URL="https://codingmonkey2000.github.io/arch_installer/"

# ── Configuration state (populated by wizard) ────────────────────────────────

CFG_USERNAME=""
CFG_HOSTNAME=""
CFG_ROOT_PASS=""
CFG_USER_PASS=""
CFG_DISK=""
CFG_TIMEZONE="Europe/Oslo"
CFG_LOCALE="en_US.UTF-8"
CFG_KEYMAP="no"
CFG_XKBLAYOUT="no"
CFG_SECURE_BOOT="no"
CFG_DEV_TOOLS="yes"
CFG_WIPE_CONFIRMED="no"
CFG_GAMING="yes"
CFG_AUR="yes"
CFG_HYPERV="no"       # auto-detected

# ── Package lists ─────────────────────────────────────────────────────────────

BASE_PACKAGES="base base-devel linux linux-lts linux-firmware amd-ucode \
systemd efibootmgr networkmanager sudo nano vim git wget curl reflector \
dosfstools gptfdisk dkms linux-headers linux-lts-headers"

DESKTOP_PACKAGES="gnome gnome-extra gdm xdg-desktop-portal-gnome \
xdg-user-dirs xorg-xwayland mesa \
pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
pavucontrol alsa-utils ttf-dejavu ttf-liberation noto-fonts \
noto-fonts-emoji ttf-roboto ttf-opensans adobe-source-code-pro-fonts"

NVIDIA_PACKAGES="nvidia-open-dkms nvidia-utils nvidia-settings lib32-nvidia-utils egl-wayland"

HYPERV_PACKAGES="xf86-video-fbdev open-vm-tools"

DEV_PACKAGES="cmake make gcc clang gdb valgrind strace python python-pip \
python-virtualenv nodejs npm go rust rustup jdk-openjdk maven \
postgresql-libs mariadb sqlite redis docker docker-compose podman \
git-lfs meson ninja flatpak"

APP_PACKAGES="firefox thunderbird libreoffice-fresh evince gnome-text-editor \
gnome-calculator file-roller baobab gnome-screenshot mpv vlc gimp \
inkscape kdenlive audacity obs-studio neovim emacs htop btop fastfetch \
tree unzip p7zip rsync tmux zsh fish flameshot eza bat ripgrep fd \
fzf zoxide starship steam lutris wine gamemode mangohud keepassxc \
ufw fail2ban clamav rkhunter nmap wireshark-qt openvpn wireguard-tools"

# ─────────────────────────────────────────────────────────────────────────────
#  DIALOG WRAPPER
# ─────────────────────────────────────────────────────────────────────────────

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

# ── HTML preview launcher ─────────────────────────────────────────────────────

open_html_preview() {
    local preview_path=""
    local browser=""

    if [[ -f "$HTML_PREVIEW_FILE" ]]; then
        preview_path="$HTML_PREVIEW_FILE"
    fi

    # No graphical session — silently skip, no dialog popup
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        return 0
    fi

    for candidate in xdg-open firefox chromium google-chrome-stable brave brave-browser microsoft-edge; do
        if command -v "$candidate" &>/dev/null; then
            browser="$candidate"
            break
        fi
    done

    [[ -z "$browser" ]] && return 0

    if [[ -n "$preview_path" ]]; then
        "$browser" "file://${preview_path}" >/dev/null 2>&1 &
    else
        "$browser" "$HTML_PREVIEW_URL" >/dev/null 2>&1 &
    fi
}

# ── Logging ───────────────────────────────────────────────────────────────────

log()  { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }
loge() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >> "$LOG_FILE"; }

run() {
    log "RUN: $*"

    "$@" >> "$LOG_FILE" 2>&1
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        loge "Command failed (${rc}): $*"

        # When the installer is inside a dialog gauge, do not open another
        # dialog on top of it. That corrupts the gauge display. The main
        # installer screen will show the failure after the gauge exits.
        if [[ "${RUN_CONTEXT:-normal}" != "gauge" ]]; then
            dlg --title " ✗ Error " \
                --msgbox "
Command failed:

  $*

See the log for details:
  $LOG_FILE" \
                12 70
        fi

        return "$rc"
    fi

    return 0
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

# ── Hyper-V detection ────────────────────────────────────────────────────────

detect_hyperv() {
    if systemd-detect-virt 2>/dev/null | grep -qi "microsoft"; then
        CFG_HYPERV="yes"
    elif grep -qi "hyperv\|hv_vmbus\|microsoft" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
        CFG_HYPERV="yes"
    elif lsmod 2>/dev/null | grep -q "^hv_vmbus"; then
        CFG_HYPERV="yes"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 0 — WELCOME
# ─────────────────────────────────────────────────────────────────────────────

screen_welcome() {
    local hyperv_note=""
    [[ "$CFG_HYPERV" == "yes" ]] && \
        hyperv_note="\n  \Z6ℹ\Zn  Hyper-V detected — NVIDIA skipped, using fbdev\n"

    dlg \
        --title " Welcome to the Arch Linux Installer " \
        --yes-label "  Begin  " \
        --no-label "   Exit  " \
        --yesno \
"
\ZbArch Linux — GNOME 50+ Installer\ZB
\Z6────────────────────────────────────────────────\Zn

This wizard installs a complete Arch Linux system
with the GNOME desktop environment.
${hyperv_note}
\Z3  Hardware profile:\Zn
  ●  AMD Ryzen 9 9950X
  ●  NVIDIA RTX 5090  (nvidia-open-dkms)
  ●  ASRock X670E Taichi

\Z6────────────────────────────────────────────────\Zn
\Z1 ⚠  The target disk will be COMPLETELY ERASED.\Zn
\Z6────────────────────────────────────────────────\Zn
" \
        20 58 || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 1 — PRE-FLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────

screen_preflight() {
    local checks=""
    local all_ok=1

    # UEFI
    if [[ -d /sys/firmware/efi ]]; then
        checks+="\Z2  ✔\Zn  UEFI boot mode\n"
    else
        checks+="\Z1  ✗\Zn  Not in UEFI mode — check BIOS settings\n"
        all_ok=0
    fi

    # Internet
    if ping -c 1 -W 3 archlinux.org &>/dev/null 2>&1; then
        checks+="\Z2  ✔\Zn  Internet connection\n"
    else
        checks+="\Z1  ✗\Zn  No internet — configure network first\n"
        all_ok=0
    fi

    # dialog
    if command -v dialog &>/dev/null; then
        checks+="\Z2  ✔\Zn  dialog available\n"
    else
        checks+="\Z1  ✗\Zn  dialog not found  (pacman -S dialog)\n"
        all_ok=0
    fi

    # Clock
    timedatectl set-ntp true &>/dev/null || true
    checks+="\Z2  ✔\Zn  System clock synced\n"

    # Hyper-V note
    if [[ "$CFG_HYPERV" == "yes" ]]; then
        checks+="\Z6  ℹ\Zn  Hyper-V guest — NVIDIA drivers will be skipped\n"
    fi

    if [[ $all_ok -eq 0 ]]; then
        dlg \
            --title " ✗ Pre-flight Failed " \
            --msgbox "\nOne or more checks failed:\n\n${checks}\nResolve the issues above and re-run the installer." \
            16 64
        return 1
    fi

    dlg \
        --title " ✔ Pre-flight Checks " \
        --msgbox "\nAll systems ready:\n\n${checks}\nPress Enter to continue." \
        14 56
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 2 — USER ACCOUNT
# ─────────────────────────────────────────────────────────────────────────────

screen_user_account() {
    while true; do

        # ── Username ──
        dlg \
            --title " User Account  (1/4) " \
            --inputbox \
"\nEnter a username for the new account.\n\nLowercase letters, numbers, underscores; must start with a letter.\nExample:  bjorn\n" \
            11 56 "$CFG_USERNAME" || return 1
        local uname="$DLGRESULT"

        # ── Hostname ──
        dlg \
            --title " User Account  (2/4) " \
            --inputbox \
"\nEnter a hostname for this machine.\n\nLetters, numbers, and hyphens only.\nExample:  archbox\n" \
            11 56 "$CFG_HOSTNAME" || return 1
        local hname="$DLGRESULT"

        # ── Root password ──
        dlg \
            --title " User Account  (3/4) " \
            --insecure \
            --passwordbox \
"\nSet the \Zbroot\ZB password.\n\nMinimum 8 characters. Characters show as  *\n" \
            10 56 || return 1
        local rpass="$DLGRESULT"

        dlg \
            --title " User Account  (3/4) " \
            --insecure \
            --passwordbox \
"\nConfirm the \Zbroot\ZB password.\n" \
            9 56 || return 1
        local rpass2="$DLGRESULT"

        # ── User password ──
        dlg \
            --title " User Account  (4/4) " \
            --insecure \
            --passwordbox \
"\nSet the password for \Zb${uname:-<user>}\ZB.\n\nMinimum 8 characters. Characters show as  *\n" \
            10 56 || return 1
        local upass="$DLGRESULT"

        dlg \
            --title " User Account  (4/4) " \
            --insecure \
            --passwordbox \
"\nConfirm the password for \Zb${uname:-<user>}\ZB.\n" \
            9 56 || return 1
        local upass2="$DLGRESULT"

        # ── Validation ──
        local errs=""
        [[ ! "$uname"  =~ ^[a-z_][a-z0-9_-]*$ ]] && \
            errs+="\Z1  ✗\Zn  Invalid username — lowercase, start with a letter\n"
        [[ ! "$hname"  =~ ^[a-zA-Z0-9-]+$ ]] && \
            errs+="\Z1  ✗\Zn  Invalid hostname — letters, numbers, hyphens only\n"
        [[ ${#rpass} -lt 8 ]] && \
            errs+="\Z1  ✗\Zn  Root password too short  (min 8 chars)\n"
        [[ "$rpass" != "$rpass2" ]] && \
            errs+="\Z1  ✗\Zn  Root passwords do not match\n"
        [[ ${#upass} -lt 8 ]] && \
            errs+="\Z1  ✗\Zn  User password too short  (min 8 chars)\n"
        [[ "$upass" != "$upass2" ]] && \
            errs+="\Z1  ✗\Zn  User passwords do not match\n"
        [[ "$rpass" == *":"* || "$upass" == *":"* ]] && \
            errs+="\Z1  ✗\Zn  Passwords cannot contain  ':'\n"

        if [[ -n "$errs" ]]; then
            dlg \
                --title " ✗ Validation Errors " \
                --msgbox "\nPlease fix the following:\n\n${errs}" \
                14 62
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
#  SCREEN 3 — LOCALE & KEYBOARD
# ─────────────────────────────────────────────────────────────────────────────

screen_locale() {
    # ── Step 1: Region / Language ─────────────────────────────────────────────
    # Offer common locales; user can type a custom one after.
    local locale_items=(
        "en_US.UTF-8"  "English  (United States)"          "off"
        "en_GB.UTF-8"  "English  (United Kingdom)"         "off"
        "nb_NO.UTF-8"  "Norwegian Bokmål"                  "off"
        "nn_NO.UTF-8"  "Norwegian Nynorsk"                 "off"
        "sv_SE.UTF-8"  "Swedish"                           "off"
        "da_DK.UTF-8"  "Danish"                            "off"
        "fi_FI.UTF-8"  "Finnish"                           "off"
        "de_DE.UTF-8"  "German"                            "off"
        "fr_FR.UTF-8"  "French"                            "off"
        "es_ES.UTF-8"  "Spanish"                           "off"
        "pt_PT.UTF-8"  "Portuguese  (Portugal)"            "off"
        "pt_BR.UTF-8"  "Portuguese  (Brazil)"              "off"
        "it_IT.UTF-8"  "Italian"                           "off"
        "nl_NL.UTF-8"  "Dutch"                             "off"
        "pl_PL.UTF-8"  "Polish"                            "off"
        "ru_RU.UTF-8"  "Russian"                           "off"
        "zh_CN.UTF-8"  "Chinese  (Simplified)"             "off"
        "ja_JP.UTF-8"  "Japanese"                          "off"
        "ko_KR.UTF-8"  "Korean"                            "off"
        "ar_SA.UTF-8"  "Arabic"                            "off"
    )
    # Mark current
    local i=0
    while [[ $i -lt ${#locale_items[@]} ]]; do
        if [[ "${locale_items[$i]}" == "$CFG_LOCALE" ]]; then
            locale_items[$((i+2))]="on"
        fi
        (( i+=3 ))
    done

    dlg \
        --title " Locale & Language  (1/2) " \
        --radiolist \
"\nSelect your system locale.\n" \
        22 60 14 \
        "${locale_items[@]}" \
        || return 1

    [[ -n "$DLGRESULT" ]] && CFG_LOCALE="$DLGRESULT"

    # ── Step 2: Keyboard layout ───────────────────────────────────────────────
    # Build list from localectl with popular ones at the top
    local top_keymaps=(
        "us"     "English (US)"
        "gb"     "English (UK)"
        "no"     "Norwegian"
        "sv"     "Swedish"
        "dk"     "Danish"
        "fi"     "Finnish"
        "de"     "German"
        "fr"     "French"
        "es"     "Spanish"
        "pt"     "Portuguese"
        "it"     "Italian"
        "ru"     "Russian"
        "pl"     "Polish"
        "br"     "Brazilian Portuguese"
        "be"     "Belgian"
        "ch"     "Swiss"
        "at"     "Austrian"
        "hu"     "Hungarian"
        "ro"     "Romanian"
        "tr"     "Turkish"
        "jp"     "Japanese"
        "cn"     "Chinese"
        "latam"  "Latin American"
        "dvp"    "Programmer Dvorak"
        "colemak" "Colemak"
    )

    local km_items=()
    local k=0
    while [[ $k -lt ${#top_keymaps[@]} ]]; do
        local kcode="${top_keymaps[$k]}"
        local kdesc="${top_keymaps[$((k+1))]}"
        if [[ "$kcode" == "$CFG_KEYMAP" ]]; then
            km_items+=("$kcode" "$kdesc" "on")
        else
            km_items+=("$kcode" "$kdesc" "off")
        fi
        (( k+=2 ))
    done

    dlg \
        --title " Locale & Language  (2/2) " \
        --radiolist \
"\nSelect your keyboard layout.\n\nThis sets both the console keymap and the GNOME keyboard.\n" \
        22 60 14 \
        "${km_items[@]}" \
        || return 1

    if [[ -n "$DLGRESULT" ]]; then
        CFG_KEYMAP="$DLGRESULT"
        CFG_XKBLAYOUT="$DLGRESULT"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 4 — TIMEZONE
# ─────────────────────────────────────────────────────────────────────────────

screen_timezone() {
    local items=(
        "Europe/Oslo"         "Norway"
        "Europe/Stockholm"    "Sweden"
        "Europe/Copenhagen"   "Denmark"
        "Europe/London"       "United Kingdom"
        "Europe/Berlin"       "Germany"
        "Europe/Paris"        "France"
        "Europe/Helsinki"     "Finland"
        "UTC"                 "UTC"
        "America/New_York"    "US Eastern"
        "America/Chicago"     "US Central"
        "America/Los_Angeles" "US Pacific"
        "Asia/Singapore"      "Singapore"
        "Asia/Tokyo"          "Japan"
        "Australia/Sydney"    "Australia Sydney"
        "MANUAL"              "Type another timezone manually"
    )

    while true; do
        dlg \
            --title " Timezone " \
            --default-item "${CFG_TIMEZONE:-Europe/Oslo}" \
            --menu \
"
Select your timezone.

Current/default:
  ${CFG_TIMEZONE:-Europe/Oslo}

Use arrow keys and Enter.
" \
            20 70 12 \
            "${items[@]}" \
            || return 1

        local selected="${DLGRESULT:-Europe/Oslo}"

        if [[ "$selected" == "MANUAL" ]]; then
            dlg \
                --title " Manual Timezone " \
                --inputbox \
"
Type an IANA timezone.

Examples:
  Europe/Oslo
  Europe/London
  America/New_York
" \
                12 64 "${CFG_TIMEZONE:-Europe/Oslo}" \
                || return 1
            selected="${DLGRESULT:-Europe/Oslo}"
        fi

        if [[ "$selected" == "UTC" ]] || timedatectl list-timezones 2>/dev/null | grep -qx "$selected"; then
            CFG_TIMEZONE="$selected"
            return 0
        fi

        dlg \
            --title " Invalid Timezone " \
            --msgbox \
"
The timezone was not recognised:

  ${selected}

Please select one from the list or enter a valid IANA timezone.
" \
            11 66
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 5 — DISK SELECTION
# ─────────────────────────────────────────────────────────────────────────────

screen_disk() {
    local items=()
    local line
    while IFS= read -r line; do
        local dev size model
        dev=$(  echo "$line" | awk '{print $1}')
        size=$( echo "$line" | awk '{print $2}')
        model=$(echo "$line" | awk '{$1=$2=""; print $0}' | xargs)
        [[ -z "$model" ]] && model="(no model)"
        items+=("/dev/${dev}" "${size}   ${model}")
    done < <(lsblk -d -o NAME,SIZE,MODEL | grep -E "^(nvme|sd|vd)" 2>/dev/null)

    if [[ ${#items[@]} -eq 0 ]]; then
        dlg --title " ✗ No Disks Found " \
            --msgbox "\nNo suitable block devices were detected.\nCheck your hardware and try again." \
            8 54
        return 1
    fi

    dlg \
        --title " Disk Selection " \
        --menu \
"\n\Z1⚠  The selected disk will be COMPLETELY ERASED.\Zn\n\nChoose the target installation disk:\n" \
        17 70 6 \
        "${items[@]}" \
        || return 1

    CFG_DISK="$DLGRESULT"

    local disk_info
    disk_info=$(lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$CFG_DISK" 2>/dev/null \
        || echo "(unable to read disk info)")

    dlg \
        --title " ⚠  Confirm Disk Wipe " \
        --defaultno \
        --yes-label "  ERASE & INSTALL  " \
        --no-label "  Go Back  " \
        --yesno \
"
\Z1This will PERMANENTLY DESTROY all data on:\Zn

  \Zb${CFG_DISK}\ZB

${disk_info}

\Z1There is NO undo.  Are you absolutely sure?\Zn
" \
        17 70 || { CFG_DISK=""; return 1; }

    CFG_WIPE_CONFIRMED="yes"
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 6 — FEATURE SELECTION
# ─────────────────────────────────────────────────────────────────────────────

screen_features() {
    local dev_default="on"
    [[ "$CFG_DEV_TOOLS" == "no" ]] && dev_default="off"

    local gaming_default="on"
    [[ "$CFG_HYPERV" == "yes" ]] && gaming_default="off"

    local always_line="GNOME 50+, GDM, ${CFG_KEYMAP} keyboard, UFW firewall"
    [[ "$CFG_HYPERV" == "yes" ]] && \
        always_line="GNOME 50+, GDM, ${CFG_KEYMAP} keyboard, UFW, Hyper-V guest drivers"

    dlg \
        --title " Feature Selection " \
        --checklist \
"\nSelect optional components to install.\n\nAlways installed: ${always_line}\n" \
        16 72 4 \
        "DEV_TOOLS"   "Full dev environment  (Docker, Rust, Node, Python…)" "$dev_default"  \
        "AUR_HELPER"  "yay AUR helper  +  VS Code, Brave, Postman, Timeshift" "on"          \
        "GAMING"      "Gaming stack  (Steam, Lutris, Wine, MangoHud)"       "$gaming_default" \
        || return 1

    CFG_DEV_TOOLS="no"
    local sel="$DLGRESULT"
    [[ "$sel" == *"DEV_TOOLS"*  ]] && CFG_DEV_TOOLS="yes"
    CFG_GAMING="no";  [[ "$sel" == *"GAMING"*    ]] && CFG_GAMING="yes"
    CFG_AUR="no";     [[ "$sel" == *"AUR_HELPER"* ]] && CFG_AUR="yes"
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 7 — SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

screen_summary() {
    local dev_label="No"
    [[ "$CFG_DEV_TOOLS" == "yes" ]] && dev_label="Yes"
    local hyperv_line=""
    [[ "$CFG_HYPERV" == "yes" ]] && \
        hyperv_line="\n  \ZbEnvironment\ZB     :  \Z6Hyper-V guest  (NVIDIA skipped)\Zn"

    dlg \
        --title " Installation Summary " \
        --yes-label "  ▶  Install Now  " \
        --no-label "  ◀  Go Back  " \
        --yesno \
"
Review your configuration.
${hyperv_line}
  \ZbUsername\ZB        :  ${CFG_USERNAME}
  \ZbHostname\ZB        :  ${CFG_HOSTNAME}
  \ZbLocale\ZB          :  ${CFG_LOCALE}
  \ZbKeyboard\ZB        :  ${CFG_KEYMAP}
  \ZbTimezone\ZB        :  ${CFG_TIMEZONE}
  \ZbTarget disk\ZB     :  ${CFG_DISK}
  \ZbDev tools\ZB       :  ${dev_label}
  \ZbAUR helper\ZB      :  ${CFG_AUR}
  \ZbGaming stack\ZB    :  ${CFG_GAMING}
  \ZbKernel\ZB          :  linux + linux-lts  (fallback)
  \ZbDesktop\ZB         :  GNOME 50+  /  GDM  /  Wayland
  \ZbBootloader\ZB      :  systemd-boot

\Z1Once you press Install Now, the disk will be erased.\Zn
" \
        24 62 || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
#  INSTALLATION — HELPERS
# ─────────────────────────────────────────────────────────────────────────────

gauge_update() {
    local pct="$1"
    local msg="$2"
    printf 'XXX\n%s\n%s\nXXX\n' "$pct" "$msg"
}

part_suffix() {
    case "$CFG_DISK" in
        /dev/nvme*|/dev/mmcblk*) echo "p" ;;
        *) echo "" ;;
    esac
}

efi_part()  { echo "${CFG_DISK}$(part_suffix)1"; }
root_part() { echo "${CFG_DISK}$(part_suffix)2"; }

wait_for_partitions() {
    local efi
    local root
    efi="$(efi_part)"
    root="$(root_part)"

    log "Waiting for partition nodes: ${efi}, ${root}"

    partprobe "$CFG_DISK" >> "$LOG_FILE" 2>&1 || true
    blockdev --rereadpt "$CFG_DISK" >> "$LOG_FILE" 2>&1 || true
    udevadm settle >> "$LOG_FILE" 2>&1 || true
    sync

    local i
    for i in {1..20}; do
        if [[ -b "$efi" && -b "$root" ]]; then
            log "Partition nodes are ready"
            return 0
        fi
        sleep 0.5
        partprobe "$CFG_DISK" >> "$LOG_FILE" 2>&1 || true
        udevadm settle >> "$LOG_FILE" 2>&1 || true
    done

    loge "Partition nodes did not appear"
    lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS >> "$LOG_FILE" 2>&1 || true
    return 1
}

log_storage_state() {
    {
        echo
        echo "===== STORAGE STATE ====="
        lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTTYPE,MOUNTPOINTS
        echo
        blkid || true
        echo
        dmesg | tail -80 || true
        echo "========================="
        echo
    } >> "$LOG_FILE" 2>&1 || true
}

# ─────────────────────────────────────────────────────────────────────────────
#  INSTALLATION STEPS
# ─────────────────────────────────────────────────────────────────────────────

step_partition() {
    log "=== PARTITIONING ==="

    umount -R /mnt >> "$LOG_FILE" 2>&1 || true
    swapoff -a >> "$LOG_FILE" 2>&1 || true

    # Clear old filesystem and partition signatures from the selected disk.
    # This prevents the kernel from trying stale ext2/ext3/ext4 signatures.
    run wipefs -af "$CFG_DISK"
    run sgdisk --zap-all "$CFG_DISK"
    run sgdisk --clear "$CFG_DISK"
    run sgdisk --new=1:0:+1G --typecode=1:ef00 --change-name=1:"EFI System" "$CFG_DISK"
    run sgdisk --new=2:0:0   --typecode=2:8300 --change-name=2:"Linux filesystem" "$CFG_DISK"

    wait_for_partitions

    # Also wipe old signatures on the newly created partitions before formatting.
    wipefs -af "$(efi_part)"  >> "$LOG_FILE" 2>&1 || true
    wipefs -af "$(root_part)" >> "$LOG_FILE" 2>&1 || true

    log_storage_state
}

step_format() {
    log "=== FORMATTING ==="

    wait_for_partitions

    run mkfs.fat -F32 -n EFI "$(efi_part)"
    run mkfs.ext4 -F -L ROOT "$(root_part)"

    # Give the kernel a moment to reread the new filesystem metadata.
    sync
    udevadm settle >> "$LOG_FILE" 2>&1 || true
    sleep 1

    log_storage_state
}

step_mount() {
    log "=== MOUNTING ==="

    wait_for_partitions

    mkdir -p /mnt
    umount -R /mnt >> "$LOG_FILE" 2>&1 || true

    if ! mount -t ext4 -o defaults "$(root_part)" /mnt >> "$LOG_FILE" 2>&1; then
        loge "Failed to mount root partition $(root_part) as ext4"
        log_storage_state
        return 1
    fi

    mkdir -p /mnt/boot

    if ! mount -t vfat -o defaults "$(efi_part)" /mnt/boot >> "$LOG_FILE" 2>&1; then
        loge "Failed to mount EFI partition $(efi_part) as vfat"
        log_storage_state
        return 1
    fi

    log_storage_state
}

step_update_mirrors() {
    log "=== MIRROR UPDATE ==="

    if ! ping -c 1 -W 5 archlinux.org >> "$LOG_FILE" 2>&1; then
        loge "No internet connection while updating mirrors"
        return 1
    fi

    pacman -Sy --noconfirm >> "$LOG_FILE" 2>&1 || true

    if ! command -v reflector >> "$LOG_FILE" 2>&1; then
        pacman -S --needed --noconfirm reflector >> "$LOG_FILE" 2>&1 || true
    fi

    if command -v reflector >> "$LOG_FILE" 2>&1; then
        reflector \
            --country Norway \
            --country Germany \
            --protocol https \
            --latest 20 \
            --sort rate \
            --save /etc/pacman.d/mirrorlist >> "$LOG_FILE" 2>&1 || {
                loge "Reflector failed, continuing with existing mirrorlist"
                return 0
            }
    else
        loge "Reflector unavailable, continuing with existing mirrorlist"
    fi

    return 0
}

step_pacstrap() {
    log "=== PACSTRAP BASE ==="

    pacman -Sy --noconfirm >> "$LOG_FILE" 2>&1 || true

    # shellcheck disable=SC2086
    run pacstrap /mnt $BASE_PACKAGES

    log "RUN: genfstab -U /mnt >> /mnt/etc/fstab"
    : > /mnt/etc/fstab
    if ! genfstab -U /mnt >> /mnt/etc/fstab 2>> "$LOG_FILE"; then
        loge "Command failed: genfstab"
        return 1
    fi

    if [[ ! -s /mnt/etc/fstab ]]; then
        loge "Generated fstab is empty"
        log_storage_state
        return 1
    fi

    log "Generated fstab:"
    cat /mnt/etc/fstab >> "$LOG_FILE" 2>&1 || true
}

# ─────────────────────────────────────────────────────────────────────────────
#  SYSTEM CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

step_configure() {
    log "=== SYSTEM CONFIGURATION ==="

    # Determine extra locale line(s)
    local extra_locale=""
    if [[ "$CFG_LOCALE" != "en_US.UTF-8" ]]; then
        extra_locale="echo \"${CFG_LOCALE} UTF-8\" >> /etc/locale.gen"
    fi

    cat > /mnt/do_configure.sh << CONF_EOF
#!/bin/bash
set -euo pipefail
TZ="\$1"; HN="\$2"; RP="\$3"; UN="\$4"; UP="\$5"; KM="\$6"; LC="\$7"; XKB="\$8"

ln -sf "/usr/share/zoneinfo/\${TZ}" /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
${extra_locale}
locale-gen
echo "LANG=\${LC}"       > /etc/locale.conf
echo "KEYMAP=\${KM}"     > /etc/vconsole.conf

echo "\${HN}" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${HN}.localdomain \${HN}
HOSTS

# mkinitcpio — load GPU early
HYPERV_VAL="\${9:-no}"
if [[ "\$HYPERV_VAL" == "yes" ]]; then
    sed -i 's/^MODULES=.*/MODULES=(hv_vmbus hv_storvsc hv_netvsc hyperv_keyboard hyperv_drm)/' /etc/mkinitcpio.conf
else
    sed -i 's/^MODULES=.*/MODULES=(amdgpu nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sed -i 's/ kms//' /etc/mkinitcpio.conf
fi
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

if [[ "\$HYPERV_VAL" == "yes" ]]; then
    KO="root=LABEL=ROOT rw video=hyperv_fb:1920x1080 quiet"
else
    KO="root=LABEL=ROOT rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1 quiet"
fi

cat > /boot/loader/entries/arch.conf << ARC
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options \${KO}
ARC
cat > /boot/loader/entries/arch-lts.conf << LTS
title   Arch Linux LTS  (fallback)
linux   /vmlinuz-linux-lts
initrd  /amd-ucode.img
initrd  /initramfs-linux-lts.img
options \${KO}
LTS

# Pacman hooks
mkdir -p /etc/pacman.d/hooks
if [[ "\$HYPERV_VAL" != "yes" ]]; then
cat > /etc/pacman.d/hooks/nvidia.hook << NVH
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=nvidia-open-dkms
Target=linux
Target=linux-lts
[Action]
Description=Update initramfs for NVIDIA
Depends=mkinitcpio
When=PostTransaction
NeedsTargets
Exec=/bin/sh -c 'while read -r trg; do case \\\$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'
NVH
fi
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
if [[ "\$HYPERV_VAL" == "yes" ]]; then
    systemctl enable hv_fcopy_daemon 2>/dev/null || true
    systemctl enable hv_kvp_daemon  2>/dev/null || true
    systemctl enable hv_vss_daemon  2>/dev/null || true
fi

# Wayland environment
cat > /etc/environment << ENV
GNOME_SESSION_TYPE=wayland
XDG_SESSION_TYPE=wayland
ENV

# Accounts
echo "root:\${RP}" | chpasswd
useradd -m -G wheel,audio,video -s /bin/bash "\${UN}"
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
        "$CFG_ROOT_PASS" "$CFG_USERNAME" "$CFG_USER_PASS" \
        "$CFG_KEYMAP" "$CFG_LOCALE" "$CFG_XKBLAYOUT" "$CFG_HYPERV"
    run arch-chroot /mnt pacman -Sy --noconfirm
    rm -f /mnt/do_configure.sh
}

step_nvidia() {
    if [[ "$CFG_HYPERV" == "yes" ]]; then
        log "=== SKIPPING NVIDIA (Hyper-V guest) ==="
        # shellcheck disable=SC2086
        run arch-chroot /mnt pacman -S --noconfirm $HYPERV_PACKAGES
        return 0
    fi

    log "=== NVIDIA RTX 5090 DRIVERS ==="
    # shellcheck disable=SC2086
    run arch-chroot /mnt pacman -S --noconfirm $NVIDIA_PACKAGES

    mkdir -p /mnt/etc/modprobe.d
    cat > /mnt/etc/modprobe.d/nvidia.conf << 'EOF'
options nvidia NVreg_DynamicPowerManagement=0x02
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia-drm modeset=1 fbdev=1
EOF
}

step_desktop() {
    log "=== GNOME 50+ DESKTOP ==="
    local pkgs="$DESKTOP_PACKAGES"
    # Add GPU-specific Mesa packages
    if [[ "$CFG_HYPERV" != "yes" ]]; then
        pkgs="$pkgs vulkan-radeon lib32-mesa lib32-nvidia-utils"
    fi
    # shellcheck disable=SC2086
    run arch-chroot /mnt pacman -S --noconfirm $pkgs
    run arch-chroot /mnt systemctl --global enable \
        pipewire.socket pipewire-pulse.socket wireplumber.service

    # Keyboard layout for X11/Wayland
    mkdir -p /mnt/etc/X11/xorg.conf.d
    cat > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf << EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "${CFG_XKBLAYOUT}"
    Option "XkbModel" "pc105"
EndSection
EOF
}

step_applications() {
    log "=== APPLICATIONS ==="
    local pkgs="$APP_PACKAGES"

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
    if [[ "$CFG_HYPERV" == "yes" ]]; then return 0; fi
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
    arch-chroot /mnt ufw --force enable       >> "$LOG_FILE" 2>&1 || true
    arch-chroot /mnt ufw default deny incoming >> "$LOG_FILE" 2>&1 || true
    arch-chroot /mnt ufw default allow outgoing >> "$LOG_FILE" 2>&1 || true
    run arch-chroot /mnt systemctl enable ufw
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
if command -v yay >/dev/null 2>&1; then
    echo "Updating AUR packages..."
    yay -Sua
else
    echo "yay not installed, skipping AUR updates."
fi
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

    cat > "${home}/POST_INSTALL_GUIDE.md" << EOF
# Arch Linux Post-Installation Guide
Installed: ${install_date}

## First boot checklist

### 1. Dev environment
\`\`\`bash
~/setup-dev-env.sh
\`\`\`

### 2. NVIDIA check (bare metal only)
\`\`\`bash
nvidia-smi
\`\`\`

### 3. WiFi
If MediaTek MT7927 is not working, replace with Intel AX210.
See ~/WIRELESS_INFO.txt for details.
EOF

    cat > "${home}/WIRELESS_INFO.txt" << 'EOF'
MEDIATEK MT7927 WIRELESS CARD
==============================
Full Linux support is not guaranteed for this chipset.
RECOMMENDED: Replace with Intel AX210 (Wi-Fi 6E + BT 5.2).

Test driver status:
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
    run arch-chroot /mnt pacman -S --needed --noconfirm git base-devel go sudo

    mkdir -p /mnt/etc/sudoers.d
    cat > "/mnt/etc/sudoers.d/99-arch-installer-${CFG_USERNAME}" << EOF
${CFG_USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL
EOF
    chmod 0440 "/mnt/etc/sudoers.d/99-arch-installer-${CFG_USERNAME}"

    cat > /mnt/install_yay.sh << 'EOF'
#!/bin/bash
set -euo pipefail
cd /tmp
rm -rf yay
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay
yay -S --needed --noconfirm visual-studio-code-bin brave-bin postman-bin timeshift auto-cpufreq || true
EOF
    chmod +x /mnt/install_yay.sh
    run arch-chroot /mnt runuser -u "$CFG_USERNAME" -- /install_yay.sh
    rm -f /mnt/install_yay.sh
    rm -f "/mnt/etc/sudoers.d/99-arch-installer-${CFG_USERNAME}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 8 — INSTALLATION PROGRESS
# ─────────────────────────────────────────────────────────────────────────────

screen_install() {
    : > "$LOG_FILE"
    log "Installation started at $(date)"
    log "Config: user=$CFG_USERNAME host=$CFG_HOSTNAME disk=$CFG_DISK tz=$CFG_TIMEZONE locale=$CFG_LOCALE keymap=$CFG_KEYMAP hyperv=$CFG_HYPERV"

    local gpu_label="NVIDIA driver setup"
    [[ "$CFG_HYPERV" == "yes" ]] && gpu_label="Hyper-V guest setup"

    (
        set -e
        RUN_CONTEXT="gauge"

        gauge_update  2  "Preparing disk ${CFG_DISK}"
        step_partition

        gauge_update  7  "Formatting EFI and root partitions"
        step_format

        gauge_update 11  "Mounting new system"
        step_mount

        gauge_update 14  "Updating Arch mirrors"
        step_update_mirrors

        gauge_update 18  "Installing base system"
        step_pacstrap

        gauge_update 38  "Configuring bootloader, locale and users"
        step_configure

        gauge_update 50  "${gpu_label}"
        step_nvidia

        gauge_update 60  "Installing GNOME desktop"
        step_desktop

        gauge_update 72  "Installing applications"
        step_applications

        gauge_update 82  "Applying system optimisations"
        step_amd_optimise

        gauge_update 86  "Configuring firewall"
        step_firewall

        gauge_update 91  "Creating user scripts and guides"
        step_user_scripts

        gauge_update 95  "Installing AUR helper and selected AUR packages"
        step_aur

        gauge_update 98  "Syncing filesystem"
        sync

        gauge_update 100 "Installation complete"
        log "Installation finished at $(date)"

    ) | dialog \
        --colors \
        --backtitle "$BACKTITLE" \
        --title " Installing Arch Linux " \
        --gauge \
"Installing Arch Linux

Disk: ${CFG_DISK}
Log : ${LOG_FILE}

This can take 15 to 40 minutes.
Do not power off the machine." \
        13 74 0

    local install_rc=${PIPESTATUS[0]}
    RUN_CONTEXT="normal"

    if [[ $install_rc -ne 0 ]]; then
        loge "Installation aborted with exit code ${install_rc}"
        return "$install_rc"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  SCREEN 9 — COMPLETION
# ─────────────────────────────────────────────────────────────────────────────

screen_complete() {
    local had_errors=0
    grep -qi "ERROR:" "$LOG_FILE" 2>/dev/null && had_errors=1

    if [[ $had_errors -eq 1 ]]; then
        dlg \
            --title " ⚠  Installation Completed with Warnings " \
            --yes-label "  View Log  " \
            --no-label "  Reboot  " \
            --yesno \
"
Errors were detected during installation.
Review the log before rebooting.

  Log file: ${LOG_FILE}

Press \ZbView Log\ZB to inspect, or \ZbReboot\ZB to continue.
" \
            10 64
        if [[ $? -eq 0 ]]; then
            dlg --title " Installation Log " --textbox "$LOG_FILE" 22 82
        fi
    else
        dlg \
            --title " ✔  Installation Complete " \
            --msgbox \
"
\Z2Arch Linux GNOME has been installed successfully!\Zn

  Username  :  ${CFG_USERNAME}
  Hostname  :  ${CFG_HOSTNAME}
  Locale    :  ${CFG_LOCALE}
  Keyboard  :  ${CFG_KEYMAP}
  Disk      :  ${CFG_DISK}

\ZbNext steps after reboot:\ZB
  1. Remove the installation media
  2. Boot into Arch Linux  →  log in as ${CFG_USERNAME}
  3. Run ~/setup-dev-env.sh  for Rust / nvm / pyenv
  4. Read ~/POST_INSTALL_GUIDE.md

" \
            20 60
    fi

    dlg \
        --title " Reboot " \
        --defaultno \
        --yesno \
"\nReboot now?  (Remove installation media first.)" \
        7 54 \
    && reboot
}

# ─────────────────────────────────────────────────────────────────────────────
#  WIZARD RUNNER
# ─────────────────────────────────────────────────────────────────────────────

run_wizard() {
    local screens=(
        screen_welcome
        screen_preflight
        screen_user_account
        screen_locale
        screen_timezone
        screen_disk
        screen_features
        screen_summary
    )
    local i=0
    local total=${#screens[@]}

    while true; do
        [[ $i -ge $total ]] && break
        [[ $i -lt 0 ]] && i=0

        if "${screens[$i]}"; then
            (( i++ ))
        else
            if [[ $i -eq 0 ]]; then
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
    if ! command -v dialog &>/dev/null; then
        echo "ERROR: 'dialog' is not installed."
        echo "Run: pacman -S dialog"
        exit 1
    fi

    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This installer must be run as root."
        echo "Try:  sudo ./$(basename "$0")"
        exit 1
    fi

    : > "$LOG_FILE"
    log "=== Arch Linux GNOME TUI Installer v${VERSION} ==="

    # Detect virtualisation before any UI
    detect_hyperv
    [[ "$CFG_HYPERV" == "yes" ]] && log "Hyper-V guest detected — NVIDIA will be skipped"

    # Open the HTML preview silently in background if possible
    open_html_preview

    run_wizard

    if ! screen_install; then
        dlg --title " ✗ Installation Failed " \
            --msgbox "\nInstallation failed.\n\nCheck the log:\n  ${LOG_FILE}\n\nInspect with:\n  less ${LOG_FILE}" \
            12 62
        return 1
    fi

    screen_complete
}

main "$@"
