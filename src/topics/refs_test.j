# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# git - white-box tests for the refs topic. Spliced into git_test.j via
# include.

func forcedRefspec() {
    checkRefspec("+main");
}

func optionRefspec() {
    checkRefspec("--mirror");
}

func emptyRefspec() {
    checkRefspec("");
}

func testRefspecsAreChecked() {
    testing.assertEqual(checkRefspec("main"), "main");
    testing.assertEqual(checkRefspec("main:release"), "main:release");
    testing.assertEqual(checkRefspec(":old"), ":old");
    testing.assertEqual(checkRefspec("refs/tags/v1.0"), "refs/tags/v1.0");
    testing.assertThrows("forcedRefspec", ERROR_KIND);
    testing.assertThrows("optionRefspec", ERROR_KIND);
    testing.assertThrows("emptyRefspec", ERROR_KIND);
}

func testBranchesAreParsed() {
    def z as string init convert.fromCodepoint(0);
    def out as string init "main" + $z + "aaa" + $z + "origin/main" + $z + "*" + $z +
        "ahead 2, behind 1" + $z + "\n" +
        "old" + $z + "bbb" + $z + "origin/old" + $z + " " + $z + "gone" + $z + "\n" +
        "origin" + $z + "ccc" + $z + "" + $z + " " + $z + "" + $z + "refs/remotes/origin/main\n";
    def all as list of Branch init branchesFrom($out);
    testing.assertEqual(len($all), 2);
    testing.assertEqual(
        $all[0],
        Branch{
            name: "main",
            hash: "aaa",
            upstream: "origin/main",
            current: true,
            ahead: 2,
            behind: 1,
            gone: false
        });
    testing.assertEqual([$all[1].current, $all[1].gone], [false, true]);
}

func badMergeMode() {
    merge(Repo{dir: "/nonexistent", config: config()}, "main", "octopus");
}

func testBranchesTagsAndMerges() {
    testing.assertThrows("badMergeMode", ERROR_KIND);
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    def main as string init currentBranch($r);
    def base as string init revParse($r, "HEAD");
    createBranch($r, "feature/x", "");
    switchTo($r, "feature/x");
    put($r, "b.txt", "feature\n");
    addAll($r);
    def tip as string init commit($r, "feature work");
    testing.assertEqual(currentBranch($r), "feature/x");
    switchTo($r, $main);
    def names as list of string init [];
    for (def b in branches($r)) {
        $names[] = $b.name;
    }
    testing.assertEqual(lists.sort($names), lists.sort(["feature/x", $main]));
    testing.assertEqual(isAncestor($r, $base, "feature/x"), true);
    testing.assertEqual(isAncestor($r, "feature/x", $base), false);
    testing.assertEqual(mergeBase($r, $main, "feature/x"), $base);
    def m as Merge init merge($r, "feature/x", "ff-only");
    testing.assertEqual($m.merged, true);
    testing.assertEqual(revParse($r, "HEAD"), $tip);
    deleteBranch($r, "feature/x", false);
    createTag($r, "v1.0", "", "first release");
    createTag($r, "light", $base, "");
    def t as list of Tag init tags($r);
    testing.assertEqual([$t[0].name, convert.toString($t[0].annotated)], ["light", "false"]);
    testing.assertEqual([$t[0].hash, $t[0].message], [$base, "first"]);
    testing.assertEqual([$t[1].name, $t[1].hash, $t[1].message], ["v1.0", $tip, "first release"]);
    deleteTag($r, "light");
    testing.assertEqual(len(tags($r)), 1);
    detach($r, "v1.0");
    testing.assertEqual(currentBranch($r), "");
    switchTo($r, $main);
    try {
        revParse($r, "nope");
        missed("an unknown revision resolved");
    } catch (e) {
        testing.assertTrue(strings.contains($e.message, "no such commit"));
    }
    fs.removeAll($dir);
}

func testConflictsAreReported() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    def main as string init currentBranch($r);
    createBranch($r, "other", "");
    put($r, "a.txt", "main side\n");
    addAll($r);
    commit($r, "main side");
    switchTo($r, "other");
    put($r, "a.txt", "other side\n");
    addAll($r);
    commit($r, "other side");
    switchTo($r, $main);
    def m as Merge init merge($r, "other", "no-ff");
    testing.assertEqual($m, Merge{merged: false, conflicts: ["a.txt"]});
    abortMerge($r);
    testing.assertEqual(isClean($r), true);
    try {
        merge($r, "other", "ff-only");
        missed("a diverged ff-only merge passed");
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    fs.removeAll($dir);
}

func testRemotes() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    def main as string init currentBranch($r);
    def hub as Repo init create(tcfg(), $dir + "/hub.git", true);
    addRemote($r, "origin", $hub.dir);
    push($r, "origin", $main, false);
    setUpstream($r, $main, "origin/" + $main);
    createTag($r, "v1", "", "");
    pushTags($r, "origin");
    def refs as list of Ref init lsRemote(tcfg(), $hub.dir);
    def names as list of string init [];
    for (def ref in $refs) {
        $names[] = $ref.name;
    }
    testing.assertTrue(lists.contains($names, "refs/heads/" + $main));
    testing.assertTrue(lists.contains($names, "refs/tags/v1"));
    def other as Repo init clone(tcfg(), $hub.dir, $dir + "/other");
    put($other, "b.txt", "from the clone\n");
    addAll($other);
    def tip as string init commit($other, "from the clone");
    push($other, "origin", $main, false);
    fetch($r, "origin");
    testing.assertEqual(status($r).behind, 1);
    def rb as list of Branch init remoteBranches($r);
    testing.assertEqual([$rb[0].name, $rb[0].hash], ["origin/" + $main, $tip]);
    testing.assertEqual(branches($r)[0].behind, 1);
    pull($r, "", "");
    testing.assertEqual(revParse($r, "HEAD"), $tip);
    pull($r, "origin", $main);
    fetch($r, "");
    amend($other, "rewritten");
    try {
        push($other, "origin", $main, false);
        missed("a rewritten history was pushed without force");
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
    push($other, "origin", $main, true);
    push($other, "origin", "HEAD:refs/heads/copy", false);
    push($other, "origin", ":copy", false);
    setRemoteUrl($r, "origin", $dir + "/elsewhere.git");
    def rem as list of Remote init remotes($r);
    testing.assertEqual(
        $rem,
        [Remote{name: "origin", url: $dir + "/elsewhere.git", pushUrl: $dir + "/elsewhere.git"}]);
    removeRemote($r, "origin");
    testing.assertEqual(remotes($r), []);
    fs.removeAll($dir);
}

func branchWithoutRemote() {
    pull(Repo{dir: "/nonexistent", config: config()}, "", "main");
}

func testPullNeedsARemoteForABranch() {
    testing.assertThrows("branchWithoutRemote", ERROR_KIND);
}
