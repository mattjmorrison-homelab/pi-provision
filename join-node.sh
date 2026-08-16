#!/usr/bin/env bash
# Joins a Pi already flashed via flash-pi.sh / flash-pi-legacy.sh to the homelab
# k3s cluster as an agent node. Run this ON the control plane (it reads the join
# token locally) — it only reaches out over SSH to the target Pi.
set -euo pipefail

CONTROL_HOST="${CONTROL_HOST:-control.morrisons.site}"
# Pi nodes don't run anything by default; workloads opt in with a matching
# toleration (and usually a nodeSelector) in their own deployment manifest.
NODE_TAINT="${NODE_TAINT:-dedicated=pi:NoSchedule}"

read -rp "Pi SSH target (e.g. pi@192.168.68.101 or pi@nodename.local): " PI_SSH

if [[ -z "$PI_SSH" ]]; then
  echo "No target given."
  exit 1
fi

echo ""
echo "Control plane: $CONTROL_HOST (local)"
echo "Target node:   $PI_SSH"
echo "Node taint:    $NODE_TAINT"
read -rp "Continue? [y/N] " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "Reading local join token..."
TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
if [[ -z "$TOKEN" ]]; then
  echo "Failed to read node token — is k3s running on this machine?"
  exit 1
fi

echo "Checking cgroup memory support on $PI_SSH..."
CGROUP_OK=$(ssh "$PI_SSH" "grep -qw memory /sys/fs/cgroup/cgroup.controllers 2>/dev/null && echo yes || echo no")

if [[ "$CGROUP_OK" == "no" ]]; then
  echo "cgroup memory controller is off — enabling it and rebooting $PI_SSH..."
  ssh -t "$PI_SSH" '
    set -e
    CMDLINE_FILE=/boot/firmware/cmdline.txt
    [[ -f "$CMDLINE_FILE" ]] || CMDLINE_FILE=/boot/cmdline.txt
    if ! grep -q "cgroup_enable=memory" "$CMDLINE_FILE"; then
      sudo sed -i "s/\$/ cgroup_memory=1 cgroup_enable=memory/" "$CMDLINE_FILE"
    fi
  '
  ssh -t "$PI_SSH" "sudo reboot" || true

  PI_HOST="${PI_SSH#*@}"
  echo "Waiting for $PI_HOST to go down..."
  sleep 15

  echo "Waiting for $PI_HOST to come back (ping)..."
  TIMEOUT=120
  ELAPSED=0
  until ping -c 1 -W 2 "$PI_HOST" >/dev/null 2>&1; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
      echo "Timed out waiting for $PI_HOST to come back up."
      exit 1
    fi
  done
  echo "Back up — giving sshd a few seconds to start..."
  sleep 10
fi

echo "Disabling swap on $PI_SSH..."
ssh -t "$PI_SSH" '
  if systemctl is-enabled dphys-swapfile >/dev/null 2>&1; then
    sudo systemctl disable --now dphys-swapfile
  fi
  sudo swapoff -a || true
'

echo "Installing k3s agent on $PI_SSH (taint: $NODE_TAINT)..."
ssh -t "$PI_SSH" "curl -sfL https://get.k3s.io | K3S_URL=https://${CONTROL_HOST}:6443 K3S_TOKEN=${TOKEN} sh -s - --node-taint=${NODE_TAINT}"

echo ""
echo "Done. Verify with:"
echo "  kubectl get nodes"
