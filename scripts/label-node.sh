#!/usr/bin/env bash
# Sets a k3s node-label on a Pi already joined to the cluster via join-node.sh.
# Run this from anywhere with SSH access to the target Pi -- it edits the Pi's
# own k3s-agent config and restarts the service, no control-plane access
# needed. Or non-interactively from CI: set PI_SSH and SSH_KEY_FILE.
set -euo pipefail

LABEL="${LABEL:-hardware=serial-hdmi}"

if [[ -z "${PI_SSH:-}" ]]; then
  read -rp "Pi SSH target (e.g. pi@nodename.local): " PI_SSH

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
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_KEY_FILE:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY_FILE")
fi

echo ""
echo "Applying label on $PI_SSH..."
ssh -t "${SSH_OPTS[@]}" "$PI_SSH" "sudo LABEL='${LABEL}' bash -s" <<'EOF'
set -euo pipefail

# See install-node-exporter.sh for why this is written here too -- same
# shared, idempotent sudoers bootstrap, safe to run from any of the scripts
# that use it first.
SUDOERS_FILE=/etc/sudoers.d/pi-provision
if [[ ! -f "$SUDOERS_FILE" ]]; then
  cat >"$SUDOERS_FILE" <<'SUDOEOF'
# Managed by pi-provision -- lets its scripts re-run non-interactively (CI
# has no terminal to answer a sudo password prompt). Every script in this
# repo elevates its whole remote block via one `sudo ... bash -s` call
# rather than many piecemeal `sudo <cmd>` calls, partly because join-node.sh
# hands off to k3s's own upstream installer, which does its own internal
# per-command sudo escalation (cp/systemctl/mkdir/etc.) unpredictably across
# versions -- there's no stable, narrower set of commands to enumerate here.
# `bash -s` is therefore the actual privilege boundary: anyone who can run
# `sudo` non-interactively as `pi` can run arbitrary root code. That's the
# same trust level CI already has via the SSH key itself, so this doesn't
# widen anything -- it just removes the password prompt for it.
pi ALL=(root) NOPASSWD:SETENV: /usr/bin/bash -s
SUDOEOF
  chmod 440 "$SUDOERS_FILE"
fi

CONFIG=/etc/rancher/k3s/config.yaml

mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"

if grep -qF "\"${LABEL}\"" "$CONFIG" 2>/dev/null; then
  echo "Label already present in $CONFIG -- nothing to do."
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
