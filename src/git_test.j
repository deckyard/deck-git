# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box tests: jennifer test src/git_test.j
 *
 * The checks, the command line and the parsers are tested everywhere. The
 * tests that run git work in throwaway repositories under the temp
 * directory, with no network, and return early where git is not installed
 * (CI's container, jvc's publish gate); `testVersionAndRun` says so.
 */
use testing;

include "topics/core_test.j";
include "topics/repo_test.j";
include "topics/history_test.j";
include "topics/refs_test.j";
