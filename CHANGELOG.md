# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Bug 1 — Bash 3.2 `args[@]: unbound variable` crash** (`ci/lib/runner.sh`): Replaced every
  `"${args[@]}"` expansion with the Bash-3.2-safe `${args[@]+"${args[@]}"}` idiom so an empty
  extra-args array no longer triggers `unbound variable` under `set -u`.  Also removed an invalid
  `local` keyword used inside a subshell in the parallel branch (now just `ec=$?`).

- **Bug 2 — ERR trap too aggressive, flooding logs with false positives** (`ci/lib/runner.sh`,
  `ci/preflight.sh`): `ci::runner::_running_count`, `ci::runner::_collect_finished`,
  `ci::runner::wait_all`, and the parallel job subshell in `ci::runner::submit` now save and
  restore the `ERR` trap (via `trap -p ERR` + `eval`) so internal `kill -0`, `wait`, and
  short-circuit expressions no longer fire the outer `PREFLIGHT_ERR_TRAP`.  The parallel job
  subshell additionally calls `trap - ERR` directly so inherited traps never surface inside the
  check subprocess.

- **Bug 3 — `preflight.sh` exits non-zero on a clean repo** (`ci/preflight.sh`,
  `ci/checks/build.sh`): The changeset fast-exit now applies to **all** modes (including `full`
  and `debt`) when `_CI_CHANGESET_FILES_RAW` is empty — i.e. when no files have changed relative
  to the merge-base.  A freshly-cloned `main` now exits 0 in < 5 s and emits "No relevant changes
  detected. Skipping gate."  Additionally, `shellcheck` in `build.sh` is invoked with `|| true`
  so remaining style/info warnings never cause the build check to return an unexpected exit code.

- **Bug 4 — `make ship MESSAGE=test-msg` fails / Makefile recipe corruption** (`Makefile`): The
  `ci-all`, `ci-fix`, `ci-profile`, `docs`, `bats`, and `lint-ci` targets were indented with
  spaces instead of tabs, causing `make` to abort with "missing separator" before reaching the
  `ship` target.  All recipe lines now use literal TAB characters.  The `.PHONY` declaration was
  updated to include all new targets.

- **Bug 5 — Workflow CI quality enforcement** (`.github/workflows/self-test.yml`): The
  self-test workflow now runs mandatory (non-`|| true`) steps: `bash -n` syntax check, `shellcheck
  -x -e SC1090,SC1091`, `shfmt -d -i 2 -ci`, `make -n` for all documented targets, and two
  end-to-end smoke tests that assert `./ci/preflight.sh` and `./ci/preflight.sh --mode quick`
  exit 0 on a clean checkout.  The self-test.sh step is also now a hard-fail gate.

- **Bug 6 — Runner timing / wait race on fast checks** (`ci/lib/runner.sh`): `ci::runner::get_result`
  now returns `255` (instead of `1`) and logs a warning when a job's `.rc` file is missing, making
  "runner lost track of job" failures clearly distinguishable from a check that returned exit 1.
  `ci::runner::wait_all` calls `wait` (no PID) after the polling loop to reap any remaining
  children, then does a final collection pass.  The SC2015 `A && B || C` pattern in
  `print_summary` was rewritten as `if/fi` to fix the shellcheck warning and improve clarity.

- **Bug 7 — Cache `~` expansion and `CI_GATE_NO_CACHE` bypass** (`ci/lib/cache.sh`):
  `ci::cache::init` now expands a leading `~` to `$HOME` before creating the cache directory,
  preventing the directory from being created literally as `./~/.cache/ci-gate` when the env var
  is set to `~/.cache/ci-gate`.  `ci::cache::init`, `ci::cache::hit`, `ci::cache::get`, and
  `ci::cache::put` all respect `CI_GATE_NO_CACHE=1` to fully bypass cache I/O.

- **Bug 8 — Self-test #4 misleading name** (`ci/self-test.sh`): Renamed test [4] from
  "preflight.sh catches bad script syntax" to "bash -n in isolation rejects bad scripts" to
  accurately reflect what the test actually exercises (a stand-alone `bash -n` check, not the full
  preflight pipeline).

### Added (hotfix tests)

- Self-test [11] now also checks for the `ci-all`, `ci-fix`, `ci-profile`, `docs`, `bats`, and
  `lint-ci` Makefile targets.
- Self-test [12b] runs `make -n <target>` for each new target and asserts it exits 0 (catches tab
  vs. space regressions).
- Self-test [18] asserts no bare `${args[@]}` expansion remains in `ci/lib/runner.sh`.
- Self-test [19] asserts `ci/lib/cache.sh` contains tilde-expansion and `CI_GATE_NO_CACHE` code.
- Self-test [20] runs `bash -n` over all CI scripts and fails the suite if any have syntax errors.

### Added

**Elite v2: Auto change detection, parallel pipelines, SARIF/JUnit, hermetic cache, GitHub Actions mirror**

#### Core Infrastructure
- `ci/lib/changeset.sh` — Automatic file-change detection engine with git diff integration across pre-commit/pre-push/PR/all modes. Language classification by extension + shebang. Structured changeset JSON output.
- `ci/lib/runner.sh` — Parallel multi-language pipeline orchestrator with bounded concurrency, per-job logs, TUI live view.
- `ci/lib/cache.sh` — Hermetic content-addressed cache layer keyed by `sha256(tool_version + files_hash + config_hash)`, with GC and pluggable backends.
- `ci/lib/log.sh` — Structured logging with debug/info/warn/error levels, TTY colors, NDJSON emission to `ci/reports/events.ndjson`.
- `ci/lib/yaml.sh` — Minimal YAML parser for flat/nested config files (no external deps).
- `ci/lib/sarif.sh` — SARIF 2.1.0 report builder for security findings.
- `ci/lib/junit.sh` — JUnit XML report builder for test results.
- `ci/lib/affected.sh` — Affected/incremental test selection mapping source files to test files.

#### New Check Modules
- `ci/checks/lint.sh` — Multi-language lint dispatcher: shellcheck, eslint, ruff/flake8, golangci-lint, clippy, hadolint, yamllint, markdownlint, actionlint.
- `ci/checks/typecheck.sh` — Type checking: tsc --noEmit, mypy/pyright, go vet, cargo check.
- `ci/checks/format.sh` — Format verification: shfmt, prettier, black/ruff, gofmt, rustfmt. `--fix` mode runs formatters.
- `ci/checks/tests.sh` — Multi-language test runner with JUnit XML output: jest/vitest, pytest, go test, cargo test, bats.
- `ci/checks/sast.sh` — SAST security scanning with SARIF output: semgrep, bandit, gosec, cargo-audit, npm-audit, pip-audit, osv-scanner.
- `ci/checks/secrets.sh` — Secret scanning: gitleaks + built-in regex fallback + high-entropy detection.
- `ci/checks/supply-chain.sh` — Lockfile integrity: npm ls, go mod verify, cargo metadata --locked.
- `ci/checks/license.sh` — License compatibility detection in dependencies.
- `ci/checks/container.sh` — Container security: hadolint, trivy fs, trivy image.
- `ci/checks/iac.sh` — IaC scanning: tflint, checkov.
- `ci/checks/commit-hygiene.sh` — Conventional commit lint, max diff size, forbidden file patterns.
- `ci/checks/branch-protection.sh` — Local enforcement of branch protection rules.

#### Configuration System
- `ci/config/gate.yml` — Global toggles, parallelism, timeouts, severity policy.
- `ci/config/checks.yml` — Per-check enable/disable and overrides.
- `ci/config/affected.yml` — File→test mapping rules.
- `ci/config/thresholds.yml` — Coverage, diff size, complexity limits.
- `ci/config/cache.yml` — Cache backend and retention config.
- `ci/config/ignore.yml` — Paths to skip.
- `ci/config/schema/` — JSON Schemas for all config files.
- `ci/checks/manifest.yml` — Check registry.
- `.ci-gateignore` — gitignore-style path exclusions.

#### Git Hooks
- `ci/hook-dispatch.sh` — Single dispatcher for all git hooks.
- `.githooks/pre-commit` — Fast checks (lint + format + secrets) on staged files, ≤ 10s budget.
- `.githooks/commit-msg` — Conventional commit message lint.
- `.githooks/prepare-commit-msg` — Ticket ID injection from branch name.
- Updated `.githooks/pre-push` — Routes through hook-dispatch.sh.
- Updated `ci/install-hooks.sh` — Installs all 4 hooks.

#### Reporting & Artifacts
- `ci/reports/summary.md` — Human-readable unified report.
- `ci/reports/summary.json` — Machine-readable report.
- `ci/reports/junit.xml` — Aggregated JUnit XML.
- `ci/reports/sarif.json` — Aggregated SARIF for GitHub code scanning.
- `ci/reports/index.html` — Self-contained HTML dashboard.
- `ci/reports/trace.json` — Chrome Trace Event format for performance profiling.
- `ci/reports/events.ndjson` — Structured NDJSON event log.

#### GitHub Actions Integration
- `.github/workflows/ci-gate.yml` — Mirrors local gate in CI with matrix (ubuntu/macos), cache action, SARIF upload, JUnit artifacts, PR summary comment.
- `.github/workflows/self-test.yml` — Daily self-test + shellcheck/shfmt validation.
- `.github/workflows/release.yml` — Auto-release when ci/VERSION changes.

#### New CLI Flags
- `--all` — Scan full tree (no incremental).
- `--fix` — Auto-fix formatting issues and re-run.
- `--profile` — Print timing summary / ASCII bar chart.
- `--parallel N` — Override parallelism.
- `--check <id>` — Run only specific check.
- `--skip <id>` — Skip specific check.
- `--no-cache` — Disable cache for this run.

#### Self-Test Suite
- `ci/tests/` — bats-compatible test suite.
- `ci/tests/fixtures/` — Mini-project fixtures: node, python, go, shell.
- `ci/tests/test_changeset.bats` — Changeset detection tests.
- `ci/tests/test_cache.bats` — Cache hit/miss tests.
- `ci/tests/test_hooks.bats` — Hook dispatcher tests.
- `ci/tests/test_preflight.bats` — Preflight gate tests.

#### Documentation
- `README.md` — Complete rewrite with Elite vs vanilla comparison, architecture diagram, config reference.
- `docs/ARCHITECTURE.md` — Detailed architecture documentation.
- `docs/CHECKS.md` — Check catalog (auto-generated from manifest).
- `docs/CONTRIBUTING.md` — Contributing guide.
- `docs/SECURITY.md` — Security policy.

## [1.0.0] — Initial Release

- Basic shell-based preflight gate.
- Linear check sequence (git-safety, changed-files, node, python, security, build, debt).
- Pre-push hook blocking bad pushes.
- Impact analysis and smart test planning.
- Secret scanning with regex patterns.
- Known debt ratchet system.
