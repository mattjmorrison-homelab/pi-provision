#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export CAPTURE_DIR="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../taint-existing-nodes.sh"
  unset NODE_TAINT KUBECONFIG MOCK_NODES
}

@test "taints every node returned by the control-plane selector" {
  export MOCK_NODES="pi5-8 pi5-16"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "taint nodes pi5-8 dedicated=pi:NoSchedule --overwrite" "$CAPTURE_DIR/kubectl.calls"
  grep -q "taint nodes pi5-16 dedicated=pi:NoSchedule --overwrite" "$CAPTURE_DIR/kubectl.calls"
}

@test "respects a custom NODE_TAINT" {
  export MOCK_NODES="pi5-8"
  export NODE_TAINT="custom=taint:NoSchedule"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "taint nodes pi5-8 custom=taint:NoSchedule --overwrite" "$CAPTURE_DIR/kubectl.calls"
}

@test "does nothing but still succeeds when there are no non-control-plane nodes" {
  export MOCK_NODES=""
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$CAPTURE_DIR/kubectl.calls" ] || ! grep -q "taint" "$CAPTURE_DIR/kubectl.calls"
}
