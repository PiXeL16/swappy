# ABOUTME: Tests for `swappy usage` and `swappy observe`: threshold switching against a real local
# ABOUTME: HTTP stub, safety refusals (errors, locks, identity), and scheduler job generation.

load helpers

TOKEN_A='{"claudeAiOauth":{"accessToken":"access-a","refreshToken":"refresh-a"}}'
TOKEN_B='{"claudeAiOauth":{"accessToken":"access-b","refreshToken":"refresh-b"}}'
TOKEN_C='{"claudeAiOauth":{"accessToken":"access-c","refreshToken":"refresh-c"}}'

setup() {
  setup_home
  setup_file_backend "$TOKEN_A"
  export SWAPPY_NO_NOTIFY=1
  export SWAPPY_OBSERVE_UNIT_DIR="$TEST_HOME/units"
  start_usage_stub
}

teardown() {
  stop_usage_stub
  teardown_home
}

# alpha saved and live, beta saved
two_profiles() {
  "$SWAPPY" save alpha
  simulate_login uuid-beta-2222 beta@example.com "$TOKEN_B"
  "$SWAPPY" save beta
  "$SWAPPY" use alpha
}

three_profiles() {
  "$SWAPPY" save alpha
  simulate_login uuid-beta-2222 beta@example.com "$TOKEN_B"
  "$SWAPPY" save beta
  simulate_login uuid-gamma-3333 gamma@example.com "$TOKEN_C"
  "$SWAPPY" save gamma
  "$SWAPPY" use alpha
}

mark_exhausted() { # name until
  mkdir -p "$HOME/.config/swappy"
  python3 - "$HOME/.config/swappy/observe.json" "$1" "$2" <<'PY'
import json, sys
json.dump({"version": 1, "exhausted": {sys.argv[2]: sys.argv[3]}}, open(sys.argv[1], "w"))
PY
}

# ---------- swappy usage ----------

@test "usage prints 5h and 7d utilization of the live account" {
  stub_respond 200 "$(usage_body 42 10)"
  run "$SWAPPY" usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"5h"* ]]
  [[ "$output" == *"42"* ]]
  [[ "$output" == *"7d"* ]]
  [[ "$output" == *"10"* ]]
}

@test "usage sends the live access token as a bearer header to the usage path only" {
  stub_respond 200 "$(usage_body 1 1)"
  run "$SWAPPY" usage
  [ "$status" -eq 0 ]
  grep -q '"auth": "Bearer access-a"' "$STUB_DIR/requests.log"
  grep -q '"path": "/api/oauth/usage"' "$STUB_DIR/requests.log"
  grep -q '"beta": "oauth-2025-04-20"' "$STUB_DIR/requests.log"
}

@test "the bearer token never appears in any process argv" {
  write_live_secret '{"claudeAiOauth":{"accessToken":"tok-argv-canary-8812","refreshToken":"r"}}'
  stub_respond 200 "$(usage_body 1 1)"
  run "$SWAPPY" usage
  [ "$status" -eq 0 ]
  grep -q 'Bearer tok-argv-canary-8812' "$STUB_DIR/requests.log"
  [ -s "$STUB_DIR/ps.log" ]
  ! grep -q 'tok-argv-canary-8812' "$STUB_DIR/ps.log"
}

@test "usage reports an HTTP error and exits 1" {
  stub_respond 429 '{"error":"rate limited"}'
  run "$SWAPPY" usage
  [ "$status" -eq 1 ]
  [[ "$output" == *"429"* ]]
}

@test "usage reports unparseable data and exits 1" {
  stub_respond 200 'not json at all'
  run "$SWAPPY" usage
  [ "$status" -eq 1 ]
}

@test "usage fails cleanly when the endpoint is unreachable" {
  export SWAPPY_USAGE_URL="http://127.0.0.1:9/api/oauth/usage"
  run "$SWAPPY" usage
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
}

@test "usage with no login fails with the login hint" {
  logout_live
  run "$SWAPPY" usage
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Claude Code login found"* ]]
}

# ---------- observe --tick: switching ----------

@test "tick below both thresholds does not switch and logs the reading" {
  two_profiles
  stub_respond 200 "$(usage_body 50 20)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-alpha-0000-1111" ]
  [ "$(read_live_secret)" = "$TOKEN_A" ]
  [[ "$(observe_log)" == *"50"* ]]
  [ -f "$HOME/.config/swappy/observe.json" ]
  [ -n "$(json_get "$HOME/.config/swappy/observe.json" last_run.at)" ]
}

@test "tick with 5h at the threshold switches to the next profile and records exhausted_until" {
  two_profiles
  stub_respond 200 "$(usage_body 85 10)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-beta-2222" ]
  [ "$(read_live_secret)" = "$TOKEN_B" ]
  [ "$(json_get "$HOME/.config/swappy/observe.json" exhausted.alpha)" = "2099-01-01T05:00:00Z" ]
  # the token we sent is the only thing the endpoint ever saw: no refresh endpoint, no other path
  ! grep -v '"path": "/api/oauth/usage"' "$STUB_DIR/requests.log"
}

@test "tick with weekly over the threshold switches" {
  two_profiles
  stub_respond 200 "$(usage_body 10 91)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-beta-2222" ]
  [ "$(json_get "$HOME/.config/swappy/observe.json" exhausted.alpha)" = "2099-01-05T00:00:00Z" ]
}

@test "exhausted_until covers the latest reset when both windows are over" {
  two_profiles
  stub_respond 200 "$(usage_body 95 95)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(json_get "$HOME/.config/swappy/observe.json" exhausted.alpha)" = "2099-01-05T00:00:00Z" ]
}

@test "--t5 and --t7 override the default threshold" {
  two_profiles
  stub_respond 200 "$(usage_body 90 90)"
  run "$SWAPPY" observe --tick --t5 95 --t7 95
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-alpha-0000-1111" ]
  run "$SWAPPY" observe --tick --t5 91 --t7 90
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-beta-2222" ]
}

@test "tick skips profiles still marked exhausted" {
  three_profiles
  mark_exhausted beta 2099-06-01T00:00:00Z
  stub_respond 200 "$(usage_body 99 10)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-gamma-3333" ]
}

@test "a profile whose exhausted_until has passed is eligible again" {
  two_profiles
  mark_exhausted beta 2000-01-01T00:00:00Z
  stub_respond 200 "$(usage_body 99 10)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-beta-2222" ]
}

@test "when every other profile is exhausted: no switch, notified once, exit 0" {
  two_profiles
  mark_exhausted beta 2099-06-01T00:00:00Z
  stub_respond 200 "$(usage_body 99 10)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-alpha-0000-1111" ]
  [ "$(json_get "$HOME/.config/swappy/observe.json" notified)" = "True" ]
  [[ "$(observe_log)" == *"exhausted"* ]]
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [[ "$(observe_log)" == *"already notified"* ]]
}

@test "never writes the token to the observe log" {
  two_profiles
  stub_respond 200 "$(usage_body 99 10)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  ! grep -q 'access-a' "$HOME/.config/swappy/observe.log"
  ! grep -q 'access-a' "$HOME/.config/swappy/observe.json"
}

@test "tick leaves state.json byte-identical when it does not switch" {
  two_profiles
  cp "$HOME/.config/swappy/state.json" "$BATS_TEST_TMPDIR/state.before"
  stub_respond 200 "$(usage_body 10 10)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  cmp "$HOME/.config/swappy/state.json" "$BATS_TEST_TMPDIR/state.before"
}

@test "a corrupt observe.json does not stop a tick" {
  two_profiles
  printf 'garbage{' > "$HOME/.config/swappy/observe.json"
  stub_respond 200 "$(usage_body 99 10)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-beta-2222" ]
}

# ---------- observe --tick: refusals (never switch) ----------

@test "tick never switches on bad data or HTTP errors, and always exits 0" {
  two_profiles
  local bad
  for bad in "401|{}" "429|{}" "500|{}" "200|garbage" "200|{}" \
             '200|{"five_hour":null,"seven_day":null}' \
             '200|{"five_hour":{"utilization":"lots","resets_at":null},"seven_day":null}'; do
    stub_respond "${bad%%|*}" "${bad#*|}"
    run "$SWAPPY" observe --tick
    [ "$status" -eq 0 ]
    [ "$(live_uuid)" = "uuid-alpha-0000-1111" ]
    [ "$(read_live_secret)" = "$TOKEN_A" ]
  done
  [[ "$(observe_log)" == *"401"* ]]
  [[ "$(observe_log)" == *"429"* ]]
}

@test "tick never switches when the endpoint is unreachable" {
  two_profiles
  export SWAPPY_USAGE_URL="http://127.0.0.1:9/api/oauth/usage"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-alpha-0000-1111" ]
}

@test "tick with one window null still acts on the other" {
  two_profiles
  stub_respond 200 '{"five_hour":null,"seven_day":{"utilization":97,"resets_at":"2099-01-05T00:00:00Z"}}'
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-beta-2222" ]
}

@test "tick exits cleanly without switching while the switch lock is held" {
  two_profiles
  mkdir "$HOME/.config/swappy/switch.lock"
  stub_respond 200 "$(usage_body 99 10)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-alpha-0000-1111" ]
  [[ "$(observe_log)" == *"lock"* ]]
}

@test "tick aborts when the live token belongs to a different saved profile than ~/.claude.json names" {
  two_profiles
  write_live_secret "$TOKEN_B"   # identity still says alpha
  stub_respond 200 "$(usage_body 99 10)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-alpha-0000-1111" ]
  [ "$(read_live_secret)" = "$TOKEN_B" ]
  [[ "$(observe_log)" == *"identity"* ]]
  # no token was sent anywhere before the identity check passed
  [ ! -e "$STUB_DIR/requests.log" ]
  # the profile snapshots were not overwritten with the wrong token
  [ "$(cat "$HOME/.config/swappy/profiles/alpha/credentials.json")" = "$TOKEN_A" ]
}

@test "tick never discards an unsaved live account (no --force)" {
  two_profiles
  simulate_login uuid-stranger-9 stranger@example.com '{"claudeAiOauth":{"accessToken":"access-s"}}'
  stub_respond 200 "$(usage_body 99 99)"
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  [ "$(live_uuid)" = "uuid-stranger-9" ]
  [ "$(read_live_secret)" = '{"claudeAiOauth":{"accessToken":"access-s"}}' ]
  [[ "$(observe_log)" == *"not saved"* ]]
}

@test "tick with no login or no profiles does nothing and exits 0" {
  logout_live
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
  run "$SWAPPY" observe --tick
  [ "$status" -eq 0 ]
}

# ---------- observe flags ----------

@test "observe rejects bad thresholds and unknown flags" {
  run "$SWAPPY" observe --t5 abc
  [ "$status" -eq 1 ]
  run "$SWAPPY" observe --t7 150
  [ "$status" -eq 1 ]
  run "$SWAPPY" observe --t5
  [ "$status" -eq 1 ]
  run "$SWAPPY" observe --bogus
  [ "$status" -eq 1 ]
}

@test "help lists usage and observe but keeps --tick hidden" {
  run "$SWAPPY" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage"* ]]
  [[ "$output" == *"observe"* ]]
  [[ "$output" != *"--tick"* ]]
}

@test "observe --debug runs the check in a foreground loop with live logs" {
  two_profiles
  stub_respond 200 "$(usage_body 10 10)"
  SWAPPY_OBSERVE_INTERVAL=0 SWAPPY_OBSERVE_MAX_TICKS=2 run "$SWAPPY" observe --debug
  [ "$status" -eq 0 ]
  [[ "$output" == *"tick"* ]]
  [ "$(grep -c '"path"' "$STUB_DIR/requests.log")" -eq 2 ]
}

# ---------- scheduler job text (pure functions) ----------

@test "plist text is valid, runs observe --tick every 900s with absolute paths" {
  run bash -c 'source "$1"; observe_plist_text /opt/s/swappy /var/log/swappy.log "/usr/bin:/bin" 80 70' _ "$SWAPPY"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$BATS_TEST_TMPDIR/job.plist"
  python3 - "$BATS_TEST_TMPDIR/job.plist" <<'PY'
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
assert p["Label"] == "com.swappy.observe", p
assert p["ProgramArguments"] == ["/opt/s/swappy", "observe", "--tick", "--t5", "80", "--t7", "70"], p
assert p["StartInterval"] == 900, p
assert p["EnvironmentVariables"]["PATH"] == "/usr/bin:/bin", p
assert p["StandardErrorPath"] == "/var/log/swappy.log", p
PY
}

@test "plist text escapes XML metacharacters in paths" {
  run bash -c 'source "$1"; observe_plist_text "/opt/a&b/swappy" /l "/p<q" 85 85' _ "$SWAPPY"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$BATS_TEST_TMPDIR/job.plist"
  python3 - "$BATS_TEST_TMPDIR/job.plist" <<'PY'
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
assert p["ProgramArguments"][0] == "/opt/a&b/swappy", p
assert p["EnvironmentVariables"]["PATH"] == "/p<q", p
PY
}

@test "systemd service and timer text run observe --tick every 15 minutes with absolute paths" {
  run bash -c 'source "$1"; observe_service_text /opt/s/swappy "/usr/bin:/bin" 80 70' _ "$SWAPPY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Type=oneshot"* ]]
  [[ "$output" == *'ExecStart="/opt/s/swappy" observe --tick --t5 80 --t7 70'* ]]
  [[ "$output" == *"Environment=\"PATH=/usr/bin:/bin\""* ]]
  run bash -c 'source "$1"; observe_timer_text' _ "$SWAPPY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OnUnitActiveSec=15min"* ]]
  [[ "$output" == *"WantedBy=timers.target"* ]]
}

# ---------- install / --off (scratch dir only) ----------

job_files() {
  if [ "$(uname)" = "Darwin" ]; then
    printf '%s\n' "$SWAPPY_OBSERVE_UNIT_DIR/com.swappy.observe.plist"
  else
    printf '%s\n' "$SWAPPY_OBSERVE_UNIT_DIR/swappy-observe.service" "$SWAPPY_OBSERVE_UNIT_DIR/swappy-observe.timer"
  fi
}

@test "observe installs the job into the scratch dir, prints it, and is idempotent" {
  run "$SWAPPY" observe --t5 70
  [ "$status" -eq 0 ]
  local f
  for f in $(job_files); do
    [ -f "$f" ]
    [[ "$output" == *"$f"* ]]
    grep -q -- '--tick' "$f"
    grep -q -- '70' "$f"
    # absolute path to the real script, never a bare "swappy"
    grep -q "$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)/swappy" "$f"
    cp "$f" "$f.first"
  done
  run "$SWAPPY" observe --t5 70
  [ "$status" -eq 0 ]
  for f in $(job_files); do
    cmp "$f" "$f.first"
  done
}

@test "observe refreshes the job when thresholds change" {
  "$SWAPPY" observe --t5 71
  "$SWAPPY" observe --t5 62
  local f
  for f in $(job_files); do
    grep -q -- '62' "$f"
    ! grep -q -- '71' "$f"
  done
}

@test "observe --off removes the job and is safe to repeat" {
  "$SWAPPY" observe
  run "$SWAPPY" observe --off
  [ "$status" -eq 0 ]
  local f
  for f in $(job_files); do
    [ ! -e "$f" ]
  done
  run "$SWAPPY" observe --off
  [ "$status" -eq 0 ]
}
