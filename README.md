# @deckyard/git

[![test](https://github.com/deckyard/deck-git/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-git/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-git/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-git)](https://github.com/deckyard/deck-git/releases/latest)

Git repositories for [Jennifer](https://jennifer-lang.dev/) through the
`git` command line: open, create and clone repositories; status, staging,
commits and stashes; log, diffs, blame and files at any revision; branches,
tags and merges; fetch, pull and push. Results are typed structs parsed from
git's machine-readable output. Built for names and URLs you do not control:
option injection, remote helpers, repository-redirecting environment
variables and hooks are all shut off, and every command has a timeout.

**[Documentation](https://deckyard.github.io/deck-git/)**

## Install

```sh
jvc add @deckyard/git
```

Or unpack `src/` from a release archive (`deckyard-git-<version>.tar.gz`)
into `vendor/deckyard/git/`.

## Usage

```jennifer
import "@deckyard/git/" as git;

def repo as git.Repo init git.open(git.config(), ".");
def s as git.Status init git.status($repo);
io.printf("%s, %d changed\n", $s.branch, len($s.changes));
for (def c in git.log($repo, "", "", 5)) {
    io.printf("%s %s\n", strings.substring($c.hash, 0, 8), $c.subject);
}
```

## Requirements

Jennifer 0.25.0 or newer and the default `jennifer` binary (the deck needs
the `exec` capability); git 2.25 or newer and `env` on the `PATH`.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/git_test.j         # tests; the live ones need git
tools/check-docs.sh                  # docs against the code
```

The tests that run git use throwaway repositories in the temp directory and
no network. They return early where git is not installed, as in CI's
container; run the suite on a machine with git before a release.

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

Git is a trademark of the Software Freedom Conservancy. This deck is not
affiliated with or endorsed by it.
