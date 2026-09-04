#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export CAPTURE_DIR="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../join-node.sh"
  unset PI_SSH SSH_KEY_FILE K3S_JOIN_TOKEN CONTROL_HOST NODE_TAINT CGROUP_STATE
  export CGROUP_STATE="yes"
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

@test "uses K3S_JOIN_TOKEN directly when set, skipping the local sudo cat" {
  export PI_SSH="pi@testhost"
  export K3S_JOIN_TOKEN="ci-supplied-token"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$CAPTURE_DIR/sudo.calls" ]
  grep -q "K3S_TOKEN=ci-supplied-token" "$CAPTURE_DIR/ssh.calls"
}

@test "falls back to local sudo cat for the join token when K3S_JOIN_TOKEN is unset" {
  export PI_SSH="pi@testhost"
  export MOCK_JOIN_TOKEN="from-disk-token"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "cat /var/lib/rancher/k3s/server/node-token" "$CAPTURE_DIR/sudo.calls"
  grep -q "K3S_TOKEN=from-disk-token" "$CAPTURE_DIR/ssh.calls"
}

@test "passes -i SSH_KEY_FILE on every ssh call when set (CI mode)" {
  export PI_SSH="pi@testhost"
  export K3S_JOIN_TOKEN="tok"
  export SSH_KEY_FILE="/tmp/fake-key"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -E '^ssh ' "$CAPTURE_DIR/ssh.calls" | grep -qv -- "-i /tmp/fake-key"
}

@test "skips the cgroup-enable reboot dance when cgroups are already on" {
  export PI_SSH="pi@testhost"
  export K3S_JOIN_TOKEN="tok"
  export CGROUP_STATE="yes"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$CAPTURE_DIR/ping.calls" ]
  ! grep -q "sudo reboot" "$CAPTURE_DIR/ssh.calls"
}

@test "reboots and waits for the host when cgroups are off" {
  export PI_SSH="pi@testhost"
  export K3S_JOIN_TOKEN="tok"
  export CGROUP_STATE="no"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "sudo reboot" "$CAPTURE_DIR/ssh.calls"
  grep -q "ping" "$CAPTURE_DIR/ping.calls"
}

@test "installs k3s against CONTROL_HOST with the given NODE_TAINT" {
  export PI_SSH="pi@testhost"
  export K3S_JOIN_TOKEN="tok"
  export CONTROL_HOST="control.example.com"
  export NODE_TAINT="custom=taint:NoSchedule"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "K3S_URL=https://control.example.com:6443" "$CAPTURE_DIR/ssh.calls"
  grep -q -- "--node-taint=custom=taint:NoSchedule" "$CAPTURE_DIR/ssh.calls"
}
