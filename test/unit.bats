# ABOUTME: Unit tests for swappy: argument parsing, profile-name validation,
# ABOUTME: empty-state behavior, and error messages. Backend-independent.

load helpers

setup() {
  setup_home
}

teardown() {
  teardown_home
}

@test "help exits 0 and shows usage" {
  run "$SWAPPY" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"save"* ]]
  [[ "$output" == *"next"* ]]
}

@test "no arguments shows usage and exits 1" {
  run "$SWAPPY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "unknown command errors with exit 1" {
  run "$SWAPPY" frobnicate extra
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
}

@test "save rejects invalid profile names" {
  setup_file_backend '{"claudeAiOauth":{"accessToken":"tok"}}'
  for bad in "Bad Name" "UPPER" "dots.dots" "sla/sh" ""; do
    run "$SWAPPY" save "$bad"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid profile name"* ]]
  done
}

@test "save without a name errors" {
  run "$SWAPPY" save
  [ "$status" -eq 1 ]
}

@test "ls with no profiles is friendly and exits 0" {
  run "$SWAPPY" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"no profiles"* ]]
  [[ "$output" == *"swappy save"* ]]
}

@test "use with unknown profile lists valid names and exits 1" {
  setup_file_backend '{"claudeAiOauth":{"accessToken":"tok"}}'
  "$SWAPPY" save alpha
  run "$SWAPPY" use nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no profile named 'nope'"* ]]
  [[ "$output" == *"alpha"* ]]
}

@test "save with no credential store errors naming what was checked" {
  export SWAPPY_BACKEND=""
  run env -u SWAPPY_BACKEND "$SWAPPY" save alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Claude Code login found"* ]]
}

@test "reserved command words cannot be used as profile names" {
  setup_file_backend '{"claudeAiOauth":{"accessToken":"tok"}}'
  for reserved in save use next ls rm help; do
    run "$SWAPPY" save "$reserved"
    [ "$status" -eq 1 ]
    [[ "$output" == *"reserved"* ]]
  done
}
