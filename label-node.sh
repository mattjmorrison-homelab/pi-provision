#!/usr/bin/env bash
# Sets a k3s node-label on a Pi already joined to the cluster via join-node.sh.
# Run this from anywhere with SSH access to the target Pi — it edits the Pi's
# own k3s-agent config and restarts the service, no control-plane access needed.
set -euo pipefail

LABEL="${LABEL:-hardware=serial-hdmi}"

read -rp "Pi SSH target (e.g. pi@192.168.68.101 or pi@nodename.local): " PI_SSH

if [[ -z "$PI_SSH" ]]; then
  echo "No target given."
  exit 1
fi

echo ""
echo "Target node: $PI_SSH"
echo "Label:       $LABEL"
read -rp "Continue? [y/N] " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

echo ""
echo "Applying label on $PI_SSH..."
ssh -t "$PI_SSH" "sudo LABEL='${LABEL}' bash -s" <<'EOF'
set -euo pipefail
CONFIG=/etc/rancher/k3s/config.yaml

mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"

if grep -qF "\"${LABEL}\"" "$CONFIG" 2>/dev/null; then
  echo "Label already present in $CONFIG — nothing to do."
elif grep -qE '^node-label:' "$CONFIG"; then
  sed -i "/^node-label:/a\\  - \"${LABEL}\"" "$CONFIG"
  echo "Added label to existing node-label list."
else
  {
    echo "node-label:"
    echo "  - \"${LABEL}\""
  } >>"$CONFIG"
  echo "Created node-label list with label."
fi

systemctl restart k3s-agent
EOF

echo ""
echo "Done. Verify from the control plane with:"
echo "  kubectl get nodes --show-labels"
