#!/usr/bin/env bash
# Actually applies pending apt upgrades on a Pi -- the manually-triggered
# counterpart to check-updates.sh's notify-only metric. Run this yourself
# (or dispatch it) once you've seen the PiUpdatesAvailable alert and decided
# it's a good time to upgrade an unattended board. Refreshes the same
# textfile metric afterward so the alert clears. Run against any Pi with SSH
# access, or non-interactively from CI: set PI_SSH and SSH_KEY_FILE.
#
# Requires the /etc/sudoers.d/pi-provision NOPASSWD entry that
# install-node-exporter.sh/label-node.sh bootstrap on first run -- run one
# of those against a Pi before this one.
set -euo pipefail

if [[ -z "${PI_SSH:-}" ]]; then
  read -rp "Pi SSH target (e.g. pi@nodename.local): " PI_SSH

  if [[ -z "$PI_SSH" ]]; then
    echo "No target given."
    exit 1
  fi

  echo ""
  echo "Target node: $PI_SSH"
  echo "This will run 'apt-get upgrade -y' -- packages will actually be installed."
  read -rp "Continue? [y/N] " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

PI_NAME="${PI_NAME:-${PI_SSH#*@}}"
PI_NAME="${PI_NAME%%.*}"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_KEY_FILE:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY_FILE")
fi

echo "Applying updates on $PI_SSH..."
ssh -t "${SSH_OPTS[@]}" "$PI_SSH" "sudo PI_NAME='${PI_NAME}' bash -s" <<'EOF'
set -euo pipefail

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

COUNT="$(apt list --upgradable 2>/dev/null | grep -vc '^Listing' || true)"
echo "Upgradable packages remaining on ${PI_NAME}: ${COUNT}"

METRICS_DIR=/var/lib/node_exporter/textfile_collector
METRICS_FILE="${METRICS_DIR}/apt-updates.prom"
TMP_FILE="${METRICS_FILE}.tmp.$$"

mkdir -p "$METRICS_DIR"
{
  echo "# HELP node_apt_upgrades_pending Number of packages with an available apt upgrade"
  echo "# TYPE node_apt_upgrades_pending gauge"
  echo "node_apt_upgrades_pending{pi=\"${PI_NAME}\"} ${COUNT}"
} >"$TMP_FILE"
mv "$TMP_FILE" "$METRICS_FILE"
EOF

echo "Done."
