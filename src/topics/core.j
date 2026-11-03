# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# git - the configuration, the hardened command line every call starts with,
# the checks on names, revisions and URLs, and running `git`. Spliced into
# git.j via include.

/** The `kind` of every error the deck throws. */
export def const ERROR_KIND as string init "git";

/**
 * How to run git. Build it with `config` and the `with*` functions; each
 * returns a changed copy.
 *
 * @field binary {string} the git program, `git` or a full path
 * @field timeoutMs {int} how long one command may run before it is killed
 * @field protocols {list of string} the transports remotes may use
 * @field hooks {bool} whether the repository's hooks run
 * @field name {string} the author and committer name; "" for git's own setting
 * @field email {string} the author and committer email; "" for git's own setting
 */
export def struct Config {
    binary as string,
    timeoutMs as int,
    protocols as list of string,
    hooks as bool,
    name as string,
    email as string
};

/**
 * An opened repository: its top-level directory (the git directory itself
 * for a bare one) and the configuration its commands run with.
 *
 * @field dir {string} the absolute path
 * @field config {Config} the configuration
 */
export def struct Repo {
    dir as string,
    config as Config
};

# The environment variables that point git at another repository or object
# store. Each beats `-C`, so every command starts with `env -u` for all of them:
# run from a git hook, which exports several, a command would otherwise act on
# the hook's repository.
def const RELOCATING as list of string init [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_IMPLICIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_NAMESPACE",
    "GIT_GRAFT_FILE",
    "GIT_SHALLOW_FILE",
    "GIT_REPLACE_REF_BASE",
    "GIT_PREFIX",
    "GIT_QUARANTINE_PATH",
    "GIT_CEILING_DIRECTORIES"
];

# The transports withProtocols accepts.
def const TRANSPORTS as list of string init ["https", "http", "ssh", "git", "file"];

# What the capture buffer appends past 16 MiB of output.
def const TRUNCATED as string init "\n[output truncated at 16 MiB]";

/**
 * Raise a deck error.
 *
 * @param message {string} what went wrong
 * @throws {Error} always, with `kind` `"git"`
 */
func fail(message as string) {
    throw Error{kind: ERROR_KIND, message: "git: " + $message};
}

/**
 * The default configuration: `git` from the `PATH`, two minutes per
 * command, remotes over `https` or `ssh` only, hooks off, git's own
 * identity. Local paths as remotes need `file` in `withProtocols`: a URL
 * from a user could otherwise clone any repository on the machine.
 *
 * @return {Config} the configuration
 */
export func config() {
    return Config{
        binary: "git",
        timeoutMs: 120000,
        protocols: ["https", "ssh"],
        hooks: false,
        name: "",
        email: ""
    };
}

/**
 * Use another git program, e.g. `/usr/local/bin/git`.
 *
 * @param c {Config} the configuration
 * @param binary {string} the program
 * @return {Config} the changed copy
 * @throws {Error} kind `"git"` when the name is empty or starts with `-`
 */
export func withBinary(c as Config, binary as string) {
    if (strings.trim($binary) == "" or strings.startsWith($binary, "-")) {
        fail("the binary is a program name or path, got \"" + $binary + "\"");
    }
    $c.binary = $binary;
    return $c;
}

/**
 * Set how long one command may run.
 *
 * @param c {Config} the configuration
 * @param ms {int} milliseconds, at least 1000
 * @return {Config} the changed copy
 * @throws {Error} kind `"git"` below one second
 */
export func withTimeout(c as Config, ms as int) {
    if ($ms < 1000) {
        fail("the timeout is at least 1000 ms");
    }
    $c.timeoutMs = $ms;
    return $c;
}

/**
 * Set the transports remotes may use. git refuses every other one, remote
 * helpers (`ext::`) included.
 *
 * @param c {Config} the configuration
 * @param protocols {list of string} some of `https`, `http`, `ssh`, `git`, `file`
 * @return {Config} the changed copy
 * @throws {Error} kind `"git"` for another name
 */
export func withProtocols(c as Config, protocols as list of string) {
    for (def p in $protocols) {
        if (not lists.contains(TRANSPORTS, $p)) {
            fail("a protocol is one of " + strings.join(TRANSPORTS, ", ") + "; got \"" + $p + "\"");
        }
    }
    $c.protocols = $protocols;
    return $c;
}

/**
 * Let the repository's hooks run (`pre-commit`, `post-checkout` ...). They
 * are off by default: a hook is a program, and a repository from elsewhere
 * should not run programs.
 *
 * @param c {Config} the configuration
 * @param on {bool} whether hooks run
 * @return {Config} the changed copy
 */
export func withHooks(c as Config, on as bool) {
    $c.hooks = $on;
    return $c;
}

/**
 * Commit as this person, whatever git's own configuration says; for
 * services and bots.
 *
 * @param c {Config} the configuration
 * @param name {string} the name
 * @param email {string} the email address
 * @return {Config} the changed copy
 * @throws {Error} kind `"git"` for an empty name, or `<`, `>` or a line break in either
 */
export func withIdentity(c as Config, name as string, email as string) {
    for (def v in [$name, $email]) {
        if (strings.trim($v) == "" or regex.matches("[<>\\x00-\\x1f]", $v)) {
            fail("an identity has a name and an email without <, > or line breaks");
        }
    }
    $c.name = $name;
    $c.email = $email;
    return $c;
}

/**
 * The full command line for git in a repository: the environment cleaned,
 * the locale fixed, prompts off, upward discovery stopped at the directory,
 * pathspecs literal, transports and config that run programs restricted.
 *
 * @param c {Config} the configuration
 * @param dir {string} the repository; "" for a command outside one
 * @param args {list of string} git's arguments
 * @return {list of string} the argument vector
 */
func commandLine(c as Config, dir as string, args as list of string) {
    def argv as list of string init ["env"];
    for (def name in RELOCATING) {
        $argv[] = "-u";
        $argv[] = $name;
    }
    $argv = lists.concat(
        $argv,
        ["-u", "LANGUAGE", "LC_ALL=C", "GIT_TERMINAL_PROMPT=0", "GIT_OPTIONAL_LOCKS=0"]);
    if ($dir != "") {
        $argv[] = "GIT_CEILING_DIRECTORIES=" + path.dir($dir);
    }
    $argv = lists.concat(
        $argv,
        [$c.binary, "--no-pager", "--literal-pathspecs", "--no-replace-objects"]);
    $argv = lists.concat($argv, ["-c", "protocol.allow=never"]);
    for (def p in $c.protocols) {
        $argv = lists.concat($argv, ["-c", "protocol." + $p + ".allow=always"]);
    }
    $argv = lists.concat($argv, ["-c", "core.fsmonitor=false"]);
    if (not $c.hooks) {
        $argv = lists.concat($argv, ["-c", "core.hooksPath=/dev/null"]);
    }
    if ($c.name != "") {
        $argv = lists.concat($argv, ["-c", "user.name=" + $c.name, "-c", "user.email=" + $c.email]);
    }
    if ($dir != "") {
        $argv = lists.concat($argv, ["-C", $dir]);
    }
    return lists.concat($argv, $args);
}

/**
 * Run git and wait for it, killing it after `timeoutMs`.
 *
 * @param c {Config} the configuration
 * @param argv {list of string} the command line
 * @param what {string} the operation, for error messages
 * @param stdoutFile {string} a file for the standard output; "" to capture it
 * @return {os.Result} the exit code and output
 * @throws {Error} kind `"git"` when git cannot start or runs too long
 */
func execute(c as Config, argv as list of string, what as string, stdoutFile as string) {
    def opts as map of string to string init {};
    if ($stdoutFile != "") {
        $opts["stdout"] = $stdoutFile;
    }
    def p as os.Process init start($c, $argv, $opts);
    def started as time.Time init time.now();
    def pause as int init 1;
    while (not os.poll($p)) {
        if (time.milliseconds(time.sub(time.now(), $started)) > $c.timeoutMs) {
            os.kill($p);
            os.wait($p);
            os.release($p);
            fail($what + ": killed after " + convert.toString($c.timeoutMs) + " ms");
        }
        time.sleep(time.fromMilliseconds($pause));
        if ($pause < 20) {
            $pause = $pause * 2;
        }
    }
    def r as os.Result init os.wait($p);
    os.release($p);
    return $r;
}

/**
 * Start git.
 *
 * @param c {Config} the configuration
 * @param argv {list of string} the command line
 * @param opts {map of string to string} `os.spawn`'s options
 * @return {os.Process} the running process
 * @throws {Error} kind `"git"` when it cannot start
 */
func start(c as Config, argv as list of string, opts as map of string to string) {
    try {
        return os.spawn($argv, $opts);
    } catch (e) {
        fail("cannot run " + $c.binary + " (is git installed?): " + $e.message);
    }
}

/**
 * Check a finished command.
 *
 * @param r {os.Result} the result
 * @param what {string} the operation, for the error message
 * @return {os.Result} the result, when the exit code is 0
 * @throws {Error} kind `"git"` with git's explanation otherwise, or when the
 *   output passed 16 MiB
 */
func checked(r as os.Result, what as string) {
    if ($r.exitCode != 0) {
        fail($what + ": " + firstError($r.stderr));
    }
    if (strings.endsWith($r.stdout, TRUNCATED)) {
        fail($what + ": the output passed 16 MiB; narrow the query");
    }
    return $r;
}

/**
 * The line of git's error output that explains a failure.
 *
 * @param stderr {string} the error output
 * @return {string} the first `fatal:` or `error:` line, else the first line
 */
func firstError(stderr as string) {
    def first as string init "";
    for (def line in strings.split($stderr, "\n")) {
        def t as string init strings.trim($line);
        if ($t == "") {
            continue;
        }
        if (strings.startsWith($t, "fatal:") or strings.startsWith($t, "error:")) {
            return $t;
        }
        if ($first == "") {
            $first = $t;
        }
    }
    if ($first == "") {
        return "failed without a message";
    }
    return $first;
}

/**
 * Run git in a repository.
 *
 * @param r {Repo} the repository
 * @param args {list of string} git's arguments
 * @param what {string} the operation, for error messages
 * @return {os.Result} the result
 * @throws {Error} kind `"git"` when git fails
 */
func gitIn(r as Repo, args as list of string, what as string) {
    return checked(execute($r.config, commandLine($r.config, $r.dir, $args), $what, ""), $what);
}

/**
 * Run git in a repository and return its output.
 *
 * @param r {Repo} the repository
 * @param args {list of string} git's arguments
 * @param what {string} the operation, for error messages
 * @return {string} the standard output
 * @throws {Error} kind `"git"` when git fails
 */
func gitOut(r as Repo, args as list of string, what as string) {
    return gitIn($r, $args, $what).stdout;
}

/**
 * Run git in a repository and return its exit code, for commands that
 * answer yes or no with it.
 *
 * @param r {Repo} the repository
 * @param args {list of string} git's arguments
 * @param what {string} the operation, for error messages
 * @return {os.Result} the result, whatever the exit code
 * @throws {Error} kind `"git"` when git cannot run
 */
func gitTry(r as Repo, args as list of string, what as string) {
    return execute($r.config, commandLine($r.config, $r.dir, $args), $what, "");
}

/**
 * Check a branch, tag or remote name as `git check-ref-format` would, and
 * refuse a leading `-`, which git would read as an option.
 *
 * @param name {string} the name
 * @param what {string} what it names, for the message
 * @return {string} the name
 * @throws {Error} kind `"git"` naming the problem
 */
func checkRef(name as string, what as string) {
    if ($name == "" or $name == "@") {
        fail("a " + $what + " name is needed");
    }
    if (strings.startsWith($name, "-")) {
        fail("a " + $what + " name may not start with -: " + $name);
    }
    def bad as bool init regex.matches("[\\x00-\\x20\\x7f~^:?*\\[\\\\]", $name) or
        strings.contains($name, "..") or strings.contains($name, "@\{") or
        strings.contains($name, "//") or strings.startsWith($name, "/") or
        strings.endsWith($name, "/") or strings.endsWith($name, ".") or
        regex.matches("(^|/)\\.", $name) or regex.matches("\\.lock(/|$)", $name);
    if ($bad) {
        fail("not a valid " + $what + " name: \"" + $name + "\"");
    }
    return $name;
}

/**
 * Check a revision (`main`, `HEAD~2`, `v1.0^`, `a1b2c3`, `main..topic`).
 *
 * @param rev {string} the revision
 * @return {string} the revision
 * @throws {Error} kind `"git"` for an empty one, a leading `-` or a control character
 */
func checkRev(rev as string) {
    if ($rev == "") {
        fail("a revision is needed");
    }
    if (strings.startsWith($rev, "-")) {
        fail("a revision may not start with -: " + $rev);
    }
    if (regex.matches("[\\x00-\\x1f\\x7f]", $rev)) {
        fail("a revision may not hold control characters");
    }
    return $rev;
}

/**
 * Check paths for a command that takes them after `--`.
 *
 * @param paths {list of string} the paths, relative to the repository
 * @return {list of string} the paths
 * @throws {Error} kind `"git"` for no paths or an empty one
 */
func checkPaths(paths as list of string) {
    if (len($paths) == 0) {
        fail("no paths given");
    }
    for (def p in $paths) {
        if ($p == "" or strings.contains($p, convert.fromCodepoint(0))) {
            fail("a path is empty or holds a NUL");
        }
    }
    return $paths;
}

/**
 * Check a remote URL before git sees it: a leading `-` (an option, such as
 * `--upload-pack=...`), surrounding whitespace, control characters, and the
 * `<transport>::<address>` form that runs a remote helper are refused. The
 * protocol allow-list in `commandLine` covers the rest.
 *
 * @param url {string} the URL or path
 * @return {string} the URL
 * @throws {Error} kind `"git"` naming the problem
 */
func checkUrl(url as string) {
    if (strings.trim($url) == "") {
        fail("a remote URL is needed");
    }
    if (strings.trim($url) != $url) {
        fail("a remote URL may not start or end with whitespace");
    }
    if (strings.startsWith($url, "-")) {
        fail("a remote URL may not start with -: " + redact($url));
    }
    if (regex.matches("[\\x00-\\x1f\\x7f]", $url)) {
        fail("a remote URL may not hold control characters");
    }
    if (regex.matches("^[A-Za-z0-9+.-]+::", $url)) {
        fail("a remote helper URL (transport::address) is refused: " + redact($url));
    }
    return $url;
}

/**
 * A URL fit for an error message: the user and password of
 * `https://user:token@host/...` replaced by `***`.
 *
 * @param url {string} the URL
 * @return {string} the URL without credentials
 */
func redact(url as string) {
    def scheme as int init strings.indexOf($url, "://");
    if ($scheme < 0) {
        return $url;
    }
    def rest as string init strings.substring($url, $scheme + 3);
    def at as int init strings.indexOf($rest, "@");
    def slash as int init strings.indexOf($rest, "/");
    if ($at < 0 or ($slash >= 0 and $slash < $at)) {
        return $url;
    }
    return strings.substring($url, 0, $scheme + 3) + "***" + strings.substring($rest, $at);
}

/**
 * Check a commit or tag message.
 *
 * @param message {string} the message
 * @return {string} the message
 * @throws {Error} kind `"git"` for a blank message or a NUL
 */
func checkMessage(message as string) {
    if (strings.trim($message) == "" or strings.contains($message, convert.fromCodepoint(0))) {
        fail("a message is needed, without NUL characters");
    }
    return $message;
}

/**
 * An absolute, cleaned path.
 *
 * @param dir {string} the path
 * @return {string} the absolute path; symbolic links resolved when it exists
 */
func absolute(dir as string) {
    if ($dir == "") {
        fail("a directory is needed");
    }
    if (fs.exists($dir)) {
        return fs.realpath($dir);
    }
    if (path.isAbs($dir)) {
        return path.clean($dir);
    }
    return path.join(os.cwd(), $dir);
}

/**
 * Split NUL-separated output, dropping the empty piece after the last NUL.
 *
 * @param out {string} the output
 * @return {list of string} the pieces
 */
func nulFields(out as string) {
    if ($out == "") {
        return [];
    }
    def parts as list of string init strings.split($out, convert.fromCodepoint(0));
    if ($parts[len($parts) - 1] == "") {
        return lists.slice($parts, 0, len($parts) - 1);
    }
    return $parts;
}

/**
 * Split output into lines, dropping empty ones.
 *
 * @param out {string} the output
 * @return {list of string} the lines
 */
func lines(out as string) {
    def all as list of string init [];
    for (def l in strings.split($out, "\n")) {
        if ($l != "") {
            $all[] = $l;
        }
    }
    return $all;
}

/**
 * Read an integer git printed.
 *
 * @param s {string} the text
 * @return {int} the integer; 0 when it is none
 */
func toInt(s as string) {
    try {
        return convert.toInt(strings.trim($s));
    } catch (e) {
        return 0;
    }
}

/**
 * The git version line, e.g. `git version 2.56.0`.
 *
 * @param c {Config} the configuration
 * @return {string} the version
 * @throws {Error} kind `"git"` when git cannot run
 */
export func version(c as Config) {
    def r as os.Result init checked(
        execute($c, commandLine($c, "", ["--version"]), "version", ""),
        "version");
    return strings.trim($r.stdout);
}

/**
 * Whether git can run with this configuration.
 *
 * @param c {Config} the configuration
 * @return {bool} true when `version` works
 */
export func available(c as Config) {
    try {
        return strings.startsWith(version($c), "git version");
    } catch (e) {
        return false;
    }
}

/**
 * Run git in a repository with arguments of your own, after the hardened
 * prefix. The arguments are **not checked**: never put untrusted input in
 * them; use the typed functions instead.
 *
 * @param r {Repo} the repository
 * @param args {list of string} the arguments
 * @return {string} what git printed
 * @throws {Error} kind `"git"` when it fails
 */
export func run(r as Repo, args as list of string) {
    return gitOut($r, $args, "run");
}
