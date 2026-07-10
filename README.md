# swappy

A tiny CLI for people with more than one Claude account. When the account you're on hits its
usage limit, `swappy next` rotates you to the next one. That's the whole tool.

swappy is deliberately **not** a profile manager. It does not split or manage your
`~/.claude` settings, history, or projects — tools like claude-profiles do that, and it's
overkill if all you want is to jump logins. swappy swaps exactly one thing: the login.

```
$ swappy ls
* work             chris@company.com
  personal         chris@gmail.com
  spare            other@gmail.com

$ swappy next
switched to personal (chris@gmail.com)
```

## Install

```sh
git clone https://github.com/YOURUSER/swappy.git
cd swappy
ln -s "$PWD/swappy" ~/.local/bin/swappy   # or anywhere on your PATH
```

No `curl | sh` on purpose: this tool handles your auth tokens, so read the script (it's one
file of bash), then symlink it. Requires `bash` and `python3`, nothing else. Works on macOS
and Linux with Claude Code OAuth logins (`/login`). API-key setups don't need swappy.

## Usage

Log in to each account once (via `claude` → `/login`) and snapshot it:

```sh
swappy save work        # snapshot whichever account is currently logged in
# /login to the next account...
swappy save personal
# /login to the third...
swappy save spare
```

Then, day to day:

| command | what it does |
|---|---|
| `swappy next` | rotate to the next saved account, wrapping around |
| `swappy use <name>` (or `swappy <name>`) | switch to a specific account |
| `swappy ls` | list accounts, `*` marks the active one |
| `swappy save <name>` | snapshot the current login (re-save refreshes a profile) |
| `swappy rm <name>` | delete a saved profile |

Already-running `claude` sessions keep their token in memory; the switch applies to new
sessions.

## How it works

Claude Code stores an OAuth login in two places:

1. **The token** — a macOS keychain item (`Claude Code-credentials`) or, on Linux,
   `~/.claude/.credentials.json`.
2. **The identity** — the `oauthAccount` object and `userID` inside `~/.claude.json`.

`swappy use` swaps both, together. The identity swap replaces only those two keys and leaves
the rest of `~/.claude.json` (your projects, history, settings) untouched, written atomically.
If the identity swap fails, the token is rolled back so the two stores never disagree.

**The drift trick:** Claude Code rotates OAuth tokens while you use it, so the token swappy
saved yesterday may already be dead. Before every switch, swappy matches the *live* account
against your saved profiles and re-snapshots the current token back into its profile. Switching
back later therefore always restores a fresh token, not a stale one.

Profiles and state live in `${XDG_CONFIG_HOME:-~/.config}/swappy/`. The last-replaced live
credential and a pre-swap copy of `~/.claude.json` are kept in `backup/` there.

## Security

Be aware of what this tool does before using it:

- Saved profiles are **OAuth tokens in plaintext on disk**, in a `700` directory with `600`
  files. That's the price of working identically across macOS and Linux. The *live*
  credential stays wherever Claude Code keeps it (the keychain, on macOS).
- On macOS, the first time swappy writes the live keychain item you may get a one-time
  keychain authorization dialog. swappy updates the item in place (`-U`) so Claude Code's
  own access is preserved.
- Whether rotating multiple accounts is cool under your plans' terms of service is between
  you and Anthropic. swappy just moves files around.

## Compatibility

Verified against Claude Code 2.1.x credential locations. OAuth logins only. If Anthropic
moves the credential store, `swappy save` will tell you it can't find a login rather than
guessing.

## Development

```sh
bats test/          # unit + integration + e2e
```

Tests run against a scratch `$HOME` and (on macOS) a throwaway keychain — they never touch
your real login. See `CLAUDE.md` for contributor conventions.

## License

MIT
