#!/usr/bin/env bats
# Only covers the safety gates that run before any real disk I/O -- see
# test/mocks/diskutil for why the image-write/mount/firstrun.sh steps aren't
# covered here.

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export CAPTURE_DIR="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../flash-pi-legacy.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "refuses to run when the expected image file is missing" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"File not found"* ]]
  [ ! -f "$CAPTURE_DIR/diskutil.calls" ]
}

@test "aborts without erasing when confirmation isn't exactly YES" {
  mkdir -p "$HOME/Downloads"
  touch "$HOME/Downloads/2026-06-18-raspios-trixie-armhf-lite.img.xz"
  run bash -c "printf 'disk4\nyes\n' | bash '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Aborted."* ]]
  ! grep -q unmountDisk "$CAPTURE_DIR/diskutil.calls"
}
