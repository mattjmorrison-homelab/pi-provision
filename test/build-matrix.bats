#!/usr/bin/env bats

setup() {
  export FLEET_YAML="$BATS_TEST_DIRNAME/fixtures/fleet.yaml"
  SCRIPT="$BATS_TEST_DIRNAME/../build-matrix.sh"
}

@test "includes every target for tasks matching the given trigger" {
  run bash "$SCRIPT" sync
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "install-node-exporter.sh"
  echo "$output" | grep -q '"pi1"'
  echo "$output" | grep -q '"pizero"'
}

@test "excludes tasks with a different trigger" {
  run bash "$SCRIPT" sync
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "check-updates.sh"
}

@test "produces an empty include list when nothing matches" {
  run bash "$SCRIPT" nonexistent-trigger
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"include"'
  ! echo "$output" | grep -q '"script"'
}

@test "carries each task's env through to its matrix entries" {
  run bash "$SCRIPT" adhoc
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "hardware=serial-hdmi"
}

@test "fails when called without a trigger" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}
