# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0
# pragma-jennifer-capability: exec

/**
 * Git repositories through the git command line.
 *
 * Open, create or clone a repository; read its status, history, diffs,
 * blame and files at any revision; stage, commit, stash, branch, tag, merge,
 * fetch, pull and push. Results are structs, parsed from git's
 * machine-readable output (`-z`, porcelain formats), so file names with
 * spaces or newlines come through intact.
 *
 * Built for names and URLs you do not control. Branch, tag and remote names
 * are checked as git checks them, revisions and URLs may not start with `-`,
 * paths always follow `--` and are literal (no globs), remote helpers and
 * unlisted transports are refused, and the environment variables that point
 * git at another repository are removed. Hooks and the fsmonitor are off,
 * prompts never wait, and every command is killed when it runs too long.
 * Every failure is `Error{kind: "git"}`.
 *
 * | topic | covers |
 * | --- | --- |
 * | `core` | the configuration, the hardened command line, the checks, `run` |
 * | `repo` | open, init, clone, status, staging, commit, stash |
 * | `history` | log, show, diffs, blame, describe, file contents, trees, archives |
 * | `refs` | revisions, branches, tags, merge, remotes, fetch, pull, push |
 *
 * @module git
 * @see https://git-scm.com/docs
 * @example
 *   def repo as git.Repo init git.open(git.config(), ".");
 *   def s as git.Status init git.status($repo);
 *   for (def c in git.log($repo, "", "", 5)) {
 *       io.printf("%s %s\n", strings.substring($c.hash, 0, 8), $c.subject);
 *   }
 */
use convert;
use fs;
use lists;
use maps;
use os;
use path;
use regex;
use strings;
use time;

include "topics/core.j";
include "topics/repo.j";
include "topics/history.j";
include "topics/refs.j";
