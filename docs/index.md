<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/git

Git repositories through the `git` command line. The deck builds a checked
argument list, runs git, and parses its machine-readable output (`-z`,
porcelain formats) into structs, so file names with spaces or line breaks
come through intact.

It is not a reimplementation of git: it needs git installed, and it gets
everything git has, including credential helpers, the ssh agent and the
user's configuration.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/git/" as git;

def c as git.Config init git.config();
def repo as git.Repo init git.open($c, "/srv/site");
```

A `Config` says which program to run and how; `config()` gives safe
defaults (see [Security](security.md)). A `Repo` is a directory plus the
configuration its commands run with; `open`, `create` and `clone` return one.

Revisions are anything git accepts: `HEAD`, `main`, `v1.0`, `HEAD~2`, an
abbreviated id, a range `v1.0..main`. Paths are relative to the top level
and literal: `*.txt` names a file called `*.txt`, it is not a pattern.

## Errors

Every failure is `Error{kind: "git"}`, its message naming the operation:

- a refused name, revision, path or URL, before anything runs:
  `git: not a valid branch name: "a..b"`;
- git's own explanation, its `fatal:` or `error:` line:
  `git: switch nope: fatal: invalid reference: nope`;
- a timeout: `git: fetch: killed after 120000 ms`;
- output past 16 MiB: `git: log: the output passed 16 MiB; narrow the query`;
- a missing program: `git: cannot run git (is git installed?)`.

`merge` reports conflicts in its result instead of throwing.

## Requirements

Jennifer 0.25.0 or newer, default `jennifer` binary: the deck needs the
`exec` capability, which `jennifer-tiny` lacks. git 2.25 or newer
(`switch`, `restore`, `--end-of-options`) and `env` on the `PATH`.
