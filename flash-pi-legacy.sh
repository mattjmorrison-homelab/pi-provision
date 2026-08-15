#!/usr/bin/env bash
# Flashes Raspberry Pi OS Lite (32-bit, Trixie) for headless SSH access.
# Targets old ARMv6 boards (e.g. original Pi 1 Model B) — the 32-bit build
# supports all Raspberry Pi models, unlike the 64-bit build (ARMv7+ only).
set -euo pipefail

DOWNLOADS="$HOME/Downloads"
TRIXIE_ARMHF="2026-06-18-raspios-trixie-armhf-lite.img.xz"

# Prompt for image path
# read -rp "Path to image file: " IMAGE_PATH
# IMAGE_PATH="${IMAGE_PATH/#\~/$HOME}"
IMAGE_PATH="${DOWNLOADS}/${TRIXIE_ARMHF}"

echo "$IMAGE_PATH"

if [[ ! -f "$IMAGE_PATH" ]]; then
  echo "File not found: $IMAGE_PATH"
  exit 1
fi

# Show disk list and prompt
echo ""
diskutil list
echo ""
read -rp "Disk identifier (e.g. disk4): " DISK

# Safety confirmation
echo ""
echo "WARNING: This will completely erase /dev/$DISK"
read -rp "Type YES to confirm: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "Aborted."
  exit 1
fi

# Prompt for password
echo ""
read -rsp "Password for pi user: " PASSWORD
echo ""

# Find SSH public key
PUBKEY=""
for KEY_FILE in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
  if [[ -f "$KEY_FILE" ]]; then
    PUBKEY=$(cat "$KEY_FILE")
    echo "Using SSH key: $KEY_FILE"
    break
  fi
done

if [[ -z "$PUBKEY" ]]; then
  echo "No SSH public key found — password auth only."
fi

# Unmount
echo ""
echo "Unmounting /dev/$DISK..."
diskutil unmountDisk "/dev/$DISK"

# Write image
echo "Writing image (this will take a few minutes)..."
if [[ "$IMAGE_PATH" == *.xz ]]; then
  xzcat "$IMAGE_PATH" | sudo dd of="/dev/r${DISK}" bs=1m status=progress
else
  sudo dd if="$IMAGE_PATH" of="/dev/r${DISK}" bs=1m status=progress
fi

# Re-mount the disk so the boot partition shows up under /Volumes
diskutil mountDisk "/dev/$DISK"

# Wait for bootfs to mount
echo ""
echo "Waiting for bootfs to mount..."
TIMEOUT=30
ELAPSED=0
while [[ ! -d /Volumes/bootfs ]]; do
  sleep 1
  ELAPSED=$((ELAPSED + 1))
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "Timed out waiting for /Volumes/bootfs — check the card and try again."
    exit 1
  fi
done

# Hash password
PI_HASH=$(echo "$PASSWORD" | openssl passwd -6 -stdin)

# Write firstrun.sh — used (rather than userconf.txt/ssh) so we can also
# inject the SSH public key, which those boot-partition flag files can't do.
echo "Writing firstrun.sh..."
{
  echo '#!/bin/bash'
  echo 'set -e'
  echo "/usr/lib/userconf-pi/userconf 'pi' '$PI_HASH'"
  echo 'systemctl enable ssh'
  if [[ -n "$PUBKEY" ]]; then
    echo 'install -o pi -g pi -m 700 -d /home/pi/.ssh'
    echo "echo '$PUBKEY' >> /home/pi/.ssh/authorized_keys"
    echo 'chown pi:pi /home/pi/.ssh/authorized_keys'
    echo 'chmod 600 /home/pi/.ssh/authorized_keys'
  fi
  echo 'rm -f /boot/firstrun.sh'
  echo "sed -i 's| systemd.run=[^ ]*||; s| systemd.run_success_action=[^ ]*||; s| systemd.unit=kernel-command-line.target||' /boot/cmdline.txt"
  echo 'exit 0'
} >/Volumes/bootfs/firstrun.sh
chmod +x /Volumes/bootfs/firstrun.sh

CMDLINE_FILE="/Volumes/bootfs/cmdline.txt"
if [[ -f "$CMDLINE_FILE" ]] && ! grep -q "firstrun.sh" "$CMDLINE_FILE"; then
  CMDLINE=$(cat "$CMDLINE_FILE")
  printf '%s systemd.run=/boot/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target\n' "$CMDLINE" >"$CMDLINE_FILE"
fi

# Eject
echo "Ejecting..."
diskutil eject "/dev/$DISK"

echo ""
echo "Done. Insert the card and power on the Pi."
echo "First boot runs setup then reboots itself — give it ~2 min, then:"
echo "  ssh pi@raspberrypi.local"
if [[ -n "$PUBKEY" ]]; then
  echo ""
  echo "To switch to key-based login, once you're in:"
  echo "  ssh-copy-id -i $KEY_FILE pi@raspberrypi.local"
fi
