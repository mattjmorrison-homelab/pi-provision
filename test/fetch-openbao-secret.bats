#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export CAPTURE_DIR="$BATS_TEST_TMPDIR"
  export VAULT_ADDR="http://vault.test"
  export JWT_FILE="$BATS_TEST_TMPDIR/jwt"
  echo "fake-jwt" > "$JWT_FILE"
  SCRIPT="$BATS_TEST_DIRNAME/../fetch-openbao-secret.sh"
  unset CURL_LOGIN_TOKEN CURL_KV_VALUE
}

@test "prints the fetched secret value on success" {
  export CURL_KV_VALUE="super-secret"
  run bash "$SCRIPT" test-role homelab/pi/pi1/private-key
  [ "$status" -eq 0 ]
  [ "$output" = "super-secret" ]
}

@test "logs in with this pod's JWT against the given role" {
  run bash "$SCRIPT" my-role homelab/pi/pi1/private-key
  [ "$status" -eq 0 ]
  grep -q "auth/kubernetes/login" "$CAPTURE_DIR/curl.calls"
}

@test "reads the given kv path" {
  run bash "$SCRIPT" test-role homelab/pi/pi1/private-key
  [ "$status" -eq 0 ]
  grep -q "v1/kv/data/homelab/pi/pi1/private-key" "$CAPTURE_DIR/curl.calls"
}

@test "fails clearly when login returns no client token" {
  export CURL_LOGIN_TOKEN=""
  run bash "$SCRIPT" test-role homelab/pi/pi1/private-key
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to return a client token"* ]]
}

@test "fails clearly when the kv path has no value" {
  export CURL_KV_VALUE=""
  run bash "$SCRIPT" test-role homelab/pi/pi1/private-key
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to fetch"* ]]
}

@test "fails when called without both arguments" {
  run bash "$SCRIPT" only-one-arg
  [ "$status" -ne 0 ]
}
