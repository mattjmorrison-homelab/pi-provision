#!/usr/bin/env bash
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://k8s-openbao.openbao.svc:8200}"

if [[ -z "${PI_SSH:-}" ]]; then
  echo "PI_SSH must be set" >&2
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_KEY_FILE:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY_FILE")
fi

CA_PUBLIC_KEY="$(curl -sf "$VAULT_ADDR/v1/ssh/public_key")"
if [[ -z "$CA_PUBLIC_KEY" ]]; then
  echo "Failed to fetch CA public key from $VAULT_ADDR/v1/ssh/public_key" >&2
  exit 1
fi

echo "Configuring SSH CA trust on $PI_SSH..."
ssh -t "${SSH_OPTS[@]}" "$PI_SSH" "sudo CA_PUBLIC_KEY='${CA_PUBLIC_KEY}' bash -s" <<'EOF'
set -euo pipefail

SUDOERS_FILE=/etc/sudoers.d/pi-provision
if [[ ! -f "$SUDOERS_FILE" ]]; then
  cat >"$SUDOERS_FILE" <<'SUDOEOF'
pi ALL=(root) NOPASSWD:SETENV: /usr/bin/bash -s
SUDOEOF
  chmod 440 "$SUDOERS_FILE"
fi

CA_FILE=/etc/ssh/openbao_ca.pub
echo "$CA_PUBLIC_KEY" > "$CA_FILE"
chmod 644 "$CA_FILE"

SSHD_CONFIG=/etc/ssh/sshd_config
if ! grep -qF "TrustedUserCAKeys $CA_FILE" "$SSHD_CONFIG"; then
  echo "TrustedUserCAKeys $CA_FILE" >> "$SSHD_CONFIG"
  systemctl restart sshd
fi
EOF
