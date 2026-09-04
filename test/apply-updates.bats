#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export CAPTURE_DIR="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../apply-updates.sh"
  unset PI_SSH SSH_KEY_FILE PI_NAME
}

@test "fails with no target given when the prompt is answered with an empty line" {
  run bash -c "printf '\n' | bash '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No target given."* ]]
}

@test "aborts when the confirmation prompt isn't answered y" {
  run bash -c "printf 'pi@testhost\nn\n' | bash '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Aborted."* ]]
}

@test "skips every prompt when PI_SSH is already set" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Continue?"* ]]
}

@test "passes -i SSH_KEY_FILE when set (CI mode)" {
  export PI_SSH="pi@testhost"
  export SSH_KEY_FILE="/tmp/fake-key"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- "-i /tmp/fake-key" "$CAPTURE_DIR/ssh.calls"
}

@test "remote heredoc actually upgrades, non-interactively" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "apt-get update" "$CAPTURE_DIR/ssh.stdin"
  grep -q "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" "$CAPTURE_DIR/ssh.stdin"
}

@test "remote heredoc refreshes the metric after upgrading" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "node_apt_upgrades_pending" "$CAPTURE_DIR/ssh.stdin"
}
