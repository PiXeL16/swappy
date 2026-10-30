# ABOUTME: Integration tests for swappy against the file backend (runs on macOS and Linux):
# ABOUTME: save/use/next/rm mechanics, drift reconciliation, rollback, and ~/.claude.json surgery.

load helpers

TOKEN_A='{"claudeAiOauth":{"accessToken":"access-a","refreshToken":"refresh-a"}}'
TOKEN_B='{"claudeAiOauth":{"accessToken":"access-b","refreshToken":"refresh-b"}}'
TOKEN_A_REFRESHED='{"claudeAiOauth":{"accessToken":"access-a2","refreshToken":"refresh-a2"}}'

setup() {
  setup_home
  setup_file_backend "$TOKEN_A"
}

teardown() {
  teardown_home
}

save_two_profiles() {
  "$SWAPPY" save alpha
  simulate_login uuid-beta-2222 beta@example.com "$TOKEN_B"
  "$SWAPPY" save beta
}

@test "save writes profile files with restrictive modes and sets active" {
  run "$SWAPPY" save alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"alpha@example.com"* ]]
  local pdir="$HOME/.config/swappy/profiles/alpha"
  [ "$(cat "$pdir/credentials.json")" = "$TOKEN_A" ]
  [ "$(json_get "$pdir/identity.json" oauthAccount.accountUuid)" = "uuid-alpha-0000-1111" ]
  [ "$(json_get "$pdir/identity.json" userID)" = "user-alpha-111" ]
  [ "$(file_mode "$pdir")" = "700" ]
  [ "$(file_mode "$pdir/credentials.json")" = "600" ]
  [ "$(json_get "$HOME/.config/swappy/state.json" active)" = "alpha" ]
}

@test "save refuses the same account under a second name" {
  "$SWAPPY" save alpha
  run "$SWAPPY" save alias-of-alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"already saved as 'alpha'"* ]]
}

@test "re-save of the same profile refreshes it" {
  "$SWAPPY" save alpha
  write_live_secret "$TOKEN_A_REFRESHED"
  run "$SWAPPY" save alpha
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/swappy/profiles/alpha/credentials.json")" = "$TOKEN_A_REFRESHED" ]
}

@test "use swaps the live credential and the identity in ~/.claude.json" {
  save_two_profiles
  run "$SWAPPY" use alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"switched to alpha"* ]]
  [[ "$output" == *"alpha@example.com"* ]]
  [ "$(read_live_secret)" = "$TOKEN_A" ]
  [ "$(json_get "$HOME/.claude.json" oauthAccount.accountUuid)" = "uuid-alpha-0000-1111" ]
  [ "$(json_get "$HOME/.claude.json" userID)" = "user-alpha-111" ]
  [ "$(json_get "$HOME/.config/swappy/state.json" active)" = "alpha" ]
}

@test "use preserves every other key in ~/.claude.json byte-for-byte (parsed)" {
  save_two_profiles
  python3 - "$HOME/.claude.json" <<'PY' > "$BATS_TEST_TMPDIR/before.json"
import json, sys
data = json.load(open(sys.argv[1]))
del data["oauthAccount"]; del data["userID"]
print(json.dumps(data, sort_keys=True))
PY
  "$SWAPPY" use alpha
  python3 - "$HOME/.claude.json" <<'PY' > "$BATS_TEST_TMPDIR/after.json"
import json, sys
data = json.load(open(sys.argv[1]))
del data["oauthAccount"]; del data["userID"]
print(json.dumps(data, sort_keys=True))
PY
  diff "$BATS_TEST_TMPDIR/before.json" "$BATS_TEST_TMPDIR/after.json"
}

@test "use is a no-op when the target is already active" {
  "$SWAPPY" save alpha
  run "$SWAPPY" use alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"already"* ]]
}

@test "bare profile name works as shorthand for use" {
  save_two_profiles
  run "$SWAPPY" alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"switched to alpha"* ]]
}

@test "use re-snapshots the drifted live token back into its profile" {
  save_two_profiles
  # still on beta; Claude Code refreshes beta's token out-of-band... but simulate for alpha:
  "$SWAPPY" use alpha
  # Claude Code rotates alpha's token while alpha is active
  write_live_secret "$TOKEN_A_REFRESHED"
  "$SWAPPY" use beta
  # alpha's stored snapshot must now hold the refreshed token, not the stale one
  [ "$(cat "$HOME/.config/swappy/profiles/alpha/credentials.json")" = "$TOKEN_A_REFRESHED" ]
  # and switching back must restore the refreshed token
  "$SWAPPY" use alpha
  [ "$(read_live_secret)" = "$TOKEN_A_REFRESHED" ]
}

@test "use refuses when the live account is not saved anywhere" {
  save_two_profiles
  simulate_login uuid-gamma-3333 gamma@example.com '{"claudeAiOauth":{"accessToken":"gamma"}}'
  run "$SWAPPY" use alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"gamma@example.com"* ]]
  [[ "$output" == *"isn't saved"* ]]
  # nothing was touched
  [ "$(read_live_secret)" = '{"claudeAiOauth":{"accessToken":"gamma"}}' ]
}

@test "use --force discards an unsaved live account" {
  save_two_profiles
  simulate_login uuid-gamma-3333 gamma@example.com '{"claudeAiOauth":{"accessToken":"gamma"}}'
  run "$SWAPPY" use alpha --force
  [ "$status" -eq 0 ]
  [ "$(read_live_secret)" = "$TOKEN_A" ]
}

@test "use restores a profile when nobody is logged in" {
  save_two_profiles
  logout_live
  run "$SWAPPY" use alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"switched to alpha"* ]]
  [ "$(read_live_secret)" = "$TOKEN_A" ]
  [ "$(json_get "$HOME/.claude.json" oauthAccount.accountUuid)" = "uuid-alpha-0000-1111" ]
  [ "$(json_get "$HOME/.claude.json" userID)" = "user-alpha-111" ]
  [ "$(json_get "$HOME/.config/swappy/state.json" active)" = "alpha" ]
}

@test "next rotates when nobody is logged in" {
  save_two_profiles
  logout_live
  run "$SWAPPY" next
  [ "$status" -eq 0 ]
  [[ "$output" == *"switched to alpha"* ]]
  [ "$(read_live_secret)" = "$TOKEN_A" ]
}

@test "use keeps a profile's token when the live credential is gone but its identity lingers" {
  save_two_profiles           # live account is beta
  remove_live_secret          # credential store emptied; ~/.claude.json still names beta
  run "$SWAPPY" use alpha
  [ "$status" -eq 0 ]
  # beta's snapshot is the only copy of its token left — re-snapshotting an absent
  # credential over it would destroy the account for good
  [ "$(cat "$HOME/.config/swappy/profiles/beta/credentials.json")" = "$TOKEN_B" ]
  [ "$(read_live_secret)" = "$TOKEN_A" ]
}

@test "use works with no ~/.claude.json at all" {
  save_two_profiles
  logout_live
  rm -f "$HOME/.claude.json"
  run "$SWAPPY" use alpha
  [ "$status" -eq 0 ]
  [ "$(json_get "$HOME/.claude.json" oauthAccount.emailAddress)" = "alpha@example.com" ]
  [ "$(read_live_secret)" = "$TOKEN_A" ]
}

@test "save still refuses when nobody is logged in" {
  save_two_profiles
  logout_live
  run "$SWAPPY" save alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Claude Code login found"* ]]
  # the existing snapshot survives the refusal
  [ "$(cat "$HOME/.config/swappy/profiles/alpha/credentials.json")" = "$TOKEN_A" ]
}

@test "use backs up the replaced live secret" {
  save_two_profiles
  "$SWAPPY" use alpha
  [ "$(cat "$HOME/.config/swappy/backup/prev-credentials.json")" = "$TOKEN_B" ]
  [ -f "$HOME/.config/swappy/backup/claude.json.bak" ]
}

@test "failed identity swap rolls the live credential back" {
  save_two_profiles
  chmod 555 "$HOME"   # ~/.claude.json can't be atomically replaced -> identity swap fails
  run "$SWAPPY" use alpha
  chmod 755 "$HOME"
  [ "$status" -eq 1 ]
  [[ "$output" == *"roll"* ]]
  # the live secret must still be beta's — the two stores never diverge
  [ "$(read_live_secret)" = "$TOKEN_B" ]
  [ "$(json_get "$HOME/.claude.json" oauthAccount.accountUuid)" = "uuid-beta-2222" ]
}

@test "next rotates in save order and wraps around" {
  save_two_profiles
  simulate_login uuid-gamma-3333 gamma@example.com '{"claudeAiOauth":{"accessToken":"gamma"}}'
  "$SWAPPY" save gamma
  run "$SWAPPY" next            # gamma -> alpha (wrap)
  [ "$status" -eq 0 ]
  [[ "$output" == *"switched to alpha"* ]]
  run "$SWAPPY" next            # alpha -> beta
  [[ "$output" == *"switched to beta"* ]]
  run "$SWAPPY" next            # beta -> gamma
  [[ "$output" == *"switched to gamma"* ]]
}

@test "next rotates off the live account, not a stale state file" {
  save_two_profiles
  "$SWAPPY" use alpha                                          # state: active=alpha, live=alpha
  simulate_login uuid-beta-2222 beta@example.com "$TOKEN_B"    # `claude /login` behind swappy's back
  run "$SWAPPY" next                                           # live is beta, so next is alpha (wrap)
  [ "$status" -eq 0 ]
  [[ "$output" == *"switched to alpha"* ]]
  [ "$(read_live_secret)" = "$TOKEN_A" ]
}

@test "next with a single profile says so and exits 0" {
  "$SWAPPY" save alpha
  run "$SWAPPY" next
  [ "$status" -eq 0 ]
  [[ "$output" == *"only one profile"* ]]
}

@test "next with no profiles errors helpfully" {
  run "$SWAPPY" next
  [ "$status" -eq 1 ]
  [[ "$output" == *"no profiles"* ]]
}

@test "rm refuses to delete the active profile" {
  save_two_profiles
  run "$SWAPPY" rm beta
  [ "$status" -eq 1 ]
  [[ "$output" == *"active"* ]]
  [ -d "$HOME/.config/swappy/profiles/beta" ]
}

@test "rm deletes an inactive profile and its files" {
  save_two_profiles
  run "$SWAPPY" rm alpha
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.config/swappy/profiles/alpha" ]
  run "$SWAPPY" ls
  [[ "$output" != *"alpha"* ]]
}

@test "ls marks the active profile and shows emails" {
  save_two_profiles
  run "$SWAPPY" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"* beta"*"beta@example.com"* ]]
  [[ "$output" == *"alpha"*"alpha@example.com"* ]]
}

@test "corrupt state file refuses with recovery instructions" {
  "$SWAPPY" save alpha
  echo 'not json' > "$HOME/.config/swappy/state.json"
  run "$SWAPPY" ls
  [ "$status" -eq 1 ]
  [[ "$output" == *"corrupt"* ]]
  [[ "$output" == *"swappy save"* ]]
}

@test "bare profile name shorthand accepts --force" {
  save_two_profiles
  simulate_login uuid-gamma-3333 gamma@example.com '{"claudeAiOauth":{"accessToken":"gamma"}}'
  run "$SWAPPY" alpha --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"switched to alpha"* ]]
}

@test "re-save refuses when the profile holds a different account" {
  "$SWAPPY" save alpha
  simulate_login uuid-beta-2222 beta@example.com "$TOKEN_B"
  run "$SWAPPY" save alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"different account"* ]]
  # alpha's original token was not destroyed
  [ "$(cat "$HOME/.config/swappy/profiles/alpha/credentials.json")" = "$TOKEN_A" ]
}

@test "save fails loudly when the state file cannot be written" {
  "$SWAPPY" save alpha
  chmod 444 "$HOME/.config/swappy/state.json"
  simulate_login uuid-beta-2222 beta@example.com "$TOKEN_B"
  run "$SWAPPY" save beta
  chmod 644 "$HOME/.config/swappy/state.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"state"* ]]
}

@test "use refuses while a fresh switch lock is held, and leaves everything alone" {
  save_two_profiles
  mkdir "$HOME/.config/swappy/switch.lock"
  run "$SWAPPY" use alpha
  [ "$status" -eq 1 ]
  [[ "$output" == *"in progress"* ]]
  [ "$(read_live_secret)" = "$TOKEN_B" ]
  [ -d "$HOME/.config/swappy/switch.lock" ]
}

@test "use overrides a stale switch lock" {
  save_two_profiles
  mkdir "$HOME/.config/swappy/switch.lock"
  touch -t 200001010000 "$HOME/.config/swappy/switch.lock"
  run "$SWAPPY" use alpha
  [ "$status" -eq 0 ]
  [ "$(read_live_secret)" = "$TOKEN_A" ]
}

@test "use releases the switch lock on success and on failure" {
  save_two_profiles
  run "$SWAPPY" use alpha
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/swappy/switch.lock" ]
  run "$SWAPPY" use nope
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.config/swappy/switch.lock" ]
  simulate_login uuid-stranger-9 stranger@example.com '{"claudeAiOauth":{"accessToken":"s"}}'
  run "$SWAPPY" use alpha
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.config/swappy/switch.lock" ]
}
