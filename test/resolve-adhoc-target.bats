#!/usr/bin/env bats

setup() {
  export FLEET_YAML="$BATS_TEST_DIRNAME/fixtures/fleet.yaml"
  SCRIPT="$BATS_TEST_DIRNAME/../resolve-adhoc-target.sh"
}

@test "resolves the ssh_host for a normal script/target pair" {
  run bash "$SCRIPT" apply-updates.sh pi1
  [ "$status" -eq 0 ]
  [ "$output" = "pi@pi1.local" ]
}

@test "fails when target is missing for a normal script" {
  run bash "$SCRIPT" apply-updates.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"target is required"* ]]
}

@test "succeeds with no output when taint-existing-nodes.sh has no target" {
  run bash "$SCRIPT" taint-existing-nodes.sh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails when taint-existing-nodes.sh is given a target" {
  run bash "$SCRIPT" taint-existing-nodes.sh pi1
  [ "$status" -eq 1 ]
  [[ "$output" == *"is cluster-wide"* ]]
}

@test "fails with the unknown-pi error for a nonexistent target" {
  run bash "$SCRIPT" apply-updates.sh nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"isn't a known pi in fleet.yaml"* ]]
}
