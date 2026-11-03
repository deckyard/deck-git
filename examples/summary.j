#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * summary example: the branch and its upstream, what changed, the latest
 * commits and the tags of a repository.
 *
 * Needs git. Run with:
 *   jennifer run examples/summary.j [repository]
 */

use io;
use os;
use strings;

import "../src/git.j" as git;

def dir as string init ".";
if (len(os.ARGS) > 1) {
    $dir = os.ARGS[1];
}
def c as git.Config init git.config();
if (not git.available($c)) {
    io.printf("git is not installed\n");
    exit 1;
}
def repo as git.Repo;
try {
    $repo = git.open($c, $dir);
} catch (e) {
    io.printf("%s\n", $e.message);
    exit 1;
}
def s as git.Status init git.status($repo);
if ($s.branch == "") {
    io.printf("detached at %s\n", git.describe($repo, ""));
} else {
    io.printf("on %s", $s.branch);
    if ($s.upstream != "") {
        io.printf(", %d ahead and %d behind %s", $s.ahead, $s.behind, $s.upstream);
    }
    io.printf("\n");
}
for (def ch in $s.changes) {
    io.printf("  %s%s %s\n", $ch.staged, $ch.unstaged, $ch.path);
}
io.printf("\nlatest commits:\n");
for (def cm in git.log($repo, "", "", 5)) {
    io.printf("  %s %s (%s)\n", strings.substring($cm.hash, 0, 8), $cm.subject, $cm.author);
}
def tags as list of git.Tag init git.tags($repo);
if (len($tags) > 0) {
    io.printf("\ntags:");
    for (def t in $tags) {
        io.printf(" %s", $t.name);
    }
    io.printf("\n");
}
