#!/usr/bin/env bash
set -euo pipefail

# Prompt for image path
read -rp "Path to image file: " IMAGE_PATH
IMAGE_PATH="${IMAGE_PATH/#\~/$HOME}"

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
PI_HASH=$(echo "$PASSWORD" | openssl passwd -5 -stdin)

# Build user-data
echo "Writing cloud-init config..."

{
  cat << 'HEADER'
#cloud-config

hostname: raspberrypi
manage_etc_hosts: true
ssh_pwauth: true

users:
  - name: pi
    groups: users,adm,dialout,audio,netdev,video,plugdev,cdrom,games,input,gpio,spi,i2c,render,sudo
    shell: /bin/bash
    lock_passwd: false
HEADER

  echo "    passwd: $PI_HASH"

  if [[ -n "$PUBKEY" ]]; then
    echo "    ssh_authorized_keys:"
    echo "      - $PUBKEY"
  fi
} > /Volumes/bootfs/user-data

# meta-data must exist
touch /Volumes/bootfs/meta-data

# Eject
echo "Ejecting..."
diskutil eject "/dev/$DISK"

echo ""
echo "Done. Insert the card, power on the Pi, then:"
echo "  ssh pi@raspberrypi.local"
