<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Working trees and commits

## Opening, creating, cloning

```jennifer
import "@deckyard/git/" as git;

def c as git.Config init git.withIdentity(git.config(), "Site Bot", "bot@example.com");
def repo as git.Repo init git.open($c, "/srv/site");               # an existing one
def fresh as git.Repo init git.create($c, "/srv/new", false);      # git init
def hub as git.Repo init git.create($c, "/srv/hub.git", true);     # bare, to push to
def copy as git.Repo init git.clone($c, "https://github.com/deckyard/deck-git.git", "/tmp/deck-git");
def shallow as git.Repo init git.cloneWith($c, "git@github.com:deckyard/deck-git.git", "/tmp/one", "main", 1);
```

`open` wants the top level of the working tree (or a bare repository's
directory); `isRepo` asks without throwing. Cloning, fetching from or
pushing to a local path needs `withProtocols($c, ["https", "ssh", "file"])`. `withIdentity` sets the author
and committer for every commit, for services that have no git configuration
of their own.

## Status

```jennifer
def s as git.Status init git.status($repo);
io.printf("on %s, %d ahead of %s\n", $s.branch, $s.ahead, $s.upstream);
for (def ch in $s.changes) {
    io.printf("%s%s %s\n", $ch.staged, $ch.unstaged, $ch.path);
}
```

Each `Change` has the staged and unstaged letter (`M`, `A`, `D`, `R` ...,
`.` for none), a `kind` (`changed`, `renamed`, `conflict`, `untracked`) and,
for a rename, the `origPath`. `isClean` is true when there is nothing at all.

## Staging and committing

| Function | Does |
|---|---|
| `add(repo, paths)` | stage new, changed or deleted files |
| `addAll(repo)` | stage everything, untracked files included |
| `remove(repo, paths)` | delete files and stage that |
| `unstage(repo, paths)` | take files out of the next commit, keep the changes |
| `restore(repo, paths)` | discard the working tree's changes to files |
| `commit(repo, message)` | commit what is staged; returns the id |
| `amend(repo, message)` | replace the last commit; "" keeps its message |

```jennifer
fs.writeString($repo.dir + "/index.html", "<h1>hello</h1>\n");
git.add($repo, ["index.html"]);
def id as string init git.commit($repo, "Publish the front page");
```

## Stashing

`stash(repo, message)` puts the changes aside, untracked files included, and
returns false when there were none; `stashPop(repo)` brings them back.
