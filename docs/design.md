<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

The deck works with git repositories through the `git` command line: open,
create and clone; status, staging, commits, amends and stashes; log, show,
diffs, blame, files and trees at a revision, archives; branches, tags,
merges, remotes, fetch, pull, push and `lsRemote`. Results are typed structs
parsed from git's machine-readable output.

It is built for names, revisions, paths and URLs that come from users, so the
hardening is part of the design rather than an option. [Security](security.md)
is the user-facing statement of that model.

Not in scope:

- **A git implementation in Jennifer.** Object storage, pack files and the
  wire protocol are git's; the deck drives the installed program.
- **Interactive commands** (rebase, add `-p`) and anything that would wait
  for a person.
- **Credential handling.** The deck never sees a credential; ssh agents,
  deploy keys and credential helpers stay git's business.
- **Forge APIs.** Pull requests, issues and releases belong to the forge
  decks (`@deckyard/github`, `@deckyard/gitlab`).

## Decisions

- **Drive the git program.** git's behaviour, formats and security fixes come
  with the installed version; reimplementing them would be large and would
  lag. The cost is the `exec` capability and no `jennifer-tiny`. The deck
  declares no `net`: git reaches remotes itself.
- **No shell, ever.** Every command is an argument list for `os.spawn`. The
  program run is `env`, which removes variables before starting `git`.
- **One hardened command line.** Every call goes through the same prefix:
  the C locale, no terminal prompt, no optional locks, no pager, literal
  pathspecs, replace refs ignored, `protocol.allow=never` with only the
  configured protocols re-enabled, the fsmonitor off, hooks off unless
  allowed, and an optional fixed identity. Keeping it in one place means a
  new command cannot forget a part.
- **Relocating environment variables are removed.** `GIT_DIR`,
  `GIT_WORK_TREE`, `GIT_INDEX_FILE` and the others that beat `-C` are unset
  with `env -u` on every command. Run from a git hook, which sets them, a
  command would otherwise act on the hook's repository.
- **Inputs are checked as git checks them.** Branch, tag and remote names
  follow `git check-ref-format` and may not start with `-`; revisions and
  URLs may not start with `-` or hold control characters; revisions follow
  `--end-of-options` where git supports it; paths follow `--` and are
  literal. `blame` is the exception: git reads `--end-of-options` there as a
  revision, so it relies on the leading-`-` refusal alone.
- **Protocols are allow-listed.** The default is `https` and `ssh`. `file`
  (and plain local paths) must be opted into with `withProtocols`, because a
  user-supplied path could otherwise clone any repository the process can
  read. The `transport::address` form (`ext::`, `fd::`) is refused before git
  sees it, and the allow-list keeps a `scheme://` URL from reaching a
  `git-remote-<scheme>` helper.
- **Programs from the repository do not run.** Hooks are off by default
  (`withHooks` turns them on) and diffs and blame pass `--no-ext-diff` and
  `--no-textconv`, which a repository's `.gitattributes` could otherwise
  select.
- **`open` takes only a top level.** `GIT_CEILING_DIRECTORIES` is
  colon-separated, so a parent such as `/srv/a:b` defeats it; `open` also
  compares the top level git reports with the one asked for.
- **Safe defaults for history-changing commands.** `pull` is always
  fast-forward only. `push` refuses a `+` refspec and offers `force` as
  `--force-with-lease`.
- **A conflict is a result.** `merge` returns `Merge` with the conflicting
  paths rather than throwing; it throws only when git refused and nothing is
  unmerged.
- **Immutable configuration.** `Config` is a value built with `config` and
  the `with*` builders (`withBinary`, `withTimeout`, `withProtocols`,
  `withHooks`, `withIdentity`); `Repo` pairs an absolute directory with one.
- **Parsers are pure.** Status (porcelain v2), log (a NUL-separated
  format), blame and branch listings are parsed by separate functions, so
  they are tested without git.
- **Binary output through a file.** `readBytes` streams `cat-file` into a
  temporary file, so it is binary-safe and unbounded; `readFile` returns text
  and is capped.

## Errors

Every failure is an `Error` with a message starting `git: `. Its kind is
`"git"` (`ERROR_KIND`) for a refused input, a non-zero exit (carrying git's
explanation, the first `fatal:` or `error:` line of its error output) and a
program that cannot start. Two cases have the generic kinds every library
shares: a command killed at its timeout is kind `"timeout"`, and output past
the 16 MiB capture cap is kind `"limit"`. Credentials in a URL are written `***` in the deck's messages;
git strips them from its own.

## Security and limits

- Every command has a timeout (`withTimeout`, at least one second, two
  minutes by default); the deck kills git when it passes.
- Captured output is capped at 16 MiB by the interpreter; past it the call
  fails and asks for a narrower query. `readBytes` is the way to large or
  binary content.
- `GIT_TERMINAL_PROMPT=0`: a remote that wants a password fails instead of
  hanging.
- The user's global configuration still applies to the commands the deck
  runs; the tests isolate it, callers may want to as well.
- `run` passes its arguments unchecked after the hardened prefix and must
  never carry user input; a new need gets a typed function instead.

## Testing and validation

- Pure tests cover the input checks, the command line and the parsers and
  run everywhere.
- Live tests run real git in throwaway repositories in the temporary
  directory, with no network, the user's global and system configuration
  switched off, and a fixed identity. Each returns early where git is not
  installed, which includes CI's container, so the suite must be run on a
  machine with git before a release.
- The security model is tested live: an `ext::` clone creates no file,
  `GIT_DIR` in the environment is ignored, hooks do not run unless allowed,
  blame and diff run no text conversion, a colon in a parent path does not
  defeat `open`, and a token does not appear in an `lsRemote` error.
- CI parses the example but cannot run it (no git in the container).
- Requires git 2.25 or newer; older versions are not tested.

## Known limitations and open questions

- The timeout kills git, not its children (`ssh`, `git-remote-https`), and a
  kill mid-write can leave `.git/index.lock` behind.
- A repository's own `.git/config` can still run programs (`core.sshCommand`,
  filters, aliases); git's `safe.directory` refuses repositories owned by
  another user, but a `.git` from an upload is not safe to open.
- A URL can reach any host the machine can; host filtering is the caller's.
- `stash` drops `--literal-pathspecs`, since with it git leaves the files
  `--include-untracked` saved and the next `stashPop` refuses to restore them.

## Dependencies on the interpreter

- Floor `>=0.28.0` (the calls 0.29.0 removes are replaced by their 0.28.0 forms) (for `strings.replicate`), the default binary only
  (`exec` through `os.spawn`, `os.poll` and `os.kill`).
- The interpreter's 16 MiB capture cap on a child's output, marked so the
  deck can detect it.
