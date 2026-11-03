# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# git - white-box tests for the history topic. Spliced into git_test.j via
# include.

func testCommitsAndBlameAreParsed() {
    def z as string init convert.fromCodepoint(0);
    def one as string init "aaa" + $z + "p1 p2" + $z + "Ada" + $z + "ada@x" + $z + "100" + $z +
        "Bob" +
        $z + "bob@x" + $z + "200" + $z + "subject" + $z + "body\nmore\n";
    def two as string init "bbb" + $z + "" + $z + "Ada" + $z + "ada@x" + $z + "50" + $z + "Ada" +
        $z +
        "ada@x" + $z + "50" + $z + "root" + $z + "";
    def all as list of Commit init commitsFrom($one + $z + $two + $z);
    testing.assertEqual(len($all), 2);
    testing.assertEqual($all[0].parents, ["p1", "p2"]);
    testing.assertEqual([$all[0].committer, $all[0].body], ["Bob", "body\nmore"]);
    testing.assertEqual([$all[0].authorTime, $all[0].committerTime], [100, 200]);
    testing.assertEqual([$all[1].hash, $all[1].subject], ["bbb", "root"]);
    testing.assertEqual($all[1].parents, []);
    def h as string init "0123456789012345678901234567890123456789";
    def out as string init $h +
        " 1 1 2\nauthor Ada\nauthor-mail <ada@x>\nauthor-time 100\nsummary s\nfilename f\n\tline one\n" +
        $h + " 2 2\n\tline two\n";
    def lines as list of BlameLine init blameFrom($out);
    testing.assertEqual(len($lines), 2);
    testing.assertEqual(
        $lines[1],
        BlameLine{
            line: 2,
            hash: $h,
            author: "Ada",
            authorEmail: "ada@x",
            authorTime: 100,
            text: "line two"
        });
}

func diffToNowhere() {
    diffRange("", "main");
}

func testDiffRanges() {
    testing.assertEqual(diffRange("", ""), ["--end-of-options", "--"]);
    testing.assertEqual(diffRange("HEAD", ""), ["--end-of-options", "HEAD", "--"]);
    testing.assertEqual(diffRange("v1", "v2"), ["--end-of-options", "v1", "v2", "--"]);
    testing.assertThrows("diffToNowhere", ERROR_KIND);
    testing.assertEqual(blobName("", "a/b.txt"), "HEAD:a/b.txt");
    testing.assertEqual(blobName("v1", "x"), "v1:x");
}

func testHistory() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    def first as string init revParse($r, "HEAD");
    put($r, "a.txt", "one\ntwo\n");
    put($r, "img.bin", strings.repeat(convert.fromCodepoint(0), 3));
    addAll($r);
    commit($r, "second\n\nadds a line");
    def all as list of Commit init log($r, "", "", 0);
    testing.assertEqual(len($all), 2);
    testing.assertEqual([$all[0].subject, $all[0].body], ["second", "adds a line"]);
    testing.assertEqual($all[0].parents, [$first]);
    testing.assertEqual([$all[0].author, $all[0].authorEmail], ["Test Bot", "bot@example.com"]);
    testing.assertEqual(len(log($r, "HEAD", "a.txt", 1)), 1);
    testing.assertEqual(len(log($r, $first + "..HEAD", "", 0)), 1);
    testing.assertEqual(show($r, $first).subject, "first");
    def stats as list of FileStat init diffStat($r, $first, "HEAD");
    testing.assertEqual(len($stats), 2);
    testing.assertEqual([$stats[0].path, convert.toString($stats[0].added)], ["a.txt", "1"]);
    testing.assertEqual($stats[1].binary, true);
    def ch as list of FileChange init changes($r, $first, "HEAD");
    testing.assertEqual([$ch[0].status, $ch[1].status], ["M", "A"]);
    testing.assertTrue(strings.contains(diff($r, $first, "HEAD"), "+two"));
    put($r, "a.txt", "one\ntwo\nthree\n");
    testing.assertTrue(strings.contains(diff($r, "", ""), "+three"));
    testing.assertEqual(stagedDiff($r), "");
    add($r, ["a.txt"]);
    testing.assertTrue(strings.contains(stagedDiff($r), "+three"));
    def b as list of BlameLine init blame($r, "HEAD", "a.txt");
    testing.assertEqual([$b[0].hash, $b[1].text], [$first, "two"]);
    testing.assertEqual($b[1].author, "Test Bot");
    testing.assertEqual(readFile($r, $first, "a.txt"), "one\n");
    def raw as bytes init readBytes($r, "", "img.bin");
    testing.assertEqual(len($raw), 3);
    def tree as list of TreeEntry init listTree($r, "", "", false);
    testing.assertEqual([$tree[0].path, $tree[0].type, $tree[0].mode], ["a.txt", "blob", "100644"]);
    testing.assertEqual($tree[1].size, 3);
    createTag($r, "v1.0", $first, "");
    testing.assertEqual(
        describe($r, ""),
        "v1.0-1-g" + strings.substring(revParse($r, "HEAD"), 0, 7));
    archive($r, "v1.0", $dir + "/v1.zip");
    testing.assertTrue(fs.stat($dir + "/v1.zip").size > 0);
    fs.removeAll($dir);
}

func testRenamesAndOddNames() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    fs.mkdir($r.dir + "/sub dir");
    put($r, "sub dir/line\nbreak.txt", "x\n");
    addAll($r);
    commit($r, "odd name");
    gitIn($r, ["mv", "a.txt", "renamed.txt"], "mv");
    commit($r, "rename");
    def ch as list of FileChange init changes($r, "HEAD~1", "HEAD");
    testing.assertEqual($ch, [FileChange{status: "R", path: "renamed.txt", oldPath: "a.txt"}]);
    def st as list of FileStat init diffStat($r, "HEAD~1", "HEAD");
    testing.assertEqual([$st[0].path, $st[0].oldPath], ["renamed.txt", "a.txt"]);
    def files as list of TreeEntry init listTree($r, "", "sub dir", true);
    testing.assertEqual($files[0].path, "sub dir/line\nbreak.txt");
    testing.assertEqual(readFile($r, "", "sub dir/line\nbreak.txt"), "x\n");
    fs.removeAll($dir);
}

func testBlameRunsNoTextConversion() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    put($r, ".gitattributes", "a.txt diff=leak\n");
    addAll($r);
    commit($r, "attributes");
    run($r, ["config", "diff.leak.textconv", "touch " + $dir + "/textconv-ran; cat"]);
    testing.assertEqual(len(blame($r, "", "a.txt")), 1);
    testing.assertEqual(fs.exists($dir + "/textconv-ran"), false);
    diff($r, "HEAD~1", "HEAD");
    testing.assertEqual(fs.exists($dir + "/textconv-ran"), false);
    fs.removeAll($dir);
}
