Arch Installer
Custom Arch Linux installer script for a GNOME desktop setup with NVIDIA drivers and optional Secure Boot support.
> ⚠️ **Danger:** this installer deletes all partitions on the disk you select. Back up anything important before running it.
Important: where this command works
The commands below are intended to be run from the official Arch Linux live ISO after booting into the installer environment.
They require `pacman`, which is normally available on the Arch ISO. If `pacman` is not found, you are probably not in the Arch live ISO. Reboot into the official Arch ISO first.
Quick check:
```bash
command -v pacman
cat /etc/os-release
```
You should see `pacman` and an Arch Linux environment.
Recommended way to run from GitHub
Boot the official Arch Linux ISO, connect to the internet, then run:
```bash
pacman -Sy --noconfirm git dialog

git clone https://github.com/codingMonkey2000/arch_installer.git
cd arch_installer

chmod +x arch-install-tui.sh
./arch-install-tui.sh
```
One-line version
Use this only if you are comfortable running the installer directly after cloning:
```bash
pacman -Sy --noconfirm git dialog && git clone https://github.com/codingMonkey2000/arch_installer.git && cd arch_installer && chmod +x arch-install-tui.sh && ./arch-install-tui.sh
```
Safer review-before-run method
This lets you inspect the script before executing it:
```bash
pacman -Sy --noconfirm git dialog

git clone https://github.com/codingMonkey2000/arch_installer.git
cd arch_installer

less arch-install-tui.sh
chmod +x arch-install-tui.sh
./arch-install-tui.sh
```
Alternative: run without `chmod`
If you get `permission denied`, run it through Bash directly:
```bash
bash arch-install-tui.sh
```
If `pacman` is not installed
This installer is not meant to be launched from Windows, Ubuntu, Debian, Fedora, macOS, or a normal installed Linux desktop.
If this fails:
```bash
pacman -Sy --noconfirm git dialog
```
then do this instead:
Download the official Arch Linux ISO.
Boot your PC or VM from that ISO.
Connect to the internet.
Run the GitHub commands again from the Arch live shell.
Do not try to replace `pacman` with `apt`, `dnf`, `brew`, or another package manager. The script uses Arch installation tools such as `pacstrap`, `arch-chroot`, `genfstab`, `mkinitcpio`, and `bootctl`.
HTML preview
The file `arch-install-preview.html` is only a visual preview/mockup of the installer screens.
It does not install Arch Linux and should not be run as the installer. Open it in a browser only if you want to preview the look and flow of the TUI.
The real installer is:
```bash
arch-install-tui.sh
```
Requirements
Official Arch Linux live ISO
UEFI boot mode
Ethernet or working internet connection
Root shell, which the Arch ISO gives you by default
A target disk you are okay with completely erasing
Notes
The installer uses `dialog` for the terminal user interface.
The script is designed for a modern GNOME setup with NVIDIA support.
Secure Boot setup should be treated carefully. Read the prompts before enabling it.
If installation fails, check the log:
```bash
cat /tmp/arch-install.log
```
Fixing the old command
Do not use this broken command:
```bash
pacman -Sy dialog chmod +x arch-install-tui.sh./arch-install-tui.sh
```
It mixes package installation, permission changes, and script execution into one invalid command.
Use this instead:
```bash
pacman -Sy --noconfirm git dialog
chmod +x arch-install-tui.sh
./arch-install-tui.sh
```
