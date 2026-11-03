# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# git - revisions, branches, tags, merging, and remotes: fetch, pull, push.
# Spliced into git.j via include.

/**
 * A branch.
 *
 * @field name {string} e.g. `main`, or `origin/main` for a remote one
 * @field hash {string} the commit it points to
 * @field upstream {string} the branch it tracks; "" for none
 * @field current {bool} whether it is checked out
 * @field ahead {int} commits on it and not on its upstream
 * @field behind {int} commits on the upstream and not on it
 * @field gone {bool} whether its upstream was deleted
 */
export def struct Branch {
    name as string,
    hash as string,
    upstream as string,
    current as bool,
    ahead as int,
    behind as int,
    gone as bool
};

/**
 * A tag.
 *
 * @field name {string} e.g. `v1.2.0`
 * @field hash {string} the commit (or other object) it points to
 * @field annotated {bool} whether it is an annotated tag, with its own message
 * @field message {string} an annotated tag's subject; a lightweight tag's
 *   commit subject
 */
export def struct Tag {
    name as string,
    hash as string,
    annotated as bool,
    message as string
};

/**
 * A remote.
 *
 * @field name {string} e.g. `origin`
 * @field url {string} where it fetches from
 * @field pushUrl {string} where it pushes to
 */
export def struct Remote {
    name as string,
    url as string,
    pushUrl as string
};

/**
 * A ref on a remote, from `lsRemote`.
 *
 * @field name {string} e.g. `refs/heads/main`, `refs/tags/v1.0`, `HEAD`
 * @field hash {string} the object it points to
 */
export def struct Ref {
    name as string,
    hash as string
};

/**
 * The outcome of `merge`.
 *
 * @field merged {bool} true when the merge is done
 * @field conflicts {list of string} the files in conflict, when it is not;
 *   resolve them, `add` and `commit`, or `abortMerge`
 */
export def struct Merge {
    merged as bool,
    conflicts as list of string
};

/**
 * The commit a revision names.
 *
 * @param r {Repo} the repository
 * @param rev {string} e.g. `HEAD`, `main`, `v1.0`, `HEAD~2`, an abbreviated id
 * @return {string} the full commit id
 * @throws {Error} kind `"git"` when it names no commit
 */
export func revParse(r as Repo, rev as string) {
    def res as os.Result init gitTry(
        $r,
        ["rev-parse", "--verify", "--quiet", "--end-of-options", checkRev($rev) + "^\{commit\}"],
        "rev-parse");
    if ($res.exitCode != 0) {
        fail("no such commit: " + $rev);
    }
    return strings.trim($res.stdout);
}

/**
 * Whether the repository has a commit yet.
 *
 * @param r {Repo} the repository
 * @return {bool} false for a new, empty repository
 * @throws {Error} kind `"git"` when git cannot run
 */
export func hasCommits(r as Repo) {
    return gitTry($r, ["rev-parse", "--verify", "--quiet", "HEAD"], "rev-parse").exitCode == 0;
}

# The branch fields, NUL-separated, one branch per line.
def const BRANCH_FORMAT as string init "--format=%(refname:short)%00%(objectname)%00%(upstream:short)%00%(HEAD)%00%(upstream:track,nobracket)%00%(symref)";

/**
 * Parse `for-each-ref` with `BRANCH_FORMAT`.
 *
 * @param out {string} the output
 * @return {list of Branch} the branches, symbolic refs left out
 */
func branchesFrom(out as string) {
    def all as list of Branch init [];
    for (def l in lines($out)) {
        def f as list of string init strings.split($l, convert.fromCodepoint(0));
        if (len($f) < 6 or $f[5] != "") {
            continue;
        }
        def b as Branch init Branch{
            name: $f[0],
            hash: $f[1],
            upstream: $f[2],
            current: $f[3] == "*",
            ahead: 0,
            behind: 0,
            gone: $f[4] == "gone"
        };
        for (def part in strings.split($f[4], ", ")) {
            if (strings.startsWith($part, "ahead ")) {
                $b.ahead = toInt(strings.substring($part, 6));
            } elseif (strings.startsWith($part, "behind ")) {
                $b.behind = toInt(strings.substring($part, 7));
            }
        }
        $all[] = $b;
    }
    return $all;
}

/**
 * The local branches.
 *
 * @param r {Repo} the repository
 * @return {list of Branch} the branches, by name
 * @throws {Error} kind `"git"` when git fails
 */
export func branches(r as Repo) {
    return branchesFrom(gitOut($r, ["for-each-ref", BRANCH_FORMAT, "refs/heads"], "branches"));
}

/**
 * The remote-tracking branches, as of the last `fetch`.
 *
 * @param r {Repo} the repository
 * @return {list of Branch} the branches, e.g. `origin/main`
 * @throws {Error} kind `"git"` when git fails
 */
export func remoteBranches(r as Repo) {
    return branchesFrom(gitOut($r, ["for-each-ref", BRANCH_FORMAT, "refs/remotes"], "branches"));
}

/**
 * The branch checked out.
 *
 * @param r {Repo} the repository
 * @return {string} its name; "" when the head is detached
 * @throws {Error} kind `"git"` when git cannot run
 */
export func currentBranch(r as Repo) {
    def res as os.Result init gitTry($r, ["symbolic-ref", "--quiet", "--short", "HEAD"], "branch");
    if ($res.exitCode != 0) {
        return "";
    }
    return strings.trim($res.stdout);
}

/**
 * Create a branch, without switching to it.
 *
 * @param r {Repo} the repository
 * @param name {string} the name
 * @param start {string} the revision it starts at; "" for `HEAD`
 * @return {null} nothing
 * @throws {Error} kind `"git"` for a bad name, one that exists, or an unknown revision
 */
export func createBranch(r as Repo, name as string, start as string) {
    def args as list of string init ["branch", "--quiet", checkRef($name, "branch")];
    if ($start != "") {
        $args[] = checkRev($start);
    }
    gitIn($r, $args, "create branch " + $name);
    return null;
}

/**
 * Delete a branch.
 *
 * @param r {Repo} the repository
 * @param name {string} the name
 * @param force {bool} true to delete it even when it is not merged
 * @return {null} nothing
 * @throws {Error} kind `"git"` when it does not exist, is checked out, or is
 *   not merged and `force` is false
 */
export func deleteBranch(r as Repo, name as string, force as bool) {
    def flag as string init "-d";
    if ($force) {
        $flag = "-D";
    }
    gitIn($r, ["branch", "--quiet", $flag, checkRef($name, "branch")], "delete branch " + $name);
    return null;
}

/**
 * Check a branch out. A name that only exists on one remote becomes a local
 * branch tracking it.
 *
 * @param r {Repo} the repository
 * @param name {string} the branch
 * @return {null} nothing
 * @throws {Error} kind `"git"` when it does not exist, or local changes would be lost
 */
export func switchTo(r as Repo, name as string) {
    gitIn($r, ["switch", "--quiet", checkRef($name, "branch")], "switch " + $name);
    return null;
}

/**
 * Check a revision out without a branch (a detached head), e.g. a tag.
 *
 * @param r {Repo} the repository
 * @param rev {string} the revision
 * @return {null} nothing
 * @throws {Error} kind `"git"` for an unknown revision, or when local changes would be lost
 */
export func detach(r as Repo, rev as string) {
    gitIn($r, ["switch", "--quiet", "--detach", checkRev($rev)], "detach " + $rev);
    return null;
}

/**
 * Make a branch track a remote branch, for `pull`, `status` and `branches`.
 *
 * @param r {Repo} the repository
 * @param branch {string} the local branch
 * @param upstream {string} the remote branch, e.g. `origin/main`
 * @return {null} nothing
 * @throws {Error} kind `"git"` when either does not exist
 */
export func setUpstream(r as Repo, branch as string, upstream as string) {
    gitIn(
        $r,
        [
            "branch",
            "--quiet",
            "--set-upstream-to=" + checkRef($upstream, "branch"),
            checkRef($branch, "branch")
        ],
        "set upstream");
    return null;
}

/**
 * The tags.
 *
 * @param r {Repo} the repository
 * @return {list of Tag} the tags, by name
 * @throws {Error} kind `"git"` when git fails
 */
export func tags(r as Repo) {
    def out as string init gitOut(
        $r,
        [
            "for-each-ref",
            "--format=%(refname:short)%00%(objecttype)%00%(objectname)%00%(*objectname)%00%(contents:subject)%00%(*contents:subject)",
            "refs/tags"
        ],
        "tags");
    def all as list of Tag init [];
    for (def l in lines($out)) {
        def f as list of string init strings.split($l, convert.fromCodepoint(0));
        if (len($f) < 6) {
            continue;
        }
        def t as Tag init Tag{name: $f[0], hash: $f[2], annotated: $f[1] == "tag", message: $f[4]};
        if ($t.annotated and $f[3] != "") {
            $t.hash = $f[3];
        }
        $all[] = $t;
    }
    return $all;
}

/**
 * Create a tag.
 *
 * @param r {Repo} the repository
 * @param name {string} the name, e.g. `v1.2.0`
 * @param rev {string} what it points to; "" for `HEAD`
 * @param message {string} a message makes an annotated tag; "" a lightweight one
 * @return {null} nothing
 * @throws {Error} kind `"git"` for a bad name, one that exists, or an unknown revision
 */
export func createTag(r as Repo, name as string, rev as string, message as string) {
    def args as list of string init ["tag"];
    if ($message != "") {
        $args = lists.concat($args, ["--annotate", "--message=" + checkMessage($message)]);
    }
    $args[] = checkRef($name, "tag");
    if ($rev != "") {
        $args[] = checkRev($rev);
    }
    gitIn($r, $args, "tag " + $name);
    return null;
}

/**
 * Delete a tag, here only; `push` with `:refs/tags/<name>` deletes it on a remote.
 *
 * @param r {Repo} the repository
 * @param name {string} the name
 * @return {null} nothing
 * @throws {Error} kind `"git"` when it does not exist
 */
export func deleteTag(r as Repo, name as string) {
    gitIn($r, ["tag", "--delete", checkRef($name, "tag")], "delete tag " + $name);
    return null;
}

/**
 * The best common ancestor of two revisions, where they forked.
 *
 * @param r {Repo} the repository
 * @param a {string} one revision
 * @param b {string} the other
 * @return {string} the commit id
 * @throws {Error} kind `"git"` when they share no history
 */
export func mergeBase(r as Repo, a as string, b as string) {
    return strings.trim(gitOut(
        $r,
        ["merge-base", "--end-of-options", checkRev($a), checkRev($b)],
        "merge-base"));
}

/**
 * Whether one revision is in the history of another, e.g. whether a branch
 * is merged.
 *
 * @param r {Repo} the repository
 * @param ancestor {string} the possible ancestor
 * @param rev {string} the revision
 * @return {bool} true when `ancestor` is `rev` or one of its ancestors
 * @throws {Error} kind `"git"` for an unknown revision
 */
export func isAncestor(r as Repo, ancestor as string, rev as string) {
    def res as os.Result init gitTry(
        $r,
        ["merge-base", "--is-ancestor", "--end-of-options", checkRev($ancestor), checkRev($rev)],
        "merge-base");
    if ($res.exitCode > 1) {
        fail("merge-base: " + firstError($res.stderr));
    }
    return $res.exitCode == 0;
}

/**
 * Merge a revision into the branch checked out.
 *
 * @param r {Repo} the repository
 * @param rev {string} what to merge, e.g. `feature` or `origin/main`
 * @param mode {string} `ff` (fast-forward when possible), `ff-only` (refuse
 *   otherwise), or `no-ff` (always a merge commit)
 * @return {Merge} whether it merged, or the files in conflict
 * @throws {Error} kind `"git"` for an unknown mode or revision, or a merge
 *   git refuses (local changes in the way, `ff-only` impossible)
 */
export func merge(r as Repo, rev as string, mode as string) {
    if (not lists.contains(["ff", "ff-only", "no-ff"], $mode)) {
        fail("a merge mode is ff, ff-only or no-ff; got \"" + $mode + "\"");
    }
    def res as os.Result init gitTry(
        $r,
        ["merge", "--quiet", "--no-edit", "--" + $mode, checkRev($rev)],
        "merge " + $rev);
    if ($res.exitCode == 0) {
        return Merge{merged: true, conflicts: []};
    }
    def conflicts as list of string init nulFields(gitOut(
        $r,
        ["diff", "--name-only", "--diff-filter=U", "-z"],
        "merge"));
    if (len($conflicts) == 0) {
        fail("merge " + $rev + ": " + firstError($res.stderr));
    }
    return Merge{merged: false, conflicts: $conflicts};
}

/**
 * Give up a merge in conflict and go back to before it.
 *
 * @param r {Repo} the repository
 * @return {null} nothing
 * @throws {Error} kind `"git"` when no merge is in progress
 */
export func abortMerge(r as Repo) {
    gitIn($r, ["merge", "--abort"], "abort merge");
    return null;
}

/**
 * The remotes.
 *
 * @param r {Repo} the repository
 * @return {list of Remote} the remotes, by name
 * @throws {Error} kind `"git"` when git fails
 */
export func remotes(r as Repo) {
    def all as list of Remote init [];
    def index as map of string to int init {};
    for (def l in lines(gitOut($r, ["remote", "--verbose"], "remotes"))) {
        def tab as int init strings.indexOf($l, "\t");
        def sp as int init strings.lastIndexOf($l, " ");
        if ($tab < 0 or $sp < $tab) {
            continue;
        }
        def name as string init strings.substring($l, 0, $tab);
        def url as string init strings.substring($l, $tab + 1, $sp);
        if (not maps.has($index, $name)) {
            $index[$name] = len($all);
            $all[] = Remote{name: $name, url: "", pushUrl: ""};
        }
        def i as int init $index[$name];
        if (strings.endsWith($l, "(push)")) {
            $all[$i].pushUrl = $url;
        } else {
            $all[$i].url = $url;
        }
    }
    return $all;
}

/**
 * Add a remote.
 *
 * @param r {Repo} the repository
 * @param name {string} its name, e.g. `origin`
 * @param url {string} its URL
 * @return {null} nothing
 * @throws {Error} kind `"git"` for a bad name or URL, or one that exists
 */
export func addRemote(r as Repo, name as string, url as string) {
    gitIn(
        $r,
        ["remote", "add", "--", checkRef($name, "remote"), checkUrl($url)],
        "add remote " + $name);
    return null;
}

/**
 * Remove a remote and its remote-tracking branches.
 *
 * @param r {Repo} the repository
 * @param name {string} its name
 * @return {null} nothing
 * @throws {Error} kind `"git"` when it does not exist
 */
export func removeRemote(r as Repo, name as string) {
    gitIn($r, ["remote", "remove", checkRef($name, "remote")], "remove remote " + $name);
    return null;
}

/**
 * Point a remote at another URL.
 *
 * @param r {Repo} the repository
 * @param name {string} its name
 * @param url {string} the new URL
 * @return {null} nothing
 * @throws {Error} kind `"git"` for a bad URL, or when it does not exist
 */
export func setRemoteUrl(r as Repo, name as string, url as string) {
    gitIn(
        $r,
        ["remote", "set-url", "--", checkRef($name, "remote"), checkUrl($url)],
        "set remote " + $name);
    return null;
}

/**
 * Fetch from a remote, pruning branches deleted there.
 *
 * @param r {Repo} the repository
 * @param remote {string} its name; "" for every remote
 * @return {null} nothing
 * @throws {Error} kind `"git"` when it does not exist or cannot be reached
 */
export func fetch(r as Repo, remote as string) {
    def args as list of string init ["fetch", "--quiet", "--prune"];
    if ($remote == "") {
        $args[] = "--all";
    } else {
        $args = lists.concat($args, ["--end-of-options", checkRef($remote, "remote")]);
    }
    gitIn($r, $args, "fetch");
    return null;
}

/**
 * Fetch and fast-forward the branch checked out. It never makes a merge
 * commit: when the branch has diverged it fails, and `fetch` with `merge`
 * is the way on.
 *
 * @param r {Repo} the repository
 * @param remote {string} the remote; "" for the branch's upstream
 * @param branch {string} the remote's branch; "" for the branch's upstream
 * @return {null} nothing
 * @throws {Error} kind `"git"` for a branch without a remote, when it cannot
 *   fast-forward, or the remote fails
 */
export func pull(r as Repo, remote as string, branch as string) {
    def args as list of string init ["pull", "--quiet", "--ff-only"];
    if ($remote == "" and $branch != "") {
        fail("pull from a branch needs its remote");
    }
    if ($remote != "") {
        $args = lists.concat($args, ["--end-of-options", checkRef($remote, "remote")]);
        if ($branch != "") {
            $args[] = checkRef($branch, "branch");
        }
    }
    gitIn($r, $args, "pull");
    return null;
}

/**
 * Push to a remote.
 *
 * @param r {Repo} the repository
 * @param remote {string} the remote, e.g. `origin`
 * @param refspec {string} what to push: `main`, `main:release`,
 *   `refs/tags/v1.0`, or `:old` to delete `old` there
 * @param force {bool} true to overwrite history there, unless someone pushed
 *   since the last fetch (`--force-with-lease`)
 * @return {null} nothing
 * @throws {Error} kind `"git"` for a bad refspec, a rejected push, or when the
 *   remote fails
 */
export func push(r as Repo, remote as string, refspec as string, force as bool) {
    def args as list of string init ["push", "--quiet"];
    if ($force) {
        $args[] = "--force-with-lease";
    }
    $args = lists.concat($args, ["--", checkRef($remote, "remote"), checkRefspec($refspec)]);
    gitIn($r, $args, "push");
    return null;
}

/**
 * Push every tag to a remote.
 *
 * @param r {Repo} the repository
 * @param remote {string} the remote
 * @return {null} nothing
 * @throws {Error} kind `"git"` when the remote refuses or fails
 */
export func pushTags(r as Repo, remote as string) {
    gitIn($r, ["push", "--quiet", "--tags", "--", checkRef($remote, "remote")], "push tags");
    return null;
}

/**
 * Check a push refspec: `src`, `src:dst` or `:dst`, each a ref name. A
 * leading `+` (force) is refused; `push` has its own, safer, `force`.
 *
 * @param refspec {string} the refspec
 * @return {string} the refspec
 * @throws {Error} kind `"git"` naming the problem
 */
func checkRefspec(refspec as string) {
    if (strings.startsWith($refspec, "+")) {
        fail("a refspec may not start with +; push with force instead");
    }
    def parts as list of string init strings.split($refspec, ":");
    if (len($parts) > 2 or ($parts[0] == "" and len($parts) == 1)) {
        fail("a refspec is src, src:dst or :dst; got \"" + $refspec + "\"");
    }
    for (def p in $parts) {
        if ($p != "") {
            checkRef($p, "ref");
        }
    }
    return $refspec;
}

/**
 * The refs of a remote repository, without cloning it.
 *
 * @param c {Config} the configuration
 * @param url {string} the remote
 * @return {list of Ref} its branches, tags and `HEAD`
 * @throws {Error} kind `"git"` for a refused URL, or when it cannot be reached
 */
export func lsRemote(c as Config, url as string) {
    def res as os.Result init checked(
        execute($c, commandLine($c, "", ["ls-remote", "--", checkUrl($url)]), "ls-remote", ""),
        "ls-remote " + redact($url));
    def all as list of Ref init [];
    for (def l in lines($res.stdout)) {
        def tab as int init strings.indexOf($l, "\t");
        if ($tab < 0 or strings.endsWith($l, "^\{\}")) {
            continue;
        }
        $all[] = Ref{name: strings.substring($l, $tab + 1), hash: strings.substring($l, 0, $tab)};
    }
    return $all;
}
