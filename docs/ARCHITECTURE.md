# Architecture

## Overview

The CI Gate is a local-first, shell-based CI pipeline that runs on developer workstations before code reaches a remote. It is composed of modular library files, discrete check scripts, a configuration system, git hooks, and a reporting pipeline.

```
ci/
├── preflight.sh          # Main entry point / orchestrator
├── hook-dispatch.sh      # Single dispatcher for all git hooks
├── install-hooks.sh      # Installs git hooks into .githooks/
├── ship.sh               # Safe commit+push wrapper
├── self-test.sh          # CI self-validation suite
├── lib/                  # Shared libraries
├── checks/               # Individual check modules
├── config/               # Configuration files (YAML)
├── scripts/              # Utility / generator scripts
├── tests/                # bats test suite + fixtures
├── reports/              # Generated reports (gitignored output)
└── artifacts/            # Generated artifacts (changeset JSON, etc.)
```

## Library Files (`ci/lib/`)

| File | Responsibility |
|------|----------------|
| `common.sh` | Exit codes, result merging, mode parsing, utility functions |
| `log.sh` | Structured logging: debug/info/warn/error, TTY colours, NDJSON emission |
| `changeset.sh` | Git diff integration, file classification by extension/shebang, structured changeset JSON |
| `runner.sh` | Parallel multi-language pipeline orchestrator, bounded concurrency, per-job logs |
| `cache.sh` | Hermetic content-addressed cache keyed by `sha256(tool_version + files_hash + config_hash)` |
| `affected.sh` | Source-to-test mapping for incremental test selection |
| `sarif.sh` | SARIF 2.1.0 report builder for security findings |
| `junit.sh` | JUnit XML report builder for test results |
| `yaml.sh` | Minimal YAML parser for flat/nested config (no external dependencies) |
| `report.sh` | Unified report aggregator (summary.md, summary.json, index.html) |
| `git.sh` | Git utility functions (branch, remote, status helpers) |
| `impact.sh` | Impact analysis: maps changed files to affected check lanes |
| `test-plan.sh` | Advisory test plan generator based on changeset |

## Check Lifecycle

Every check goes through four phases:

```
detect()  →  plan()  →  run()  →  report()
```

1. **detect** — Determine whether this check is applicable (e.g., are there Python files?).
2. **plan** — Compute which files/directories to operate on; look up the cache key.
3. **run** — Execute the check tool(s); capture exit code, stdout, stderr.
4. **report** — Emit structured output: SARIF (security), JUnit (tests), or plain log.

## Caching System

Cache keys are computed as:

```
sha256( tool_name + tool_version + sorted_file_hashes + config_hash )
```

A cache hit skips the `run()` phase entirely and replays the previous result. The cache is stored under `~/.cache/ci-gate/` by default (configurable via `ci/config/cache.yml`). Garbage collection removes entries older than the configured TTL.

## Reporting Pipeline

After all checks complete, the report aggregator produces:

| File | Format | Purpose |
|------|--------|---------|
| `ci/reports/summary.md` | Markdown | Human-readable terminal summary |
| `ci/reports/summary.json` | JSON | Machine-readable result |
| `ci/reports/junit.xml` | JUnit XML | Test results for CI systems |
| `ci/reports/sarif.json` | SARIF 2.1.0 | Security findings for GitHub code scanning |
| `ci/reports/index.html` | HTML | Self-contained dashboard |
| `ci/reports/trace.json` | Chrome Trace | Performance profiling |
| `ci/reports/events.ndjson` | NDJSON | Structured event log |

## Hook Dispatch System

All git hooks delegate to a single dispatcher:

```
.githooks/pre-commit  ─┐
.githooks/commit-msg  ─┤→  ci/hook-dispatch.sh  →  ci/preflight.sh --mode <hook>
.githooks/pre-push    ─┤
.githooks/prepare-commit-msg ─┘
```

The dispatcher receives the hook name as `$1` and routes to the appropriate preflight mode:

| Hook | Mode | Budget |
|------|------|--------|
| `pre-commit` | `quick` | ≤ 10 s (staged files only) |
| `commit-msg` | `commit-msg` | ≤ 2 s |
| `prepare-commit-msg` | `prepare` | ≤ 2 s |
| `pre-push` | `ship` | Full gate |

## Configuration System

| File | Purpose |
|------|---------|
| `ci/config/gate.yml` | Global toggles, parallelism, timeouts, severity policy |
| `ci/config/checks.yml` | Per-check enable/disable and option overrides |
| `ci/config/affected.yml` | File→test mapping rules |
| `ci/config/thresholds.yml` | Coverage, diff size, complexity limits |
| `ci/config/cache.yml` | Cache backend and retention config |
| `ci/config/ignore.yml` | Paths to skip globally |
| `ci/checks/manifest.yml` | Check registry (source of truth for all checks) |
| `.ci-gateignore` | gitignore-style per-project path exclusions |
