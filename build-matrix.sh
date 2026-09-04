#!/usr/bin/env bash
# Builds a GitHub Actions matrix (as {"include": [...]} JSON) from every
# fleet.yaml task matching the given trigger. Used by the scheduled/sync
# workflows to discover what to run without duplicating this yq query in
# each one.
#
# Usage: build-matrix.sh <trigger>
set -euo pipefail

TRIGGER="${1:?Usage: build-matrix.sh <trigger>}"
FLEET_YAML="${FLEET_YAML:-fleet.yaml}"

# shellcheck disable=SC2016 # $t is yq's own bind-variable syntax, not a shell var
ENTRIES="$(yq -o=json "
  [.tasks[] | select(.trigger == \"${TRIGGER}\") | . as \$t |
    \$t.targets[] | {\"script\": \$t.script, \"target\": ., \"env\": (\$t.env // {})}]
" "$FLEET_YAML")"
echo "{\"include\":${ENTRIES}}"
