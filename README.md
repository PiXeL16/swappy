# swappy

[![tests](https://github.com/PiXeL16/swappy/actions/workflows/ci.yml/badge.svg)](https://github.com/PiXeL16/swappy/actions/workflows/ci.yml)

A tiny CLI for people with more than one Claude account. When the account you're on hits its
usage limit, `swappy next` rotates you to the next one. That's the whole tool.

```
$ swappy ls
* work             chris@company.com
  personal         chris@gmail.com
  spare            other@gmail.com

$ swappy next
switched to personal (chris@gmail.com)
```

swappy is deliberately **not** a profile manager. It doesn't split or manage your `~/.claude`
settings, history, or projects (tools like claude-profiles do that, and it's overkill if all
you want is to jump logins). swappy swaps exactly one thing: the login. Your settings, MCP
servers, and project history stay put and are shared across accounts.

## Why

If you bounce between a work account, a personal account, and a spare, running out of usage
means logging out, logging in, doing the OAuth dance in a browser, and losing track of which
account you already burned. swappy turns that into one command that also remembers the
rotation order for you.

## Install

```sh
git clone https://github.com/PiXeL16/swappy.git
cd swappy
ln -s "$PWD/swappy" ~/.local/bin/swappy   # or anywhere on your PATH
```

There's no `curl | sh` on purpose: this tool handles your auth tokens, so read the script
first (it's one file of bash), then symlink it. Requirements: `bash` and `python3`, nothing
else. Works on macOS and Linux with Claude Code OAuth logins. API-key setups don't need swappy.

## Usage

Log in to each account once (in `claude`, run `/login`) and snapshot it:

```sh
swappy save work        # snapshots whichever account is currently logged in
# /login to the next account, then:
swappy save personal
# /login to the third, then:
swappy save spare
```

Day to day:

| command | what it does |
|---|---|
| `swappy next` | rotate to the next saved account, wrapping around |
| `swappy use <name>` | switch to a specific account (`swappy <name>` also works) |
| `swappy ls` | list accounts, `*` marks the active one |
| `swappy save <name>` | snapshot the current login (re-save refreshes a profile) |
| `swappy rm <name>` | delete a saved profile |
| `swappy usage` | show the live account's 5h / 7d usage |
| `swappy observe` | install a scheduled job that rotates accounts near the limit |

Two things worth knowing:

- Claude sessions that are already running keep their token in memory. The switch applies to
  new sessions.
- If you `/login` to an account swappy doesn't know about, `swappy use` refuses to switch away
  from it (so you can't accidentally throw away a login). Either `swappy save` it or pass
  `--force` to discard it.

## Auto-rotate with `swappy observe`

`swappy next` is manual. `swappy observe` checks the live account's usage every 15 minutes and
rotates to the next saved profile when the 5-hour or weekly window gets close to its limit.

```sh
swappy observe                    # install/refresh the scheduled job, print it, exit (idempotent)
swappy observe --t5 80 --t7 90    # thresholds in percent (default 85 for both)
swappy observe --debug            # run the same check in the foreground with live logs
swappy observe --off              # remove the scheduled job
swappy usage                      # print the live account's current 5h / 7d usage
```

- **macOS and Linux only.** macOS installs a launchd agent (`~/Library/LaunchAgents/com.swappy.observe.plist`),
  Linux a systemd user timer (`~/.config/systemd/user/swappy-observe.{service,timer}`). Both use the
  absolute path of the swappy script. On macOS a background job reading the keychain may trigger an
  authorization prompt the first time; check `observe.log` after the first interval.
- **Thresholds.** `--t5` / `--t7` switch when the 5-hour / weekly utilization is at or above the value.
  Re-run `swappy observe --t5 N` to change the installed job.
- **How it picks.** swappy never checks other profiles' usage (their saved tokens go stale, and it never
  refreshes tokens). It reads the live account just before leaving it, remembers when that account
  resets (`exhausted_until`, in `observe.json` next to `state.json`), and rotates to the next profile
  that is not still marked exhausted. If every profile is exhausted it stays put and sends one
  desktop notification.
- **It never switches on doubt.** On an HTTP error (401, 429, ...), unparseable or empty data, an
  unreachable endpoint, a held switch lock, an unsaved live account (it never uses `--force`), or a
  failed identity check, it logs to `observe.log` and does nothing.
- **Identity check.** Before switching, swappy refuses if the live token is byte-identical to a token
  saved for a *different* profile than the one `~/.claude.json` names. It cannot prove a freshly
  rotated token belongs to the named account without calling a refresh endpoint, which swappy never
  does, so that is the limit of the check.
- **Unofficial endpoint.** Usage comes from `https://api.anthropic.com/api/oauth/usage`, an
  undocumented endpoint known only from community sources. It can change or disappear without notice.
- **Unverified:** whether an already-running Claude Code session picks up a swapped token (the note above
  says it keeps the old one; one observation suggested otherwise), and whether a running session writes
  its in-memory identity back over `~/.claude.json` after a swap.
- **Reserved names.** `usage` and `observe` are now command words: an existing profile with either
  name is hidden (it can no longer be selected by name) until you `swappy rm` / re-save it under another name.

## How it works

Claude Code stores an OAuth login in two places:

1. **The token**: a macOS keychain item (`Claude Code-credentials`) or, on Linux,
   `~/.claude/.credentials.json`.
2. **The identity**: the `oauthAccount` object and `userID` inside `~/.claude.json`.

`swappy use` swaps both, together. The identity swap replaces only those two keys and leaves
the rest of `~/.claude.json` (projects, history, settings) untouched, written atomically. If
the identity swap fails, the token write is rolled back so the two stores never disagree.

**The drift trick.** Claude Code rotates OAuth tokens while you work, so the token swappy
saved yesterday may already be dead. Before every switch, swappy matches the *live* account
against your saved profiles and re-snapshots the current token back into its profile.
Switching back later therefore restores a fresh token, not a stale one. This is the part that
makes naive "copy the credentials file around" approaches break after a day.

Re-snapshotting only ever happens with a credential in hand, and a switch never requires one:
if Claude Code has no live login (you ran `/logout`, or it dropped the keychain item), `swappy
use` and `swappy next` simply restore the profile you asked for. Rotation follows the account
that is *actually* live, so logging in by hand behind swappy's back doesn't desync it.

Only one switch runs at a time (a lock directory in the swappy dir, overridden after two minutes), so a
manual `swappy use` and the scheduled observer cannot interleave.

Profiles and state live in `${XDG_CONFIG_HOME:-~/.config}/swappy/`. The last-replaced live
credential and a pre-swap copy of `~/.claude.json` are kept in `backup/` there.

## Security

Know what this tool does before using it:

- Saved profiles are **OAuth tokens in plaintext on disk**, in a `700` directory with `600`
  files. That's the price of working identically across macOS and Linux. The *live*
  credential stays wherever Claude Code keeps it (the keychain, on macOS).
- On macOS the first time swappy writes the live keychain item you may get a one-time
  keychain authorization dialog. swappy updates the item in place (`security ... -U`) so
  Claude Code's own keychain access is preserved.
- Whether rotating multiple accounts is cool under your plans' terms of service is between
  you and Anthropic. swappy just moves files around.

## Limitations

- OAuth logins only, verified against Claude Code 2.1.x credential locations. If Anthropic
  moves the credential store, `swappy save` will tell you it can't find a login rather than
  guessing.
- swappy can only rotate between accounts you have saved. It never invents a login: if a
  profile's saved token has expired past refresh, that account needs a real `/login` again.

## Development

```sh
bats test/          # unit + integration + e2e
```

`SWAPPY_KEYCHAIN`, `SWAPPY_BACKEND`, `SWAPPY_USAGE_URL`, `SWAPPY_OBSERVE_UNIT_DIR`, `SWAPPY_NO_NOTIFY` and
`SWAPPY_OBSERVE_INTERVAL` / `SWAPPY_OBSERVE_MAX_TICKS` are test-only environment variables (see the top of
`swappy`). `SWAPPY_USAGE_URL` receives your bearer token, so never set it to anything you do not control.

Tests run against a scratch `$HOME` and, on macOS, a real throwaway keychain. They never touch
your login keychain or your real `~/.claude.json`. See `CLAUDE.md` for contributor conventions.

## License

MIT
