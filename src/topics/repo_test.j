# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# git - white-box tests for the repo topic. Spliced into git_test.j via
# include.

func testStatusIsParsed() {
    def z as string init convert.fromCodepoint(0);
    def out as string init "# branch.oid 1111111111111111111111111111111111111111" + $z +
        "# branch.head main" + $z + "# branch.upstream origin/main" + $z + "# branch.ab +2 -3" +
        $z + "1 .M N... 100644 100644 100644 aaa bbb dir/with space.txt" + $z +
        "2 R. N... 100644 100644 100644 aaa bbb R100 new name.txt" + $z + "old name.txt" + $z +
        "u UU N... 100644 100644 100644 100644 a b c both.txt" + $z + "? new" + $z;
    def s as Status init statusFrom($out);
    testing.assertEqual($s.head, "1111111111111111111111111111111111111111");
    testing.assertEqual([$s.branch, $s.upstream], ["main", "origin/main"]);
    testing.assertEqual([$s.ahead, $s.behind], [2, 3]);
    testing.assertEqual(len($s.changes), 4);
    testing.assertEqual(
        $s.changes[0],
        Change{
            path: "dir/with space.txt",
            origPath: "",
            staged: ".",
            unstaged: "M",
            kind: "changed"
        });
    testing.assertEqual(
        $s.changes[1],
        Change{
            path: "new name.txt",
            origPath: "old name.txt",
            staged: "R",
            unstaged: ".",
            kind: "renamed"
        });
    testing.assertEqual([$s.changes[2].path, $s.changes[2].kind], ["both.txt", "conflict"]);
    testing.assertEqual([$s.changes[3].path, $s.changes[3].kind], ["new", "untracked"]);
    def fresh as Status init statusFrom("# branch.oid (initial)" + $z + "# branch.head (detached)" +
        $z);
    testing.assertEqual([$fresh.head, $fresh.branch], ["", ""]);
}

func testOpenOnlyTakesTheTopLevel() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    fs.mkdir($r.dir + "/sub");
    testing.assertEqual(isRepo(tcfg(), $r.dir), true);
    testing.assertEqual(isRepo(tcfg(), $r.dir + "/sub"), false);
    testing.assertEqual(isRepo(tcfg(), $dir), false);
    testing.assertEqual(isRepo(tcfg(), $dir + "/missing"), false);
    def bare as Repo init create(tcfg(), $dir + "/bare.git", true);
    testing.assertEqual(isRepo(tcfg(), $bare.dir), true);
    fs.removeAll($dir);
}

func testStageCommitAndStatus() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init create(tcfg(), $dir + "/work", false);
    testing.assertEqual(hasCommits($r), false);
    testing.assertEqual(log($r, "", "", 0), []);
    testing.assertEqual(isClean($r), true);
    put($r, "a b.txt", "one\n");
    put($r, "*.txt", "a file named star\n");
    testing.assertEqual(len(status($r).changes), 2);
    add($r, ["*.txt"]);
    def s as Status init status($r);
    def staged as list of string init [];
    for (def c in $s.changes) {
        if ($c.staged == "A") {
            $staged[] = $c.path;
        }
    }
    testing.assertEqual($staged, ["*.txt"]);
    addAll($r);
    def first as string init commit($r, "first\n\nwith a body");
    testing.assertEqual(len($first), 40);
    testing.assertEqual(isClean($r), true);
    testing.assertTrue(status($r).branch != "");
    put($r, "a b.txt", "changed\n");
    add($r, ["a b.txt"]);
    unstage($r, ["a b.txt"]);
    testing.assertEqual(status($r).changes[0].unstaged, "M");
    restore($r, ["a b.txt"]);
    testing.assertEqual(fs.readString($r.dir + "/a b.txt"), "one\n");
    remove($r, ["*.txt"]);
    def second as string init amend($r, "first, without the star");
    testing.assertTrue($second != $first);
    testing.assertEqual(show($r, "HEAD").subject, "first, without the star");
    testing.assertEqual(amend($r, "") != "", true);
    fs.removeAll($dir);
}

func testStash() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    testing.assertEqual(stash($r, ""), false);
    put($r, "a.txt", "edited\n");
    put($r, "new.txt", "new\n");
    testing.assertEqual(stash($r, "work in progress"), true);
    testing.assertEqual(isClean($r), true);
    stashPop($r);
    testing.assertEqual(fs.readString($r.dir + "/a.txt"), "edited\n");
    testing.assertEqual(fs.exists($r.dir + "/new.txt"), true);
    fs.removeAll($dir);
}

func testCloneRefusesHelpersAndUnlistedTransports() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    try {
        clone(tcfg(), "ext::sh -c touch% " + $dir + "/pwned", $dir + "/c1");
        missed("an ext:: URL was cloned");
    } catch (e) {
        testing.assertTrue(strings.contains($e.message, "remote helper"));
    }
    testing.assertEqual(fs.exists($dir + "/pwned"), false);
    try {
        clone(withProtocols(tcfg(), ["https"]), "file://" + $r.dir, $dir + "/c2");
        missed("a file:// clone passed an https-only configuration");
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    def c as Repo init cloneWith(tcfg(), $r.dir, $dir + "/c3", "", 1);
    testing.assertEqual(len(log($c, "", "", 0)), 1);
    fs.removeAll($dir);
}

func testOpenComparesTheTopLevel() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def outer as Repo init create(tcfg(), $dir + "/a:b", false);
    fs.mkdir($outer.dir + "/inner");
    try {
        open(tcfg(), $outer.dir + "/inner");
        missed("a subdirectory under a colon path was opened");
    } catch (e) {
        testing.assertTrue(strings.contains($e.message, "not the top level"));
    }
    try {
        clone(config(), $outer.dir, $dir + "/copy");
        missed("a local path was cloned with the default protocols");
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    try {
        lsRemote(config(), "https://alice:s3cr3t@127.0.0.1:1/x.git");
        missed("an unreachable remote answered");
    } catch (e) {
        testing.assertEqual(strings.contains($e.message, "s3cr3t"), false);
    }
    fs.removeAll($dir);
}
