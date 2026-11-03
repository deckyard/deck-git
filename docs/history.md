<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# History

## Commits

```jennifer
import "@deckyard/git/" as git;

def repo as git.Repo init git.open(git.config(), ".");
for (def c in git.log($repo, "v1.0..HEAD", "", 0)) {
    io.printf("%s %s <%s>\n", $c.subject, $c.author, $c.authorEmail);
}
def tip as git.Commit init git.show($repo, "HEAD");
```

`log(repo, rev, path, limit)` starts at `rev` ("" for `HEAD`) or walks a
range, keeps the commits touching `path` when one is given, and stops after
`limit` (0 for all). Before the first commit it returns an empty list. Times
are Unix seconds.

## Diffs

`base` and `target` pick what is compared:

| `base` | `target` | compares |
|---|---|---|
| "" | "" | the index against the working tree: unstaged changes |
| a revision | "" | that revision against the working tree |
| a revision | a revision | the two revisions |

```jennifer
def patch as string init git.diff($repo, "v1.0", "HEAD");
for (def s in git.diffStat($repo, "v1.0", "HEAD")) {
    io.printf("+%d -%d %s\n", $s.added, $s.removed, $s.path);
}
for (def ch in git.changes($repo, "HEAD~1", "HEAD")) {
    io.printf("%s %s\n", $ch.status, $ch.path);
}
```

`stagedDiff` is what `commit` would record. Renames are detected, and
external diff programs never run.

## Files at a revision

| Function | Does |
|---|---|
| `readFile(repo, rev, path)` | a text file's contents |
| `readBytes(repo, rev, path)` | any file's contents, as bytes |
| `listTree(repo, rev, dir, recursive)` | the entries of a directory |
| `blame(repo, rev, path)` | who last changed each line |
| `describe(repo, rev)` | `v1.2-3-gabc1234`, from the nearest tag |
| `archive(repo, rev, file)` | the files as `.zip`, `.tar` or `.tar.gz` |

A captured output stops at 16 MiB, and the call then fails rather than
return part of it: `readBytes` and `archive` go through files and have no
such limit, and `log` takes a `limit`.
