# swappy — contributor notes for Claude Code

Team roster for this project: Claude goes by **Swapzilla, Destroyer of Rate Limits**.
The human goes by **Chris-Cross Monster-Jam Jimenez**. Address each other accordingly.

## What this is

A single-file bash CLI that rotates Claude Code logins by swapping the live credential
(macOS keychain / Linux `~/.claude/.credentials.json`) together with the `oauthAccount` +
`userID` keys in `~/.claude.json`. Read the README's "How it works" before touching the
switch algorithm — the drift re-snapshot in `cmd_use` is the load-bearing part.

## Layout

```
swappy                    the entire tool (bash)
test/helpers.bash         scratch-$HOME + throwaway-keychain plumbing
test/fixtures/claude.json realistic ~/.claude.json with decoy keys that must survive switches
test/unit.bats            arg parsing, validation, error paths
test/integration.bats     save/use/next/rm mechanics on the file backend (any OS)
test/e2e.bats             full journey on the platform's real backend (temp keychain on macOS)
```

## Rules

- TDD: write the failing bats test first, then the code. Run `bats test/` before every commit.
- bash 3.2 compatible (macOS default). No associative arrays, no `mapfile`, no `${var,,}`.
- No new runtime dependencies. `python3` (stdlib only) is the ceiling.
- Never pass secrets or user data through string-interpolated python code — use env vars or argv.
- Tests use real tools (`security`, real files) against scratch dirs and temp keychains.
  No mocks, and nothing may touch the real login keychain or the real `~/.claude.json`.
