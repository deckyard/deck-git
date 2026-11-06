<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Security

A git command line has more ways in than it looks. A branch named
`--upload-pack=touch /tmp/x` is an option. A URL `ext::sh -c ...` runs a
command. `GIT_DIR` in the environment, as a hook sets it, makes `-C` point
somewhere else. A repository's hooks and `core.fsmonitor` are programs. The
deck closes each of these, so names, revisions, paths and URLs can come from
users.

## What the deck does

- **No shell.** Every command is an argument list handed to the program.
- **Names are checked as git checks them.** Branch, tag and remote names
  follow `git check-ref-format`: no spaces, `..`, `~ ^ : ? * [ \`, `@` plus an
  opening brace, leading or trailing `/` or `.`, `.lock` endings, and no
  leading `-`.
- **Revisions and URLs may not start with `-`**, and revisions are passed
  after `--end-of-options` where git supports it. Control characters are
  refused in both.
- **Paths come after `--` and are literal** (`--literal-pathspecs`): `-rf`
  is a file name and `*.txt` is not a glob, nor is `:(top)` magic.
- **Remotes are allow-listed.** `protocol.allow=never`, then only
  `Config.protocols` (default `https` and `ssh`). Local paths and `file://`
  need `file` in the list: with it, a URL from a user can clone any
  repository the process can read. `ext::`, `fd::` and
  every other `transport::address` form is refused before git sees it, and a
  `scheme://` URL cannot reach a `git-remote-<scheme>` helper on the `PATH`.
  `withProtocols` changes the list; `http` and `git` are unencrypted.
- **The environment cannot redirect a command.** `GIT_DIR`, `GIT_WORK_TREE`,
  `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY` and the other variables that beat
  `-C` are removed with `env -u` on every command.
- **git does not look above the repository.** `open` takes the top level:
  `GIT_CEILING_DIRECTORIES` stops a subdirectory of some other repository
  from being taken for it, and `open` compares the top level git reports
  with the one asked for.
- **Programs from the repository do not run.** Hooks are off
  (`core.hooksPath=/dev/null`) unless `withHooks` turns them on, the
  fsmonitor is off, and diffs and blame run no external diff or text
  conversion, which a `.gitattributes` in the repository could select.
- **Credentials stay out of error messages.** `https://user:token@...` is
  written `https://***@...` in the deck's messages; git strips it from its
  own.
- **Nothing waits for a person.** `GIT_TERMINAL_PROMPT=0`: a remote that
  wants a password fails instead of hanging. The locale is `C`, so messages
  are English and stable.
- **Every command has a timeout** (`withTimeout`, two minutes by default),
  and replaced objects (`refs/replace/`) are ignored, so an id names what it
  says.

## What it does not do

- **A repository's own configuration is still git's.** `.git/config` can
  set `core.sshCommand`, filters and aliases that run programs. git refuses
  repositories owned by another user (`safe.directory`); do not run the deck
  on a `.git` directory that came from an upload or an archive.
- **The timeout kills git, not its children.** An `ssh` or
  `git-remote-https` it started can outlive it until its connection drops.
  A command killed while writing can leave `.git/index.lock` behind; the
  next command that needs the index then fails until it is removed.
- **A URL can reach any host the machine can.** Cloning a user's
  `https://` or `ssh://` URL connects to internal hosts as readily as to
  GitHub; filter hosts before calling `clone` or `lsRemote` if that matters.
- **`run` is unchecked.** It passes your arguments as they are, after the
  hardened prefix. Never build them from user input.
- **Credentials are git's.** The deck never sees them: use an ssh agent,
  deploy keys, or a credential helper.
