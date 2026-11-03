# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# git - white-box tests for the core topic, and the helpers the live tests
# share. Spliced into git_test.j via include.

/**
 * Keep the user's own git configuration out of the tests: a global
 * `commit.gpgSign` or `init.defaultBranch` would change what they see.
 *
 * @return {bool} true
 */
func isolate() {
    os.setEnv("GIT_CONFIG_GLOBAL", "/dev/null");
    os.setEnv("GIT_CONFIG_NOSYSTEM", "1");
    return true;
}

def isolated as bool init isolate();

# Whether git runs here; the live tests return early without it.
def hasGit as bool init available(config());

/**
 * Mark a call that should have thrown. The error reaches the test's own
 * `catch`, whose assertions on kind and message then fail.
 *
 * @param what {string} what got through
 * @throws {Error} always, with `kind` `"missed"`
 */
func missed(what as string) {
    throw Error{kind: "missed", message: $what};
}

/**
 * The configuration the live tests use: a fixed identity.
 *
 * @return {Config} the configuration
 */
func tcfg() {
    return withProtocols(
        withIdentity(config(), "Test Bot", "bot@example.com"),
        ["https", "ssh", "file"]);
}

/**
 * A fresh directory for a live test.
 *
 * @return {string} the directory
 */
func scratch() {
    return fs.makeTempDir(os.tempDir(), "git-test-");
}

/**
 * Write a file in a repository's working tree.
 *
 * @param r {Repo} the repository
 * @param name {string} the path
 * @param text {string} the contents
 */
func put(r as Repo, name as string, text as string) {
    fs.writeString($r.dir + "/" + $name, $text);
}

/**
 * A new repository in a scratch directory, with one commit of `a.txt`.
 *
 * @param dir {string} the scratch directory
 * @return {Repo} the repository
 */
func seeded(dir as string) {
    def r as Repo init create(tcfg(), $dir + "/work", false);
    put($r, "a.txt", "one\n");
    add($r, ["a.txt"]);
    commit($r, "first");
    return $r;
}

/**
 * The message a check fails with.
 *
 * @param name {string} the ref name
 * @return {string} the message; "" when it passes
 */
func refRefusal(name as string) {
    try {
        checkRef($name, "branch");
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
        return $e.message;
    }
    return "";
}

/**
 * The message a URL check fails with.
 *
 * @param url {string} the URL
 * @return {string} the message; "" when it passes
 */
func urlRefusal(url as string) {
    try {
        checkUrl($url);
    } catch (e) {
        return $e.message;
    }
    return "";
}

func testRefNamesAreChecked() {
    for (def good in ["main", "feature/login", "v1.2.0", "release-2026.11", "HEAD", "user@host"]) {
        testing.assertEqual(refRefusal($good), "");
    }
    for (def bad in [
        "",
        "@",
        "-f",
        "--upload-pack=x",
        "a b",
        "a..b",
        "a~1",
        "a^",
        "a:b",
        "a?",
        "a*",
        "a[1]",
        "a\\b",
        "a@\{1\}",
        "/a",
        "a/",
        "a//b",
        "a.",
        ".hidden",
        "x/.hidden",
        "a.lock",
        "a.lock/b",
        "a\nb"
    ]) {
        testing.assertTrue(refRefusal($bad) != "");
    }
}

func badRev() {
    checkRev("--output=/tmp/x");
}

func emptyPaths() {
    checkPaths([]);
}

func blankMessage() {
    checkMessage("  \n");
}

func testRevisionsPathsAndMessages() {
    testing.assertEqual(checkRev("HEAD~2"), "HEAD~2");
    testing.assertEqual(checkRev("v1.0..main"), "v1.0..main");
    testing.assertEqual(checkRev("main@\{yesterday\}"), "main@\{yesterday\}");
    testing.assertThrows("badRev", ERROR_KIND);
    testing.assertThrows("emptyPaths", ERROR_KIND);
    testing.assertThrows("blankMessage", ERROR_KIND);
    testing.assertEqual(checkPaths(["-rf", "a b.txt"]), ["-rf", "a b.txt"]);
}

func testUrlsAreChecked() {
    for (def good in [
        "https://github.com/deckyard/deck-git.git",
        "git@github.com:deckyard/deck-git.git",
        "ssh://git@host:2222/x.git",
        "/srv/git/x.git",
        "../x"
    ]) {
        testing.assertEqual(urlRefusal($good), "");
    }
    testing.assertTrue(strings.contains(
        urlRefusal("--upload-pack=touch /tmp/x"),
        "may not start with -"));
    testing.assertTrue(strings.contains(
        urlRefusal("ext::sh -c touch% /tmp/pwned"),
        "remote helper"));
    testing.assertTrue(strings.contains(urlRefusal("fd::17"), "remote helper"));
    testing.assertTrue(strings.contains(urlRefusal(" https://x"), "whitespace"));
    testing.assertTrue(strings.contains(urlRefusal("https://x\n--y"), "control"));
    testing.assertTrue(strings.contains(urlRefusal(""), "needed"));
    testing.assertEqual(redact("https://alice:t0ken@host/x.git"), "https://***@host/x.git");
    testing.assertEqual(redact("https://host/a@b"), "https://host/a@b");
    testing.assertEqual(redact("git@host:x.git"), "git@host:x.git");
    testing.assertEqual(redact("ext::https://u:p@h/x"), "ext::https://***@h/x");
}

func badProtocol() {
    withProtocols(config(), ["https", "ext"]);
}

func shortTimeout() {
    withTimeout(config(), 10);
}

func optionAsBinary() {
    withBinary(config(), "--exec-path=/tmp");
}

func badIdentity() {
    withIdentity(config(), "Eve <eve@x>", "eve@x");
}

func testConfiguration() {
    def c as Config init config();
    testing.assertEqual([$c.binary, convert.toString($c.timeoutMs)], ["git", "120000"]);
    testing.assertEqual($c.protocols, ["https", "ssh"]);
    testing.assertEqual($c.hooks, false);
    testing.assertEqual(withBinary($c, "/usr/bin/git").binary, "/usr/bin/git");
    testing.assertEqual(withTimeout($c, 5000).timeoutMs, 5000);
    testing.assertEqual(withProtocols($c, ["https"]).protocols, ["https"]);
    testing.assertEqual(withHooks($c, true).hooks, true);
    def me as Config init withIdentity($c, "Ada", "ada@example.com");
    testing.assertEqual([$me.name, $me.email], ["Ada", "ada@example.com"]);
    testing.assertThrows("badProtocol", ERROR_KIND);
    testing.assertThrows("shortTimeout", ERROR_KIND);
    testing.assertThrows("optionAsBinary", ERROR_KIND);
    testing.assertThrows("badIdentity", ERROR_KIND);
}

func testTheCommandLineIsHardened() {
    def argv as list of string init commandLine(config(), "/srv/repo", ["status"]);
    testing.assertEqual($argv[0], "env");
    for (def name in [
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_OBJECT_DIRECTORY",
        "LANGUAGE"
    ]) {
        testing.assertTrue(lists.contains($argv, $name));
    }
    for (def setting in [
        "LC_ALL=C",
        "GIT_TERMINAL_PROMPT=0",
        "GIT_CEILING_DIRECTORIES=/srv",
        "--no-pager",
        "--literal-pathspecs",
        "--no-replace-objects",
        "protocol.allow=never",
        "protocol.https.allow=always",
        "core.fsmonitor=false",
        "core.hooksPath=/dev/null"
    ]) {
        testing.assertTrue(lists.contains($argv, $setting));
    }
    testing.assertEqual(lists.contains($argv, "protocol.http.allow=always"), false);
    testing.assertEqual(lists.slice($argv, len($argv) - 3), ["-C", "/srv/repo", "status"]);
    def hooked as list of string init commandLine(withHooks(tcfg(), true), "", ["--version"]);
    testing.assertEqual(lists.contains($hooked, "core.hooksPath=/dev/null"), false);
    testing.assertTrue(lists.contains($hooked, "user.name=Test Bot"));
    testing.assertEqual(lists.contains($hooked, "-C"), false);
}

func testErrorsAndOutput() {
    def err as string init "hint: something\nfatal: not a git repository\nmore\n";
    testing.assertEqual(firstError($err), "fatal: not a git repository");
    testing.assertEqual(firstError("warning: x\n"), "warning: x");
    testing.assertEqual(firstError(""), "failed without a message");
    try {
        checked(os.Result{exitCode: 0, stdout: "x" + TRUNCATED, stderr: ""}, "log");
        missed("truncated output passed");
    } catch (e) {
        testing.assertTrue(strings.contains($e.message, "passed 16 MiB"));
    }
    def z as string init convert.fromCodepoint(0);
    testing.assertEqual(nulFields("a" + $z + "b c" + $z), ["a", "b c"]);
    testing.assertEqual(nulFields(""), []);
    testing.assertEqual(lines("a\n\nb\n"), ["a", "b"]);
    testing.assertEqual(toInt(" 42 "), 42);
    testing.assertEqual(toInt("-"), 0);
}

func testAMissingBinaryIsADeckError() {
    def c as Config init withBinary(config(), "/nonexistent/git");
    testing.assertEqual(available($c), false);
    try {
        version($c);
        missed("a missing binary ran");
    } catch (e) {
        testing.assertEqual($e.kind, ERROR_KIND);
    }
}

func testVersionAndRun() {
    if (not $hasGit) {
        return;
    }
    testing.assertTrue(strings.startsWith(version(config()), "git version"));
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    testing.assertEqual(strings.trim(run($r, ["rev-list", "--count", "HEAD"])), "1");
    fs.removeAll($dir);
}

func testEnvironmentCannotRedirectCommands() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    def other as Repo init create(tcfg(), $dir + "/other", false);
    os.setEnv("GIT_DIR", $other.dir + "/.git");
    def n as int init len(log($r, "", "", 0));
    os.setEnv("GIT_DIR", "");
    testing.assertEqual($n, 1);
    testing.assertEqual(hasCommits($other), false);
    fs.removeAll($dir);
}

func testHooksAreOffUnlessAllowed() {
    if (not $hasGit) {
        return;
    }
    def dir as string init scratch();
    def r as Repo init seeded($dir);
    def hook as string init $r.dir + "/.git/hooks/pre-commit";
    fs.writeString($hook, "#!/bin/sh\ntouch hook-ran\n");
    fs.chmod($hook, 493);
    put($r, "b.txt", "two\n");
    add($r, ["b.txt"]);
    commit($r, "second");
    testing.assertEqual(fs.exists($r.dir + "/hook-ran"), false);
    def hooked as Repo init open(withHooks(tcfg(), true), $r.dir);
    put($hooked, "c.txt", "three\n");
    add($hooked, ["c.txt"]);
    commit($hooked, "third");
    testing.assertEqual(fs.exists($r.dir + "/hook-ran"), true);
    fs.removeAll($dir);
}
