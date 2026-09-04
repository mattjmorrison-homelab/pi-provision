#!/usr/bin/env bash
# Validates the adhoc workflow's script/target combination and resolves
# the target's SSH host via pi-ssh-host.sh. taint-existing-nodes.sh is
# cluster-wide and must be dispatched with no target; every other script
# requires one. Prints the resolved ssh_host on success (nothing for
# taint-existing-nodes.sh, which has none).
#
# Usage: resolve-adhoc-target.sh <script> <target>
set -euo pipefail

SCRIPT="${1:?Usage: resolve-adhoc-target.sh <script> <target>}"
TARGET="${2:-}"

if [[ "$SCRIPT" == "taint-existing-nodes.sh" ]]; then
  if [[ -n "$TARGET" ]]; then
    echo "taint-existing-nodes.sh is cluster-wide -- leave target blank." >&2
    exit 1
  fi
  exit 0
fi

if [[ -z "$TARGET" ]]; then
  echo "target is required for $SCRIPT" >&2
  exit 1
fi

"$(dirname "$0")/pi-ssh-host.sh" "$TARGET"
