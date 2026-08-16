#!/usr/bin/env bash
# Installs node_exporter as a systemd service on a Pi that is NOT a k3s cluster
# member (join-node.sh handles metrics for cluster nodes via the in-cluster
# DaemonSet). Run this from anywhere with SSH access to the target Pi.
#
# Only enables the collectors we actually want: disk space, RAM, CPU, and
# SoC temperature (via the standard Linux thermal_zone/hwmon sysfs paths,
# which Raspberry Pi OS populates natively) -- everything else is disabled
# to keep the footprint small on constrained boards (e.g. the 512MB Pi 1).
set -euo pipefail

# Pinned to match the version running in-cluster (homelab-node-exporter).
VERSION="${VERSION:-1.12.1}"

read -rp "Pi SSH target (e.g. pi@192.168.68.101 or pi@nodename.local): " PI_SSH

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

echo ""
echo "Installing node_exporter on $PI_SSH..."
ssh -t "$PI_SSH" "sudo VERSION='${VERSION}' bash -s" <<'EOF'
set -euo pipefail

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
  --collector.hwmon
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now node_exporter
systemctl restart node_exporter

echo "node_exporter installed and running on :9100."
EOF

echo ""
echo "Done. Verify with:"
echo "  curl http://<pi-ip>:9100/metrics | grep -E 'node_(filesystem|memory|cpu|thermal_zone|hwmon)'"
echo ""
echo "Then add a static target for this Pi's IP:9100 to homelab-prometheus's"
echo "scrape_configs (job: node-exporter-external, or similar) to have it scraped."
