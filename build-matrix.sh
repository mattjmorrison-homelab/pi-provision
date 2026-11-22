#!/usr/bin/env bash
set -euo pipefail

FLEET_DIR="${FLEET_DIR:-fleet}"

find "$FLEET_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
  | sort \
  | jq -R -s -c 'split("\n") | map(select(length > 0)) | map({target: .}) | {include: .}'
