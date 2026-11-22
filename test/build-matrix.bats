#!/usr/bin/env bats

setup() {
  export FLEET_DIR="$BATS_TEST_TMPDIR/fleet"
  mkdir -p "$FLEET_DIR/pi5-8" "$FLEET_DIR/pi5-16" "$FLEET_DIR/pi1"
  SCRIPT="$BATS_TEST_DIRNAME/../build-matrix.sh"
}

@test "includes every pi under fleet/" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"pi1"'
  echo "$output" | grep -q '"pi5-8"'
  echo "$output" | grep -q '"pi5-16"'
}

@test "produces a single line of output" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 1 ]
}

@test "sorts targets for deterministic output" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = '{"include":[{"target":"pi1"},{"target":"pi5-16"},{"target":"pi5-8"}]}' ]
}

@test "produces an empty include list when fleet/ has no entries" {
  rm -rf "$FLEET_DIR"
  mkdir -p "$FLEET_DIR"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = '{"include":[]}' ]
}
