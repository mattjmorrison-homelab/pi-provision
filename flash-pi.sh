#!/usr/bin/env bash
# Tested against: Raspberry Pi OS Lite (Legacy, 64-bit) — Bookworm
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
PI_HASH=$(echo "$PASSWORD" | openssl passwd -6 -stdin)

# Write userconf.txt (creates the pi user with hashed password)
echo "Writing userconf.txt..."
echo "pi:$PI_HASH" > /Volumes/bootfs/userconf.txt

# Enable SSH
touch /Volumes/bootfs/ssh

# Write SSH public key to rootfs if available
if [[ -n "$PUBKEY" ]]; then
  SSH_DIR="/Volumes/rootfs/home/pi/.ssh"
  mkdir -p "$SSH_DIR"
  echo "$PUBKEY" > "$SSH_DIR/authorized_keys"
  chmod 700 "$SSH_DIR"
  chmod 600 "$SSH_DIR/authorized_keys"
  echo "SSH key written to rootfs."
fi

# Eject
echo "Ejecting..."
diskutil eject "/dev/$DISK"

echo ""
echo "Done. Insert the card, power on the Pi, then:"
echo "  ssh pi@raspberrypi.local"
