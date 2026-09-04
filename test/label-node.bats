#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export CAPTURE_DIR="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../label-node.sh"
  unset PI_SSH SSH_KEY_FILE LABEL
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

@test "defaults LABEL to hardware=serial-hdmi" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "LABEL='hardware=serial-hdmi'" "$CAPTURE_DIR/ssh.calls"
}

@test "respects a custom LABEL" {
  export PI_SSH="pi@testhost"
  export LABEL="foo=bar"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "LABEL='foo=bar'" "$CAPTURE_DIR/ssh.calls"
}

@test "remote heredoc bootstraps the pi-provision sudoers file" {
  export PI_SSH="pi@testhost"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "/etc/sudoers.d/pi-provision" "$CAPTURE_DIR/ssh.stdin"
}
