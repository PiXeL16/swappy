# ABOUTME: End-to-end tests: the full three-account journey through the platform's real
# ABOUTME: credential backend — a throwaway macOS keychain on darwin, the credentials file elsewhere.

load helpers

TOKEN_A='{"claudeAiOauth":{"accessToken":"access-a","refreshToken":"refresh-a"}}'
TOKEN_B='{"claudeAiOauth":{"accessToken":"access-b","refreshToken":"refresh-b"}}'
TOKEN_C='{"claudeAiOauth":{"accessToken":"access-c","refreshToken":"refresh-c"}}'

setup() {
  setup_home
  if [ "$(uname)" = "Darwin" ]; then
    setup_keychain_backend "$TOKEN_A"
  else
    setup_file_backend "$TOKEN_A"
  fi
}

teardown() {
  if [ "$(uname)" = "Darwin" ]; then
    teardown_keychain_backend
  fi
  teardown_home
}

@test "full journey: save three accounts, rotate, wrap, drift, rm" {
  # save three accounts, logging in between (fixture starts as alpha)
  "$SWAPPY" save alpha
  simulate_login uuid-beta-2222 beta@example.com "$TOKEN_B"
  "$SWAPPY" save beta
  simulate_login uuid-gamma-3333 gamma@example.com "$TOKEN_C"
  "$SWAPPY" save gamma

  # ls shows all three, gamma active
  run "$SWAPPY" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"*"alpha@example.com"* ]]
  [[ "$output" == *"beta"*"beta@example.com"* ]]
  [[ "$output" == *"* gamma"*"gamma@example.com"* ]]

  # rotate: gamma -> alpha (wrap), live stores really swapped
  run "$SWAPPY" next
  [ "$status" -eq 0 ]
  [[ "$output" == *"switched to alpha (alpha@example.com)"* ]]
  [ "$(read_live_secret)" = "$TOKEN_A" ]
  [ "$(json_get "$HOME/.claude.json" oauthAccount.emailAddress)" = "alpha@example.com" ]
  [ "$(json_get "$HOME/.claude.json" userID)" = "user-alpha-111" ]

  # Claude Code refreshes alpha's token while active; rotating away must capture it
  REFRESHED='{"claudeAiOauth":{"accessToken":"access-a2","refreshToken":"refresh-a2"}}'
  write_live_secret "$REFRESHED"
  run "$SWAPPY" next            # alpha -> beta
  [[ "$output" == *"switched to beta"* ]]
  [ "$(read_live_secret)" = "$TOKEN_B" ]
  [ "$(cat "$HOME/.config/swappy/profiles/alpha/credentials.json")" = "$REFRESHED" ]

  # wrap the rest of the way and confirm alpha comes back refreshed
  "$SWAPPY" next                # beta -> gamma
  run "$SWAPPY" next            # gamma -> alpha
  [[ "$output" == *"switched to alpha"* ]]
  [ "$(read_live_secret)" = "$REFRESHED" ]

  # decoy keys in ~/.claude.json survived every switch
  [ "$(json_get "$HOME/.claude.json" tipsHistory.terminal-setup)" = "5" ]
  run json_get "$HOME/.claude.json" projects
  [[ "$output" == *"decoy history entry"* ]]

  # rm: refuses active, deletes inactive
  run "$SWAPPY" rm alpha
  [ "$status" -eq 1 ]
  run "$SWAPPY" rm beta
  [ "$status" -eq 0 ]
  run "$SWAPPY" ls
  [[ "$output" != *"beta@example.com"* ]]
}

@test "keychain backend is auto-detected on darwin without SWAPPY_BACKEND" {
  if [ "$(uname)" != "Darwin" ]; then
    skip "darwin-only"
  fi
  unset SWAPPY_BACKEND
  run "$SWAPPY" save alpha
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/swappy/profiles/alpha/credentials.json")" = "$TOKEN_A" ]
}
