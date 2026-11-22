#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

./scripts/ca-trust.sh
./scripts/install-node-exporter.sh
