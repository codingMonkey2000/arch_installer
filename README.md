# Arch Installer

A custom Arch Linux installer with a terminal based `dialog` interface and an optional HTML preview.

This installer is designed to be run from the official Arch Linux live ISO.

> Warning
> This installer will erase the selected disk completely. Do not run it on a system or disk that contains data you want to keep.

## What this does

The installer creates a fresh Arch Linux installation with:

* GNOME desktop
* systemd boot
* NetworkManager
* NVIDIA driver support
* AMD microcode
* Norwegian keyboard layout
* Optional Secure Boot setup using `sbctl`
* Optional development tools
* Optional AUR helper and extra applications

The real installer is:

```bash
arch-install-tui.sh
```

The HTML file is only a visual preview. It does not install Arch Linux by itself.

## Requirements

You should boot from the official Arch Linux ISO.

Before running the installer, check that you are in the Arch live environment:

```bash
command -v pacman
cat /etc/os-release
```

If `pacman` is missing, you are not in the Arch ISO or an Arch based live environment. Reboot into the official Arch Linux ISO before continuing.

Recommended setup:

* UEFI boot mode
* Ethernet connection
* Empty target disk or a disk you are ready to wipe
* Secure Boot disabled during installation
* Internet access

## Run directly from GitHub

From the Arch ISO terminal, run:

```bash
pacman -Sy --noconfirm git dialog
git clone https://github.com/codingMonkey2000/arch_installer.git
cd arch_installer
chmod +x arch-install-tui.sh
./arch-install-tui.sh
```

One line version:

```bash
pacman -Sy --noconfirm git dialog && git clone https://github.com/codingMonkey2000/arch_installer.git && cd arch_installer && chmod +x arch-install-tui.sh && ./arch-install-tui.sh
```

## HTML preview behavior

The repository includes:

```text
arch-install-preview.html
```

When the installer starts, it tries to open the HTML preview first.

This only works if a graphical browser and display session are available.

For example, it may open if you run it from a graphical Linux desktop with:

* Firefox
* Chromium
* Brave
* `xdg-open`

On the normal Arch ISO terminal, there is usually no graphical display and no browser. In that case, the installer will not load the HTML graphic visually. It should show the preview location or URL and continue with the real terminal installer.

The HTML preview is not required for installation.

## Permission denied

If you get:

```text
Permission denied
```

make the script executable:

```bash
chmod +x arch-install-tui.sh
./arch-install-tui.sh
```

Or run it directly with Bash:

```bash
bash arch-install-tui.sh
```

## pacman not found

If you get:

```text
pacman: command not found
```

you are not running from the Arch Linux ISO.

Boot the official Arch ISO, then try again.

## Installation log

During installation, logs are written to:

```text
/tmp/arch-install.log
```

If something fails, check:

```bash
less /tmp/arch-install.log
```

## Secure Boot note

Secure Boot should normally be disabled during the installation.

If Secure Boot support is selected, the installer prepares an `sbctl` based setup. After the first boot into the installed system, follow the generated post install instructions before enabling Secure Boot again in BIOS.

## Important safety notes

This project is a personal custom installer.

Review the script before running it:

```bash
less arch-install-tui.sh
```

The installer is destructive. It partitions and formats the selected target disk.

Do not run it on your main system unless you are sure you selected the correct disk and have backups.
::: 
