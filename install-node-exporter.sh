#!/usr/bin/env bash
# Installs node_exporter as a systemd service on a Pi that is NOT a k3s cluster
# member (join-node.sh handles metrics for cluster nodes via the in-cluster
# DaemonSet). Run this from anywhere with SSH access to the target Pi, or
# non-interactively by CI (set PI_SSH and SSH_KEY_FILE) -- same script serves
# both.
#
# Only enables the collectors we actually want: disk space, RAM, CPU, and
# SoC temperature (via the standard Linux thermal_zone/hwmon sysfs paths,
# which Raspberry Pi OS populates natively) -- everything else is disabled
# to keep the footprint small on constrained boards (e.g. the 512MB Pi 1).
set -euo pipefail

# Pinned to match the version running in-cluster (homelab-node-exporter).
VERSION="${VERSION:-1.12.1}"

if [[ -z "${PI_SSH:-}" ]]; then
  read -rp "Pi SSH target (e.g. pi@nodename.local): " PI_SSH

  if [[ -z "$PI_SSH" ]]; then
    echo "No target given."
    exit 1
  fi

  echo ""
  echo "Target node: $PI_SSH"
  echo "Version:     $VERSION"
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
echo "Installing node_exporter on $PI_SSH..."
ssh -t "${SSH_OPTS[@]}" "$PI_SSH" "sudo VERSION='${VERSION}' bash -s" <<'EOF'
set -euo pipefail

# Bootstraps passwordless sudo for the exact commands pi-provision's scripts
# need, so every run after this first one (including from CI) can skip the
# password prompt. Written once, idempotently, from inside this same
# human-authorized `sudo bash -s` elevation.
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

if systemctl is-active --quiet node_exporter 2>/dev/null; then
  echo "node_exporter already running -- reinstalling binary and refreshing service."
fi

case "$(uname -m)" in
  aarch64) ARCH="arm64" ;;
  armv7l)  ARCH="armv7" ;;
  armv6l)  ARCH="armv6" ;;
  *)
    echo "Unrecognized architecture: $(uname -m)"
    exit 1
    ;;
esac

TARBALL="node_exporter-${VERSION}.linux-${ARCH}.tar.gz"
URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/${TARBALL}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "Downloading ${URL}..."
curl -sfL "$URL" -o "${WORKDIR}/${TARBALL}"
tar -xzf "${WORKDIR}/${TARBALL}" -C "$WORKDIR"

install -o root -g root -m 755 \
  "${WORKDIR}/node_exporter-${VERSION}.linux-${ARCH}/node_exporter" \
  /usr/local/bin/node_exporter

if ! id node_exporter >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
fi

cat >/etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Prometheus node_exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address=:9100 \
  --collector.disable-defaults \
  --collector.filesystem \
  --collector.diskstats \
  --collector.meminfo \
  --collector.cpu \
  --collector.thermal_zone \
  --collector.hwmon \
  --collector.textfile \
  --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT

if ! getent group textfile-collector >/dev/null; then
  groupadd --system textfile-collector
fi
usermod -a -G textfile-collector node_exporter
install -d -o root -g textfile-collector -m 2775 /var/lib/node_exporter/textfile_collector

systemctl daemon-reload
systemctl enable --now node_exporter
systemctl restart node_exporter

echo "node_exporter installed and running on :9100."
EOF

echo ""
echo "Done. Verify with:"
echo "  curl http://<pi-ip>:9100/metrics | grep -E 'node_(filesystem|memory|cpu|thermal_zone|hwmon|textfile)'"
