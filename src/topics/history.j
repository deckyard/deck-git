# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# git - reading history: commits, diffs, blame, file contents at a revision,
# trees and archives. Spliced into git.j via include.

/**
 * A commit.
 *
 * @field hash {string} its id
 * @field parents {list of string} its parents' ids; two or more for a merge
 * @field author {string} the author's name
 * @field authorEmail {string} the author's email
 * @field authorTime {int} when it was written, in Unix seconds
 * @field committer {string} the committer's name
 * @field committerEmail {string} the committer's email
 * @field committerTime {int} when it was committed, in Unix seconds
 * @field subject {string} the message's first line
 * @field body {string} the rest of the message
 */
export def struct Commit {
    hash as string,
    parents as list of string,
    author as string,
    authorEmail as string,
    authorTime as int,
    committer as string,
    committerEmail as string,
    committerTime as int,
    subject as string,
    body as string
};

/**
 * Lines added and removed in one file.
 *
 * @field path {string} the path
 * @field oldPath {string} the path before a rename; "" otherwise
 * @field added {int} lines added; 0 for a binary file
 * @field removed {int} lines removed; 0 for a binary file
 * @field binary {bool} whether git saw a binary file
 */
export def struct FileStat {
    path as string,
    oldPath as string,
    added as int,
    removed as int,
    binary as bool
};

/**
 * How one file changed.
 *
 * @field status {string} `A` added, `M` modified, `D` deleted, `R` renamed,
 *   `C` copied, `T` type changed, `U` unmerged
 * @field path {string} the path
 * @field oldPath {string} the path before a rename or copy; "" otherwise
 */
export def struct FileChange {
    status as string,
    path as string,
    oldPath as string
};

/**
 * One line of `blame`.
 *
 * @field line {int} the line number, from 1
 * @field hash {string} the commit that last changed it
 * @field author {string} that commit's author
 * @field authorEmail {string} the author's email
 * @field authorTime {int} when, in Unix seconds
 * @field text {string} the line
 */
export def struct BlameLine {
    line as int,
    hash as string,
    author as string,
    authorEmail as string,
    authorTime as int,
    text as string
};

/**
 * One entry of a tree.
 *
 * @field path {string} the path from the top level
 * @field type {string} `blob` (a file), `tree` (a directory) or `commit` (a submodule)
 * @field mode {string} e.g. `100644`, `100755`, `120000` (a symbolic link)
 * @field hash {string} the object id
 * @field size {int} the size in bytes; 0 for a tree or submodule
 */
export def struct TreeEntry {
    path as string,
    type as string,
    mode as string,
    hash as string,
    size as int
};

# The ten fields of a commit, NUL-separated; `-z` ends each commit with one more.
def const COMMIT_FORMAT as string init "--format=%H%x00%P%x00%an%x00%ae%x00%at%x00%cn%x00%ce%x00%ct%x00%s%x00%b";

/**
 * Commits, newest first.
 *
 * @param r {Repo} the repository
 * @param rev {string} where to start, or a range such as `v1.0..main`; ""
 *   for the checked-out commit
 * @param path {string} only commits touching this path; "" for all
 * @param limit {int} the most commits to return; 0 for no limit
 * @return {list of Commit} the commits; empty before the first commit
 * @throws {Error} kind `"git"` for an unknown revision, or when git fails
 */
export func log(r as Repo, rev as string, path as string, limit as int) {
    if ($rev == "" and not hasCommits($r)) {
        return [];
    }
    def args as list of string init ["log", "-z", COMMIT_FORMAT];
    if ($limit < 0) {
        fail("a limit is 0 or more");
    }
    if ($limit > 0) {
        $args[] = "--max-count=" + convert.toString($limit);
    }
    $args[] = "--end-of-options";
    if ($rev != "") {
        $args[] = checkRev($rev);
    }
    $args[] = "--";
    if ($path != "") {
        $args[] = $path;
    }
    return commitsFrom(gitOut($r, $args, "log"));
}

/**
 * One commit.
 *
 * @param r {Repo} the repository
 * @param rev {string} the revision, e.g. `HEAD`, `v1.0`, an id
 * @return {Commit} the commit
 * @throws {Error} kind `"git"` for an unknown revision
 */
export func show(r as Repo, rev as string) {
    def found as list of Commit init commitsFrom(gitOut(
        $r,
        ["log", "-z", COMMIT_FORMAT, "--max-count=1", "--end-of-options", checkRev($rev), "--"],
        "show " + $rev));
    if (len($found) == 0) {
        fail("show " + $rev + ": no such commit");
    }
    return $found[0];
}

/**
 * Parse commits printed with `COMMIT_FORMAT` and `-z`.
 *
 * @param out {string} the output
 * @return {list of Commit} the commits
 */
func commitsFrom(out as string) {
    def all as list of Commit init [];
    def f as list of string init nulFields($out);
    def i as int init 0;
    while ($i + 10 <= len($f)) {
        def parents as list of string init [];
        for (def p in strings.split($f[$i + 1], " ")) {
            if ($p != "") {
                $parents[] = $p;
            }
        }
        $all[] = Commit{
            hash: $f[$i],
            parents: $parents,
            author: $f[$i + 2],
            authorEmail: $f[$i + 3],
            authorTime: toInt($f[$i + 4]),
            committer: $f[$i + 5],
            committerEmail: $f[$i + 6],
            committerTime: toInt($f[$i + 7]),
            subject: $f[$i + 8],
            body: strings.trim($f[$i + 9])
        };
        $i = $i + 10;
    }
    return $all;
}

/**
 * The arguments that pick what a diff compares.
 *
 * @param base {string} a revision; "" for the index
 * @param target {string} a revision; "" for the working tree
 * @return {list of string} the arguments, ending in `--`
 */
func diffRange(base as string, target as string) {
    if ($base == "" and $target != "") {
        fail("a diff to a revision needs a revision to start from");
    }
    def args as list of string init ["--end-of-options"];
    if ($base != "") {
        $args[] = checkRev($base);
    }
    if ($target != "") {
        $args[] = checkRev($target);
    }
    $args[] = "--";
    return $args;
}

/**
 * The patch between two states, as `git diff` prints it. External diff
 * programs and text conversion filters are not run.
 *
 * @param r {Repo} the repository
 * @param base {string} a revision; "" for the index (what is staged)
 * @param target {string} a revision; "" for the working tree
 * @return {string} the patch; "" when nothing differs
 * @throws {Error} kind `"git"` for an unknown revision, or a patch over 16 MiB
 */
export func diff(r as Repo, base as string, target as string) {
    return gitOut(
        $r,
        lists.concat(
            ["diff", "--no-color", "--no-ext-diff", "--no-textconv"],
            diffRange($base, $target)),
        "diff");
}

/**
 * The patch of what is staged against the last commit: what `commit` would
 * record.
 *
 * @param r {Repo} the repository
 * @return {string} the patch; "" when nothing is staged
 * @throws {Error} kind `"git"` when git fails
 */
export func stagedDiff(r as Repo) {
    return gitOut(
        $r,
        ["diff", "--cached", "--no-color", "--no-ext-diff", "--no-textconv", "--"],
        "diff");
}

/**
 * Lines added and removed per file, renames detected.
 *
 * @param r {Repo} the repository
 * @param base {string} a revision; "" for the index
 * @param target {string} a revision; "" for the working tree
 * @return {list of FileStat} one per changed file
 * @throws {Error} kind `"git"` for an unknown revision
 */
export func diffStat(r as Repo, base as string, target as string) {
    def out as string init gitOut(
        $r,
        lists.concat(["diff", "--numstat", "-z", "-M", "--no-ext-diff"], diffRange($base, $target)),
        "diff");
    def all as list of FileStat init [];
    def f as list of string init nulFields($out);
    def i as int init 0;
    while ($i < len($f)) {
        def parts as list of string init strings.split($f[$i], "\t");
        $i = $i + 1;
        if (len($parts) < 3) {
            continue;
        }
        def s as FileStat init FileStat{
            path: $parts[2],
            oldPath: "",
            added: toInt($parts[0]),
            removed: toInt($parts[1]),
            binary: $parts[0] == "-"
        };
        if ($parts[2] == "" and $i + 1 < len($f)) {
            $s.oldPath = $f[$i];
            $s.path = $f[$i + 1];
            $i = $i + 2;
        }
        $all[] = $s;
    }
    return $all;
}

/**
 * Which files changed and how, renames detected.
 *
 * @param r {Repo} the repository
 * @param base {string} a revision; "" for the index
 * @param target {string} a revision; "" for the working tree
 * @return {list of FileChange} one per changed file
 * @throws {Error} kind `"git"` for an unknown revision
 */
export func changes(r as Repo, base as string, target as string) {
    def out as string init gitOut(
        $r,
        lists.concat(
            ["diff", "--name-status", "-z", "-M", "--no-ext-diff"],
            diffRange($base, $target)),
        "diff");
    def all as list of FileChange init [];
    def f as list of string init nulFields($out);
    def i as int init 0;
    while ($i + 1 < len($f)) {
        def letter as string init strings.substring($f[$i], 0, 1);
        if ($letter == "R" or $letter == "C") {
            $all[] = FileChange{status: $letter, path: $f[$i + 2], oldPath: $f[$i + 1]};
            $i = $i + 3;
        } else {
            $all[] = FileChange{status: $letter, path: $f[$i + 1], oldPath: ""};
            $i = $i + 2;
        }
    }
    return $all;
}

/**
 * Who last changed each line of a file.
 *
 * @param r {Repo} the repository
 * @param rev {string} the revision; "" for the working tree's file
 * @param path {string} the file
 * @return {list of BlameLine} one per line
 * @throws {Error} kind `"git"` for an unknown file or revision
 */
export func blame(r as Repo, rev as string, path as string) {
    # blame reads `--end-of-options HEAD -- f` as revisions `HEAD` and `f`, so
    # it relies on checkRev's refusal of a leading `-` alone.
    def args as list of string init ["blame", "--porcelain", "--no-textconv"];
    if ($rev != "") {
        $args[] = checkRev($rev);
    }
    $args = lists.concat($args, lists.concat(["--"], checkPaths([$path])));
    return blameFrom(gitOut($r, $args, "blame " + $path));
}

/**
 * Parse `git blame --porcelain`: a header per line, the commit's details the
 * first time it appears, then the line after a tab.
 *
 * @param out {string} the output
 * @return {list of BlameLine} the lines
 */
func blameFrom(out as string) {
    def all as list of BlameLine init [];
    def seen as map of string to BlameLine init {};
    def cur as BlameLine;
    for (def l in strings.split($out, "\n")) {
        if (strings.startsWith($l, "\t")) {
            $cur.text = strings.substring($l, 1);
            if (maps.has($seen, $cur.hash)) {
                def known as BlameLine init $seen[$cur.hash];
                $cur.author = $known.author;
                $cur.authorEmail = $known.authorEmail;
                $cur.authorTime = $known.authorTime;
            } else {
                $seen[$cur.hash] = $cur;
            }
            $all[] = $cur;
            continue;
        }
        def sp as int init strings.indexOf($l, " ");
        if ($sp < 0) {
            continue;
        }
        def key as string init strings.substring($l, 0, $sp);
        def rest as string init strings.substring($l, $sp + 1);
        if ($key == "author") {
            $cur.author = $rest;
        } elseif ($key == "author-mail") {
            $cur.authorEmail = strings.replace(strings.replace($rest, "<", ""), ">", "");
        } elseif ($key == "author-time") {
            $cur.authorTime = toInt($rest);
        } elseif (len($key) >= 40 and regex.matches("^[0-9a-f]+$", $key)) {
            def nums as list of string init strings.split($rest, " ");
            $cur = BlameLine{
                line: toInt($nums[1]),
                hash: $key,
                author: "",
                authorEmail: "",
                authorTime: 0,
                text: ""
            };
        }
    }
    return $all;
}

/**
 * A readable name for a commit from the nearest tag, e.g. `v1.2-3-gabc1234`;
 * the abbreviated id when no tag is reachable.
 *
 * @param r {Repo} the repository
 * @param rev {string} the revision; "" for the checked-out commit
 * @return {string} the name
 * @throws {Error} kind `"git"` for an unknown revision
 */
export func describe(r as Repo, rev as string) {
    def args as list of string init ["describe", "--tags", "--always", "--end-of-options"];
    if ($rev != "") {
        $args[] = checkRev($rev);
    }
    return strings.trim(gitOut($r, $args, "describe"));
}

/**
 * The object name `rev:path` for a file at a revision.
 *
 * @param rev {string} the revision; "" for `HEAD`
 * @param path {string} the path from the top level
 * @return {string} the object name
 */
func blobName(rev as string, path as string) {
    def at as string init "HEAD";
    if ($rev != "") {
        $at = checkRev($rev);
    }
    checkPaths([$path]);
    return $at + ":" + $path;
}

/**
 * A text file's contents at a revision.
 *
 * @param r {Repo} the repository
 * @param rev {string} the revision; "" for `HEAD`
 * @param path {string} the path from the top level
 * @return {string} the contents
 * @throws {Error} kind `"git"` when the file is not there, or is over 16 MiB
 */
export func readFile(r as Repo, rev as string, path as string) {
    return gitOut($r, ["cat-file", "blob", blobName($rev, $path)], "read " + $path);
}

/**
 * A file's contents at a revision, as bytes: images, archives, any size. It
 * passes through a temporary file, removed afterwards.
 *
 * @param r {Repo} the repository
 * @param rev {string} the revision; "" for `HEAD`
 * @param path {string} the path from the top level
 * @return {bytes} the contents
 * @throws {Error} kind `"git"` when the file is not there
 */
export func readBytes(r as Repo, rev as string, path as string) {
    def name as string init blobName($rev, $path);
    def tmp as string init fs.makeTempFile(os.tempDir(), "jennifer-git-", ".blob");
    def data as bytes;
    try {
        def res as os.Result init execute(
            $r.config,
            commandLine($r.config, $r.dir, ["cat-file", "blob", $name]),
            "read " + $path,
            $tmp);
        checked($res, "read " + $path);
        $data = fs.readBytes($tmp);
    } catch (e) {
        fs.remove($tmp);
        throw $e;
    }
    fs.remove($tmp);
    return $data;
}

/**
 * The entries of a directory at a revision.
 *
 * @param r {Repo} the repository
 * @param rev {string} the revision; "" for `HEAD`
 * @param dir {string} the directory from the top level; "" for the top level
 * @param recursive {bool} true for every file below it (files only, no
 *   directory entries)
 * @return {list of TreeEntry} the entries
 * @throws {Error} kind `"git"` for an unknown revision
 */
export func listTree(r as Repo, rev as string, dir as string, recursive as bool) {
    def args as list of string init ["ls-tree", "-z", "--long", "--full-tree"];
    if ($recursive) {
        $args[] = "-r";
    }
    def at as string init "HEAD";
    if ($rev != "") {
        $at = checkRev($rev);
    }
    $args = lists.concat($args, [$at, "--"]);
    if ($dir != "") {
        def d as string init $dir;
        if (not strings.endsWith($d, "/")) {
            $d = $d + "/";
        }
        $args[] = $d;
    }
    def all as list of TreeEntry init [];
    for (def e in nulFields(gitOut($r, $args, "list " + $at))) {
        def tab as int init strings.indexOf($e, "\t");
        if ($tab < 0) {
            continue;
        }
        def meta as list of string init [];
        for (def m in strings.split(strings.substring($e, 0, $tab), " ")) {
            if ($m != "") {
                $meta[] = $m;
            }
        }
        $all[] = TreeEntry{
            path: strings.substring($e, $tab + 1),
            type: $meta[1],
            mode: $meta[0],
            hash: $meta[2],
            size: toInt($meta[3])
        };
    }
    return $all;
}

/**
 * Write the files of a revision to an archive, without the history. The
 * format comes from the extension: `.zip`, `.tar`, `.tar.gz` or `.tgz`.
 *
 * @param r {Repo} the repository
 * @param rev {string} the revision; "" for `HEAD`
 * @param file {string} the archive to write
 * @return {null} nothing
 * @throws {Error} kind `"git"` for another extension or an unknown revision
 */
export func archive(r as Repo, rev as string, file as string) {
    def lower as string init strings.lower($file);
    def format as string init "";
    if (strings.endsWith($lower, ".zip")) {
        $format = "zip";
    } elseif (strings.endsWith($lower, ".tar.gz") or strings.endsWith($lower, ".tgz")) {
        $format = "tar.gz";
    } elseif (strings.endsWith($lower, ".tar")) {
        $format = "tar";
    } else {
        fail("an archive is .zip, .tar, .tar.gz or .tgz: " + $file);
    }
    def at as string init "HEAD";
    if ($rev != "") {
        $at = checkRev($rev);
    }
    gitIn(
        $r,
        ["archive", "--format=" + $format, "--output=" + absolute($file), "--end-of-options", $at],
        "archive");
    return null;
}
