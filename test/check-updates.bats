#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export CAPTURE_DIR="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../check-updates.sh"
  unset PI_SSH SSH_KEY_FILE PI_NAME
}

@test "fails with no target given when the prompt is answered with an empty line" {
  run bash -c "printf '\n' | bash '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No target given."* ]]
}

@test "skips the prompt when PI_SSH is already set" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "derives PI_NAME from the host part of PI_SSH" {
  export PI_SSH="pi@pi1.local"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "PI_NAME='pi1'" "$CAPTURE_DIR/ssh.calls"
}

@test "respects an explicit PI_NAME override" {
  export PI_SSH="pi@testhost"
  export PI_NAME="custom-name"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "PI_NAME='custom-name'" "$CAPTURE_DIR/ssh.calls"
}

@test "passes -i SSH_KEY_FILE when set (CI mode)" {
  export PI_SSH="pi@testhost"
  export SSH_KEY_FILE="/tmp/fake-key"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- "-i /tmp/fake-key" "$CAPTURE_DIR/ssh.calls"
}

@test "remote heredoc only refreshes the index, never upgrades" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "apt-get update" "$CAPTURE_DIR/ssh.stdin"
  ! grep -q "apt-get upgrade" "$CAPTURE_DIR/ssh.stdin"
}

@test "remote heredoc writes the node_apt_upgrades_pending metric" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "node_apt_upgrades_pending" "$CAPTURE_DIR/ssh.stdin"
  grep -q "apt-updates.prom" "$CAPTURE_DIR/ssh.stdin"
}
