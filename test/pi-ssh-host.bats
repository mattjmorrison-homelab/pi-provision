#!/usr/bin/env bats

setup() {
  export FLEET_YAML="$BATS_TEST_DIRNAME/fixtures/fleet.yaml"
  SCRIPT="$BATS_TEST_DIRNAME/../pi-ssh-host.sh"
}

@test "prints the ssh_host for a known pi" {
  run bash "$SCRIPT" pi1
  [ "$status" -eq 0 ]
  [ "$output" = "pi@pi1.local" ]
}

@test "fails with a clear error for an unknown pi" {
  run bash "$SCRIPT" nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"isn't a known pi in fleet.yaml"* ]]
}

@test "fails when called without a name" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}
