<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# git cheatsheet

Every export of `@deckyard/git`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/git/" as git;
```

Every failure is `Error{kind: "git"}`. A `c` argument is a `Config`, an
`r` a `Repo`. Revisions and paths that may be "" say so in the guides.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `ERROR_KIND` | `"git"` | the `kind` of every error the deck throws |

## Types

### `Config`

| Field | Meaning |
|---|---|
| `binary as string` | the git program |
| `timeoutMs as int` | how long one command may run |
| `protocols as list of string` | the transports remotes may use |
| `hooks as bool` | whether the repository's hooks run |
| `name as string` | the author and committer name; "" for git's |
| `email as string` | their email; "" for git's |

### `Repo`

| Field | Meaning |
|---|---|
| `dir as string` | the absolute top-level directory |
| `config as Config` | the configuration |

### `Status`

| Field | Meaning |
|---|---|
| `head as string` | the commit checked out; "" before the first |
| `branch as string` | the branch; "" when detached |
| `upstream as string` | the branch it tracks |
| `ahead as int` | commits not on the upstream |
| `behind as int` | upstream commits not on it |
| `changes as list of Change` | changed and untracked files |

### `Change`

| Field | Meaning |
|---|---|
| `path as string` | the path |
| `origPath as string` | the path before a rename |
| `staged as string` | the index's letter, `.` for none |
| `unstaged as string` | the working tree's letter |
| `kind as string` | `changed`, `renamed`, `conflict`, `untracked` |

### `Commit`

| Field | Meaning |
|---|---|
| `hash as string` | its id |
| `parents as list of string` | its parents' ids |
| `author as string` | the author's name |
| `authorEmail as string` | the author's email |
| `authorTime as int` | Unix seconds |
| `committer as string` | the committer's name |
| `committerEmail as string` | the committer's email |
| `committerTime as int` | Unix seconds |
| `subject as string` | the first line |
| `body as string` | the rest of the message |

### `FileStat`

| Field | Meaning |
|---|---|
| `path as string` | the path |
| `oldPath as string` | the path before a rename |
| `added as int` | lines added |
| `removed as int` | lines removed |
| `binary as bool` | whether git saw a binary file |

### `FileChange`

| Field | Meaning |
|---|---|
| `status as string` | `A`, `M`, `D`, `R`, `C`, `T`, `U` |
| `path as string` | the path |
| `oldPath as string` | the path before a rename or copy |

### `BlameLine`

| Field | Meaning |
|---|---|
| `line as int` | the line number, from 1 |
| `hash as string` | the commit that last changed it |
| `author as string` | its author |
| `authorEmail as string` | the author's email |
| `authorTime as int` | Unix seconds |
| `text as string` | the line |

### `TreeEntry`

| Field | Meaning |
|---|---|
| `path as string` | the path from the top level |
| `type as string` | `blob`, `tree` or `commit` |
| `mode as string` | e.g. `100644` |
| `hash as string` | the object id |
| `size as int` | bytes; 0 for a tree |

### `Branch`

| Field | Meaning |
|---|---|
| `name as string` | e.g. `main`, `origin/main` |
| `hash as string` | the commit |
| `upstream as string` | the branch it tracks |
| `current as bool` | whether it is checked out |
| `ahead as int` | commits not on the upstream |
| `behind as int` | upstream commits not on it |
| `gone as bool` | whether the upstream was deleted |

### `Tag`

| Field | Meaning |
|---|---|
| `name as string` | e.g. `v1.2.0` |
| `hash as string` | the commit it points to |
| `annotated as bool` | whether it has its own message |
| `message as string` | its subject |

### `Remote`

| Field | Meaning |
|---|---|
| `name as string` | e.g. `origin` |
| `url as string` | where it fetches from |
| `pushUrl as string` | where it pushes to |

### `Ref`

| Field | Meaning |
|---|---|
| `name as string` | e.g. `refs/heads/main` |
| `hash as string` | the object |

### `Merge`

| Field | Meaning |
|---|---|
| `merged as bool` | whether it is done |
| `conflicts as list of string` | the files in conflict |

## Configuration

| Function | Returns | Does |
|---|---|---|
| `git.config()` | `Config` | safe defaults |
| `git.withBinary(c, binary)` | `Config` | another git program |
| `git.withTimeout(c, ms)` | `Config` | per-command timeout, at least 1000 |
| `git.withProtocols(c, protocols)` | `Config` | the transports remotes may use; default `https`, `ssh` |
| `git.withHooks(c, on)` | `Config` | let the repository's hooks run |
| `git.withIdentity(c, name, email)` | `Config` | commit as this person |
| `git.version(c)` | `string` | the git version line |
| `git.available(c)` | `bool` | whether git runs |

## Repositories

| Function | Returns | Does |
|---|---|---|
| `git.open(c, dir)` | `Repo` | a repository at its top level |
| `git.isRepo(c, dir)` | `bool` | whether `open` would accept it |
| `git.create(c, dir, bare)` | `Repo` | `git init` |
| `git.clone(c, url, dir)` | `Repo` | clone |
| `git.cloneWith(c, url, dir, branch, depth)` | `Repo` | clone one branch or a shallow history |
| `git.run(r, args)` | `string` | git with your own, unchecked arguments |

## Working tree

| Function | Returns | Does |
|---|---|---|
| `git.status(r)` | `Status` | branch, upstream, changed files |
| `git.isClean(r)` | `bool` | no changes, no untracked files |
| `git.add(r, paths)` | `null` | stage files |
| `git.addAll(r)` | `null` | stage everything |
| `git.remove(r, paths)` | `null` | delete files, stage that |
| `git.unstage(r, paths)` | `null` | take files out of the next commit |
| `git.restore(r, paths)` | `null` | discard working-tree changes |
| `git.commit(r, message)` | `string` | commit what is staged; the id |
| `git.amend(r, message)` | `string` | replace the last commit; the id |
| `git.stash(r, message)` | `bool` | put changes aside; false when none |
| `git.stashPop(r)` | `null` | bring them back |

## History

| Function | Returns | Does |
|---|---|---|
| `git.log(r, rev, path, limit)` | `list of Commit` | commits, newest first |
| `git.show(r, rev)` | `Commit` | one commit |
| `git.diff(r, base, target)` | `string` | the patch |
| `git.stagedDiff(r)` | `string` | the patch of what is staged |
| `git.diffStat(r, base, target)` | `list of FileStat` | lines added and removed per file |
| `git.changes(r, base, target)` | `list of FileChange` | which files changed, and how |
| `git.blame(r, rev, path)` | `list of BlameLine` | who last changed each line |
| `git.describe(r, rev)` | `string` | a name from the nearest tag |
| `git.readFile(r, rev, path)` | `string` | a text file at a revision |
| `git.readBytes(r, rev, path)` | `bytes` | any file at a revision |
| `git.listTree(r, rev, dir, recursive)` | `list of TreeEntry` | a directory at a revision |
| `git.archive(r, rev, file)` | `null` | `.zip`, `.tar` or `.tar.gz` of a revision |

## Branches and tags

| Function | Returns | Does |
|---|---|---|
| `git.revParse(r, rev)` | `string` | the commit id a revision names |
| `git.hasCommits(r)` | `bool` | false for an empty repository |
| `git.branches(r)` | `list of Branch` | the local branches |
| `git.remoteBranches(r)` | `list of Branch` | the remote-tracking branches |
| `git.currentBranch(r)` | `string` | the branch checked out; "" when detached |
| `git.createBranch(r, name, start)` | `null` | create a branch |
| `git.deleteBranch(r, name, force)` | `null` | delete a branch |
| `git.switchTo(r, name)` | `null` | check a branch out |
| `git.detach(r, rev)` | `null` | check a revision out, no branch |
| `git.setUpstream(r, branch, upstream)` | `null` | make a branch track a remote one |
| `git.tags(r)` | `list of Tag` | the tags |
| `git.createTag(r, name, rev, message)` | `null` | a tag; annotated with a message |
| `git.deleteTag(r, name)` | `null` | delete a tag |
| `git.mergeBase(r, a, b)` | `string` | where two revisions forked |
| `git.isAncestor(r, ancestor, rev)` | `bool` | whether one is in the other's history |
| `git.merge(r, rev, mode)` | `Merge` | merge; `ff`, `ff-only` or `no-ff` |
| `git.abortMerge(r)` | `null` | give up a merge in conflict |

## Remotes

| Function | Returns | Does |
|---|---|---|
| `git.remotes(r)` | `list of Remote` | the remotes |
| `git.addRemote(r, name, url)` | `null` | add one |
| `git.removeRemote(r, name)` | `null` | remove one |
| `git.setRemoteUrl(r, name, url)` | `null` | point one elsewhere |
| `git.fetch(r, remote)` | `null` | fetch and prune; "" for all |
| `git.pull(r, remote, branch)` | `null` | fetch and fast-forward |
| `git.push(r, remote, refspec, force)` | `null` | push; `force` is `--force-with-lease` |
| `git.pushTags(r, remote)` | `null` | push every tag |
| `git.lsRemote(c, url)` | `list of Ref` | a remote's refs, without cloning |
