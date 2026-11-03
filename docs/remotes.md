<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Branches and remotes

## Branches and tags

```jennifer
import "@deckyard/git/" as git;

def repo as git.Repo init git.open(git.config(), ".");
git.createBranch($repo, "feature/login", "");
git.switchTo($repo, "feature/login");
for (def b in git.branches($repo)) {
    io.printf("%s %s ahead %d behind %d\n", $b.name, $b.upstream, $b.ahead, $b.behind);
}
git.createTag($repo, "v1.2.0", "", "Release 1.2.0");
```

`revParse` turns a revision into a commit id, `currentBranch` says what is
checked out ("" when detached), `detach` checks a revision out without a
branch. `isAncestor` answers whether a branch is merged; `mergeBase` finds
where two branches forked. A `createTag` message makes an annotated tag.

## Merging

```jennifer
def m as git.Merge init git.merge($repo, "feature/login", "no-ff");
if (not $m.merged) {
    io.printf("conflicts in %s\n", strings.join($m.conflicts, ", "));
    git.abortMerge($repo);
}
```

The mode is `ff`, `ff-only` or `no-ff`. Conflicts are a result, not an
error: resolve the files, `add` and `commit`, or `abortMerge`.

## Remotes

| Function | Does |
|---|---|
| `remotes(repo)` | the remotes and their URLs |
| `addRemote(repo, name, url)`, `removeRemote`, `setRemoteUrl` | manage them |
| `fetch(repo, remote)` | fetch and prune; "" for all remotes |
| `pull(repo, remote, branch)` | fetch and fast-forward; "" for the upstream |
| `push(repo, remote, refspec, force)` | push `main`, `main:release`, `:old` |
| `pushTags(repo, remote)` | push every tag |
| `setUpstream(repo, branch, upstream)` | track `origin/main` |
| `remoteBranches(repo)` | the remote-tracking branches |
| `lsRemote(c, url)` | a remote's refs without cloning |

`pull` never makes a merge commit; when the branch has diverged it fails,
and `fetch` plus `merge` is the way on. `push` with `force` uses
`--force-with-lease`: it overwrites history there unless someone else pushed
since your last fetch. A refspec with `+` is refused for that reason.
