#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

./scripts/ca-trust.sh
./scripts/join-node.sh
LABEL="hardware=serial-hdmi" ./scripts/label-node.sh
