# ABOUTME: Shared bats helpers for swappy tests. Builds an isolated fake $HOME per test
# ABOUTME: and (on macOS) a throwaway keychain, so tests exercise real tools without touching real auth.

SWAPPY="$BATS_TEST_DIRNAME/../swappy"

# Every test runs against a scratch HOME with a realistic ~/.claude.json fixture.
setup_home() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  unset XDG_CONFIG_HOME
  cp "$BATS_TEST_DIRNAME/fixtures/claude.json" "$HOME/.claude.json"
}

teardown_home() {
  # $HOME may have been made read-only by rollback tests
  chmod -R u+w "$TEST_HOME" 2>/dev/null || true
  rm -rf "$TEST_HOME"
}

# File backend: the cross-platform credential store (~/.claude/.credentials.json).
setup_file_backend() {
  export SWAPPY_BACKEND=file
  mkdir -p "$HOME/.claude"
  printf '%s' "$1" > "$HOME/.claude/.credentials.json"
  chmod 600 "$HOME/.claude/.credentials.json"
}

# Keychain backend (macOS only): a real temporary keychain, deleted in teardown.
setup_keychain_backend() {
  TEST_KEYCHAIN="$TEST_HOME/swappy-test.keychain-db"
  security create-keychain -p swappy-test "$TEST_KEYCHAIN"
  security unlock-keychain -p swappy-test "$TEST_KEYCHAIN"
  export SWAPPY_KEYCHAIN="$TEST_KEYCHAIN"
  export SWAPPY_BACKEND=keychain
  security add-generic-password -U -s "Claude Code-credentials" -a "$USER" -w "$1" "$TEST_KEYCHAIN"
}

teardown_keychain_backend() {
  if [ -n "${TEST_KEYCHAIN:-}" ] && [ -f "$TEST_KEYCHAIN" ]; then
    security delete-keychain "$TEST_KEYCHAIN" 2>/dev/null || true
  fi
  unset SWAPPY_KEYCHAIN
}

# Read the live credential through the same backend swappy uses.
read_live_secret() {
  if [ "${SWAPPY_BACKEND:-}" = "keychain" ]; then
    security find-generic-password -s "Claude Code-credentials" -a "$USER" -w "$TEST_KEYCHAIN"
  else
    cat "$HOME/.claude/.credentials.json"
  fi
}

# Write the live credential out-of-band (simulates Claude Code refreshing the token).
write_live_secret() {
  if [ "${SWAPPY_BACKEND:-}" = "keychain" ]; then
    security add-generic-password -U -s "Claude Code-credentials" -a "$USER" -w "$1" "$TEST_KEYCHAIN"
  else
    printf '%s' "$1" > "$HOME/.claude/.credentials.json"
  fi
}

# Delete the live credential, leaving ~/.claude.json alone (simulates Claude Code dropping
# the keychain item while its stale identity lingers).
remove_live_secret() {
  if [ "${SWAPPY_BACKEND:-}" = "keychain" ]; then
    security delete-generic-password -s "Claude Code-credentials" -a "$USER" "$TEST_KEYCHAIN" >/dev/null 2>&1 || true
  else
    rm -f "$HOME/.claude/.credentials.json"
  fi
}

# Simulate `/logout`: no live credential and no identity left in ~/.claude.json.
logout_live() {
  remove_live_secret
  python3 - "$HOME/.claude.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data.pop("oauthAccount", None)
data.pop("userID", None)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
}

# Simulate `/login` to a different account: new live secret + new identity in ~/.claude.json.
simulate_login() { # uuid email token
  write_live_secret "$3"
  SIM_UUID="$1" SIM_EMAIL="$2" python3 - "$HOME/.claude.json" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["oauthAccount"]["accountUuid"] = os.environ["SIM_UUID"]
data["oauthAccount"]["emailAddress"] = os.environ["SIM_EMAIL"]
data["userID"] = "user-" + os.environ["SIM_UUID"]
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
}

# Octal permission bits of a file, portable across GNU and BSD stat.
# (GNU treats -f as --file-system, so "try BSD then fall back" ordering must be GNU-first.)
file_mode() {
  if stat -c %a "$1" >/dev/null 2>&1; then
    stat -c %a "$1"
  else
    stat -f %Lp "$1"
  fi
}

# jq-less JSON field reader (python3 is swappy's only runtime dep, tests match).
json_get() { # file dotted.path
  python3 - "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for key in sys.argv[2].split("."):
    data = data[key]
print(data)
PY
}
