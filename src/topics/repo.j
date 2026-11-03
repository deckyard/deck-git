# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# git - opening, creating and cloning repositories, the working tree's
# status, staging, committing and stashing. Spliced into git.j via include.

/**
 * One changed file in `status`.
 *
 * @field path {string} the path, relative to the top level
 * @field origPath {string} the path it was renamed or copied from; "" otherwise
 * @field staged {string} the change in the index: `M`, `A`, `D`, `R`, `C`,
 *   `T`, `U`, or `.` for none
 * @field unstaged {string} the change in the working tree, the same letters
 * @field kind {string} `changed`, `renamed`, `conflict` or `untracked`
 */
export def struct Change {
    path as string,
    origPath as string,
    staged as string,
    unstaged as string,
    kind as string
};

/**
 * The state of the working tree.
 *
 * @field head {string} the commit checked out; "" before the first commit
 * @field branch {string} the branch checked out; "" when detached
 * @field upstream {string} the branch it tracks, e.g. `origin/main`; "" for none
 * @field ahead {int} commits on the branch and not on its upstream
 * @field behind {int} commits on the upstream and not on the branch
 * @field changes {list of Change} the changed and untracked files
 */
export def struct Status {
    head as string,
    branch as string,
    upstream as string,
    ahead as int,
    behind as int,
    changes as list of Change
};

/**
 * Open a repository at its top level (or a bare one at its git directory).
 * git does not look above the directory: a subdirectory of a repository is
 * refused, not taken for the repository around it.
 *
 * @param c {Config} the configuration
 * @param dir {string} the directory
 * @return {Repo} the repository
 * @throws {Error} kind `"git"` when it is not a repository's top level
 */
export func open(c as Config, dir as string) {
    def r as Repo init Repo{dir: absolute($dir), config: $c};
    if (not fs.isDir($r.dir)) {
        fail("no such directory: " + $dir);
    }
    def res as os.Result init gitTry(
        $r,
        ["rev-parse", "--is-bare-repository", "--absolute-git-dir"],
        "open");
    if ($res.exitCode != 0) {
        fail($dir + " is not the top level of a git repository: " + firstError($res.stderr));
    }
    # The ceiling stops git looking upwards, but GIT_CEILING_DIRECTORIES is
    # colon-separated, so a parent like /srv/a:b defeats it. Compare.
    def answer as list of string init lines($res.stdout);
    def found as string init $answer[1];
    if ($answer[0] != "true") {
        $found = strings.trim(gitOut($r, ["rev-parse", "--show-toplevel"], "open"));
    }
    if ($found != $r.dir) {
        fail($dir + " is not the top level of a git repository; " + $found + " is");
    }
    return $r;
}

/**
 * Whether a directory is the top level of a repository.
 *
 * @param c {Config} the configuration
 * @param dir {string} the directory
 * @return {bool} true when `open` would accept it
 */
export func isRepo(c as Config, dir as string) {
    try {
        open($c, $dir);
        return true;
    } catch (e) {
        return false;
    }
}

/**
 * Create a repository, and the directory when it does not exist.
 *
 * @param c {Config} the configuration
 * @param dir {string} the directory
 * @param bare {bool} true for a bare repository, e.g. one to push to
 * @return {Repo} the repository
 * @throws {Error} kind `"git"` when git fails
 */
export func create(c as Config, dir as string, bare as bool) {
    def abs as string init absolute($dir);
    def args as list of string init ["init", "--quiet"];
    if ($bare) {
        $args[] = "--bare";
    }
    $args = lists.concat($args, ["--", $abs]);
    checked(execute($c, commandLine($c, "", $args), "init", ""), "init " + $dir);
    return open($c, $abs);
}

/**
 * Clone a repository.
 *
 * @param c {Config} the configuration
 * @param url {string} the remote: an `https://` or `ssh://` URL, `host:path`,
 *   or a local path, as `Config.protocols` allows
 * @param dir {string} the new directory
 * @return {Repo} the clone
 * @throws {Error} kind `"git"` for a refused URL, or when git fails
 */
export func clone(c as Config, url as string, dir as string) {
    return cloneWith($c, $url, $dir, "", 0);
}

/**
 * Clone one branch, or a shallow history.
 *
 * @param c {Config} the configuration
 * @param url {string} the remote
 * @param dir {string} the new directory
 * @param branch {string} the branch or tag to check out; "" for the default
 * @param depth {int} how many commits to fetch; 0 for all
 * @return {Repo} the clone
 * @throws {Error} kind `"git"` for a refused URL or branch, or when git fails
 */
export func cloneWith(c as Config, url as string, dir as string, branch as string, depth as int) {
    def abs as string init absolute($dir);
    def args as list of string init ["clone", "--quiet"];
    if ($branch != "") {
        $args = lists.concat($args, ["--branch", checkRef($branch, "branch")]);
    }
    if ($depth < 0) {
        fail("a depth is 0 or more");
    }
    if ($depth > 0) {
        $args = lists.concat($args, ["--depth", convert.toString($depth)]);
    }
    $args = lists.concat($args, ["--", checkUrl($url), $abs]);
    checked(execute($c, commandLine($c, "", $args), "clone", ""), "clone " + redact($url));
    return open($c, $abs);
}

/**
 * The state of the working tree: the branch, its upstream, and every changed
 * or untracked file. Ignored files are left out.
 *
 * @param r {Repo} the repository
 * @return {Status} the state
 * @throws {Error} kind `"git"` when git fails, e.g. for a bare repository
 */
export func status(r as Repo) {
    return statusFrom(gitOut($r, ["status", "--porcelain=v2", "--branch", "-z"], "status"));
}

/**
 * Parse `git status --porcelain=v2 --branch -z`.
 *
 * @param out {string} the output
 * @return {Status} the state
 */
func statusFrom(out as string) {
    def s as Status;
    def fields as list of string init nulFields($out);
    def i as int init 0;
    while ($i < len($fields)) {
        def f as string init $fields[$i];
        $i = $i + 1;
        if (strings.startsWith($f, "# ")) {
            $s = statusHeader($s, $f);
        } elseif (strings.startsWith($f, "1 ")) {
            $s.changes[] = changeFrom($f, 8, "changed", "");
        } elseif (strings.startsWith($f, "2 ")) {
            $s.changes[] = changeFrom($f, 9, "renamed", $fields[$i]);
            $i = $i + 1;
        } elseif (strings.startsWith($f, "u ")) {
            $s.changes[] = changeFrom($f, 10, "conflict", "");
        } elseif (strings.startsWith($f, "? ")) {
            $s.changes[] = Change{
                path: strings.substring($f, 2),
                origPath: "",
                staged: ".",
                unstaged: ".",
                kind: "untracked"
            };
        }
    }
    return $s;
}

/**
 * Fold one `# branch.*` header into the status.
 *
 * @param s {Status} the status so far
 * @param line {string} the header
 * @return {Status} the status
 */
func statusHeader(s as Status, line as string) {
    def parts as list of string init strings.split($line, " ");
    if (len($parts) < 3) {
        return $s;
    }
    def key as string init $parts[1];
    def value as string init $parts[2];
    if ($key == "branch.oid" and $value != "(initial)") {
        $s.head = $value;
    } elseif ($key == "branch.head" and $value != "(detached)") {
        $s.branch = $value;
    } elseif ($key == "branch.upstream") {
        $s.upstream = $value;
    } elseif ($key == "branch.ab" and len($parts) >= 4) {
        $s.ahead = toInt(strings.substring($value, 1));
        $s.behind = toInt(strings.substring($parts[3], 1));
    }
    return $s;
}

/**
 * One tracked entry of `status`: fixed fields, then the path, which may hold
 * spaces.
 *
 * @param line {string} the entry
 * @param skip {int} how many space-separated fields come before the path
 * @param kind {string} the kind
 * @param orig {string} the original path, for a rename
 * @return {Change} the change
 */
func changeFrom(line as string, skip as int, kind as string, orig as string) {
    def parts as list of string init strings.split($line, " ");
    def xy as string init $parts[1];
    return Change{
        path: strings.join(lists.slice($parts, $skip), " "),
        origPath: $orig,
        staged: strings.substring($xy, 0, 1),
        unstaged: strings.substring($xy, 1, 2),
        kind: $kind
    };
}

/**
 * Whether the working tree has no changes and no untracked files.
 *
 * @param r {Repo} the repository
 * @return {bool} true when it is clean
 * @throws {Error} kind `"git"` when git fails
 */
export func isClean(r as Repo) {
    return len(status($r).changes) == 0;
}

/**
 * Stage files: new, changed or deleted.
 *
 * @param r {Repo} the repository
 * @param paths {list of string} the paths, taken literally (no globs)
 * @return {null} nothing
 * @throws {Error} kind `"git"` when git fails, e.g. for a path that does not exist
 */
export func add(r as Repo, paths as list of string) {
    gitIn($r, lists.concat(["add", "--"], checkPaths($paths)), "add");
    return null;
}

/**
 * Stage every change in the working tree, untracked files included.
 *
 * @param r {Repo} the repository
 * @return {null} nothing
 * @throws {Error} kind `"git"` when git fails
 */
export func addAll(r as Repo) {
    gitIn($r, ["add", "--all"], "add");
    return null;
}

/**
 * Delete files from the working tree and stage the deletion.
 *
 * @param r {Repo} the repository
 * @param paths {list of string} the paths
 * @return {null} nothing
 * @throws {Error} kind `"git"` when git fails
 */
export func remove(r as Repo, paths as list of string) {
    gitIn($r, lists.concat(["rm", "--quiet", "--"], checkPaths($paths)), "remove");
    return null;
}

/**
 * Take files out of the next commit, keeping their changes in the working tree.
 *
 * @param r {Repo} the repository
 * @param paths {list of string} the paths
 * @return {null} nothing
 * @throws {Error} kind `"git"` when git fails
 */
export func unstage(r as Repo, paths as list of string) {
    gitIn($r, lists.concat(["restore", "--staged", "--"], checkPaths($paths)), "unstage");
    return null;
}

/**
 * Discard the working tree's changes to files, back to what is staged. The
 * changes are lost.
 *
 * @param r {Repo} the repository
 * @param paths {list of string} the paths
 * @return {null} nothing
 * @throws {Error} kind `"git"` when git fails
 */
export func restore(r as Repo, paths as list of string) {
    gitIn($r, lists.concat(["restore", "--worktree", "--"], checkPaths($paths)), "restore");
    return null;
}

/**
 * Commit what is staged.
 *
 * @param r {Repo} the repository
 * @param message {string} the message; the first line is the subject
 * @return {string} the new commit's id
 * @throws {Error} kind `"git"` for a blank message, nothing staged, no
 *   identity, or when git fails
 */
export func commit(r as Repo, message as string) {
    gitIn($r, ["commit", "--quiet", "--message=" + checkMessage($message)], "commit");
    return revParse($r, "HEAD");
}

/**
 * Replace the last commit with one holding what is staged too.
 *
 * @param r {Repo} the repository
 * @param message {string} the new message; "" keeps the old one
 * @return {string} the new commit's id
 * @throws {Error} kind `"git"` when git fails
 */
export func amend(r as Repo, message as string) {
    def args as list of string init ["commit", "--quiet", "--amend"];
    if ($message == "") {
        $args[] = "--no-edit";
    } else {
        $args[] = "--message=" + checkMessage($message);
    }
    gitIn($r, $args, "amend");
    return revParse($r, "HEAD");
}

/**
 * Put the working tree's changes, untracked files included, aside and leave
 * it clean.
 *
 * @param r {Repo} the repository
 * @param message {string} a description; "" for git's
 * @return {bool} false when there was nothing to put aside
 * @throws {Error} kind `"git"` when git fails
 */
export func stash(r as Repo, message as string) {
    if (isClean($r)) {
        return false;
    }
    def args as list of string init ["stash", "push", "--quiet", "--include-untracked"];
    if ($message != "") {
        $args[] = "--message=" + checkMessage($message);
    }
    # Literal pathspecs stop `--include-untracked` from cleaning the files it
    # saved, and the next `stashPop` then refuses to restore them.
    def argv as list of string init [];
    for (def a in commandLine($r.config, $r.dir, $args)) {
        if ($a != "--literal-pathspecs") {
            $argv[] = $a;
        }
    }
    checked(execute($r.config, $argv, "stash", ""), "stash");
    return true;
}

/**
 * Bring back the changes `stash` put aside last, and drop them from the stash.
 *
 * @param r {Repo} the repository
 * @return {null} nothing
 * @throws {Error} kind `"git"` when there is no stash, or they conflict with
 *   the working tree
 */
export func stashPop(r as Repo) {
    gitIn($r, ["stash", "pop", "--quiet"], "stash pop");
    return null;
}
