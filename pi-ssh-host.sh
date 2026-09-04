#!/usr/bin/env bash
# Looks up a Pi's SSH target from fleet.yaml by name. Single source of
# truth for this lookup -- used by the adhoc/scheduled/sync GitHub Actions
# workflows to resolve PI_SSH before running a script against a target.
#
# Usage: pi-ssh-host.sh <name>
set -euo pipefail

NAME="${1:?Usage: pi-ssh-host.sh <name>}"
FLEET_YAML="${FLEET_YAML:-fleet.yaml}"

HOST="$(yq -r ".pis.\"${NAME}\".ssh_host // \"\"" "$FLEET_YAML")"
if [[ -z "$HOST" ]]; then
  echo "'$NAME' isn't a known pi in fleet.yaml -- add it there (and to admin-openbao) first." >&2
  exit 1
fi
echo "$HOST"
