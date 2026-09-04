#!/usr/bin/env bash
# Refreshes apt's package index on a Pi and records how many packages are
# upgradable as a node_exporter textfile metric, so Prometheus can alert on
# it (see k8s-prometheus's PiUpdatesAvailable rule) -- notify-only, this
# script never installs anything. Run against any Pi with SSH access, or
# non-interactively from CI: set PI_SSH and SSH_KEY_FILE.
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
fi

PI_NAME="${PI_NAME:-${PI_SSH#*@}}"
PI_NAME="${PI_NAME%%.*}"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_KEY_FILE:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY_FILE")
fi

echo "Checking for updates on $PI_SSH..."
# shellcheck disable=SC2029 # intentional: PI_NAME is meant to expand locally
# here, becoming a literal env-var assignment on the remote sudo command line.
ssh "${SSH_OPTS[@]}" "$PI_SSH" "sudo PI_NAME='${PI_NAME}' bash -s" <<'EOF'
set -euo pipefail

apt-get update -qq

COUNT="$(apt list --upgradable 2>/dev/null | grep -vc '^Listing' || true)"
echo "Upgradable packages on ${PI_NAME}: ${COUNT}"

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
