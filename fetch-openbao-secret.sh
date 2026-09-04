#!/usr/bin/env bash
# Logs into OpenBao via this pod's Kubernetes ServiceAccount token and
# reads one KV secret, printing its value to stdout. Used by the adhoc/
# scheduled/sync GitHub Actions workflows to fetch each Pi's SSH private
# key (and, for join-node.sh, the shared k3s join token) without storing
# credentials anywhere in this repo. Requires VAULT_ADDR in the
# environment.
#
# Usage: fetch-openbao-secret.sh <role> <kv-path>
set -euo pipefail

ROLE="${1:?Usage: fetch-openbao-secret.sh <role> <kv-path>}"
KV_PATH="${2:?Usage: fetch-openbao-secret.sh <role> <kv-path>}"
JWT_FILE="${JWT_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/token}"

JWT="$(cat "$JWT_FILE")"
LOGIN_PAYLOAD="$(jq -n --arg jwt "$JWT" --arg role "$ROLE" '{jwt: $jwt, role: $role}')"
CLIENT_TOKEN="$(curl -sf -X POST "$VAULT_ADDR/v1/auth/kubernetes/login" -d "$LOGIN_PAYLOAD" | jq -r '.auth.client_token')"
if [[ -z "$CLIENT_TOKEN" || "$CLIENT_TOKEN" == "null" ]]; then
  echo "Vault login for role $ROLE failed to return a client token" >&2
  exit 1
fi

VALUE="$(curl -sf -H "X-Vault-Token: $CLIENT_TOKEN" "$VAULT_ADDR/v1/kv/data/$KV_PATH" | jq -r '.data.data.value')"
if [[ -z "$VALUE" || "$VALUE" == "null" ]]; then
  echo "Failed to fetch $KV_PATH from OpenBao" >&2
  exit 1
fi
echo "$VALUE"
