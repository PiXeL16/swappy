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

Two things worth knowing:

- Claude sessions that are already running keep their token in memory. The switch applies to
  new sessions.
- If you `/login` to an account swappy doesn't know about, `swappy use` refuses to switch away
  from it (so you can't accidentally throw away a login). Either `swappy save` it or pass
  `--force` to discard it.

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
- swappy switches *between* logins; it can't restore one after `/logout` has deleted the
  credential store entirely. If you logged out, `/login` to any account and switch from there.

## Development

```sh
bats test/          # unit + integration + e2e
```

Tests run against a scratch `$HOME` and, on macOS, a real throwaway keychain. They never touch
your login keychain or your real `~/.claude.json`. See `CLAUDE.md` for contributor conventions.

## License

MIT
