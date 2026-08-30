#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export CAPTURE_DIR="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../install-node-exporter.sh"
  unset PI_SSH SSH_KEY_FILE VERSION
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

@test "targets PI_SSH over ssh" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "pi@testhost" "$CAPTURE_DIR/ssh.calls"
}

@test "passes -i SSH_KEY_FILE when set (CI mode)" {
  export PI_SSH="pi@testhost"
  export SSH_KEY_FILE="/tmp/fake-key"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- "-i /tmp/fake-key" "$CAPTURE_DIR/ssh.calls"
}

@test "omits -i when SSH_KEY_FILE is unset" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q -- "-i " "$CAPTURE_DIR/ssh.calls"
}

@test "defaults VERSION to 1.12.1" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "VERSION='1.12.1'" "$CAPTURE_DIR/ssh.calls"
}

@test "respects a custom VERSION" {
  export PI_SSH="pi@testhost"
  export VERSION="1.13.0"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "VERSION='1.13.0'" "$CAPTURE_DIR/ssh.calls"
}

@test "remote heredoc enables the textfile collector" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- "--collector.textfile" "$CAPTURE_DIR/ssh.stdin"
  grep -q "textfile_collector" "$CAPTURE_DIR/ssh.stdin"
}

@test "remote heredoc bootstraps the pi-provision sudoers file idempotently" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "/etc/sudoers.d/pi-provision" "$CAPTURE_DIR/ssh.stdin"
  grep -q -- "-f \"\$SUDOERS_FILE\"" "$CAPTURE_DIR/ssh.stdin"
}
