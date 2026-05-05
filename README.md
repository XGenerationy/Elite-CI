# Elite CI Gate

**Local-first CI pipeline. Runs on your machine. Blocks bad code before it leaves.**

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)]()
[![ShellCheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)]()
[![Version](https://img.shields.io/badge/version-2.0-blue)](ci/VERSION)

---

## Elite vs Vanilla GitHub Actions

| Feature | Vanilla GitHub CI | CI Gate Elite |
|---------|------------------|---------------|
| File-change detection | ❌ Manual | ✅ Auto (git diff) |
| Affected test selection | ❌ | ✅ nx/turbo/pytest-testmon |
| Parallel execution | ✅ (matrix only) | ✅ Bounded DAG runner |
| Hermetic caching | ✅ Cache action | ✅ Content-addressed local cache |
| SARIF security reports | ✅ CodeQL | ✅ semgrep/bandit/gosec/gitleaks |
| JUnit test reports | ✅ | ✅ |
| Pre-commit blocking | ❌ (post-push) | ✅ (pre-commit hook) |
| Local execution | ❌ | ✅ |
| Internet required | ✅ Always | ✅ Optional |
| Feedback time | 2-10 min | < 10 sec (pre-commit) |
| Auto-fix mode | ❌ | ✅ --fix |
| Conventional commits | ❌ | ✅ Built-in |
| Secret scanning | GitHub secret scanning | ✅ gitleaks + regex (pre-commit) |
| Supply chain verification | ❌ | ✅ lockfile integrity |
| Coverage enforcement | Needs plugin | ✅ Built-in thresholds |
| Chrome trace profiling | ❌ | ✅ trace.json |
| HTML dashboard | ❌ | ✅ Self-contained |

---

## What Is This?

A local continuous integration gate that runs **on your machine** before code ever leaves it. Think of it as your own private CI pipeline — no servers, no cloud, no waiting for GitHub Actions. Run `make verify` and know your code is clean before you commit.

- **Blocks bad pushes** — pre-push hook stops broken code from reaching the remote
- **Finds secrets before they leak** — scans for keys, tokens, and credentials pre-commit
- **Validates everything** — lint, format, typecheck, tests, SAST, secrets, supply-chain — all in one command
- **Auto change detection** — only runs checks relevant to what you changed
- **Zero external dependencies** — bash + awk, works on any Mac or Linux machine
- **Open source** — Apache 2.0, free forever

---

## Quick Start

```bash
git clone https://github.com/XGenerationy/local-self-hosted-ci-gate.git
cd local-self-hosted-ci-gate
make install-hooks    # one-time: installs git hooks
make verify           # run all checks
```

To commit and push safely:

```bash
make ship MESSAGE="fix login bug"
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Developer Workstation                        │
│                                                                  │
│  git commit / git push                                           │
│        │                                                         │
│        ▼                                                         │
│  ┌─────────────┐    ┌──────────────────────────────────────-┐    │
│  │  Git Hooks  │    │          ci/preflight.sh              │    │
│  │             │    │                                       │    │
│  │ pre-commit  │───▶│  ┌─────────────┐  ┌──────────────┐    │    │
│  │ commit-msg  │    │  │  Changeset  │  │   Parallel   │    │    │
│  │ pre-push    │    │  │  Detection  │  │     DAG      │    │    │
│  │ prepare-    │    │  │  Engine     │  │   Runner     │    │    │
│  │ commit-msg  │    │  └──────┬──────┘  └──────┬───────┘    │    │
│  └─────────────┘    │         │                │            │    │
│                      │  ┌──────▼──────┐  ┌────▼─────────┐   │    │
│                      │  │  Changeset  │  │   Checks:    │   │    │
│                      │  │    JSON     │  │ lint/format  │   │    │
│                      │  └─────────────┘  │ typecheck    │   │    │
│                      │                   │ tests        │   │    │
│                      │                   │ sast/secrets │   │    │
│                      │                   └──────┬───────┘   │    │
│                      │  ┌────────────────────────┴──────┐   │    │
│                      │  │           Reports             │   │    │
│                      │  │  summary.md  sarif.json  html │   │    │
│                      │  │  junit.xml   trace.json       │   │    │
│                      │  └───────────────────────────────┘   │    │
│                      └──────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────-────┘
              │
              ▼  (if all checks pass)
       git push → GitHub → CI Gate workflow mirrors local checks
```

---

## Feature Matrix

| Category | Checks |
|----------|--------|
| **Hygiene** | Whitespace, conflict markers, conventional commits, branch protection |
| **Security** | gitleaks secrets, semgrep/bandit/gosec SAST, supply-chain lockfile integrity, license compatibility |
| **Lint** | shellcheck, eslint, ruff/flake8, golangci-lint, hadolint, yamllint |
| **Format** | shfmt, prettier, black/ruff, gofmt |
| **Typecheck** | tsc, mypy/pyright, go vet |
| **Tests** | jest/vitest, pytest, go test, bats (with JUnit XML output) |
| **Container** | hadolint, trivy fs/image |
| **IaC** | tflint, checkov |

See [docs/CHECKS.md](docs/CHECKS.md) for the full check catalog.

---

## Configuration Reference

| File | Purpose |
|------|---------|
| `ci/config/gate.yml` | Global toggles, parallelism, timeouts, severity policy |
| `ci/config/checks.yml` | Per-check enable/disable and option overrides |
| `ci/config/thresholds.yml` | Coverage, diff size, complexity limits |
| `ci/config/cache.yml` | Cache backend and retention config |
| `ci/config/ignore.yml` | Paths to skip globally |
| `ci/checks/manifest.yml` | Check registry (source of truth) |
| `.ci-gateignore` | gitignore-style per-project path exclusions |

---

## Commands Reference

| Command | Does |
|---------|------|
| `make verify` | Run full check suite |
| `make ci-quick` | Fast pre-commit checks only |
| `make ci-full` | Full check suite |
| `make ci-all` | Full tree scan (no incremental) |
| `make ci-fix` | Run with auto-fix mode |
| `make ci-profile` | Run with timing profile output |
| `make ci-ship` | Ship-mode gate |
| `make ci-debt` | Debt ratchet check |
| `make impact` | Generate impact analysis report |
| `make test-plan` | Generate smart test plan |
| `make smart` | Generate plan then run full gate |
| `make install-hooks` | Install all git hooks |
| `make ci-self-test` | Validate CI scripts themselves |
| `make bats` | Run bats test suite |
| `make lint-ci` | Syntax-check all CI scripts |
| `make docs` | Regenerate docs/CHECKS.md |
| `make ship MESSAGE="msg"` | Run checks, commit, push |

---

## Install In Your Own Project

Copy these files into your repository:

```
ci/                     # Full CI gate directory
.githooks/              # Git hook scripts
Makefile                # Convenience targets
.gitignore              # Secret + artifact protection
```

Then:

```bash
make install-hooks
make verify
```

Wire your project's commands into `ci/preflight.sh` section 4-8.

---

## Requirements

- macOS or Linux
- bash 3.2+
- git 2.0+
- make (pre-installed on macOS/Linux)

No global packages, no Homebrew, no Docker required.

---

## Safety Guarantees

- Never deletes files or changes your code
- Never force-pushes
- Never commits untracked files by default
- Never commits `.env`, keys, certificates, or credentials
- Never pushes from detached HEAD
- Never skips tests or suppresses failures

---

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md). Open source under Apache 2.0.

---

**Built with bash. Powered by discipline.**

[GitHub](https://github.com/XGenerationy/local-self-hosted-ci-gate) · [License](LICENSE) · [Changelog](CHANGELOG.md) · [Architecture](docs/ARCHITECTURE.md)
