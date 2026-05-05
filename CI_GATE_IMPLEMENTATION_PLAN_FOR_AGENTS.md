# CI Gate Implementation Plan for Agents

## Purpose

This file is a professional implementation handoff for agents working on the local self-hosted CI gate.

The target system is a **Mac-local self-hosted CI gate** that runs all applicable validation before code is committed, pushed, or considered ready.

The gate must be strict about **new problems**, while handling existing repository debt safely through a ratchet model.

Current known pre-existing issues:

| Issue | Status | Notes |
|---|---|---|
| Ruff `ASYNC240` warnings | Pre-existing | `pathlib` usage in async contexts |
| Ruff `I001` warnings | Pre-existing | Import sorting warnings |
| Pytest 4 failures | Pre-existing | Capability diagnostic / manifest tests failed before CI gate work |

The CI gate did not introduce these issues. The gate correctly detected them.

The next development objective is to upgrade the gate from a binary pass/fail script into a **professional ratchet-based CI gate**.

---

# Mandatory Agent Rules

## 1. Read before acting

Before editing any file, the agent must read:

```text
AGENTS.md
ci/README.md if it exists
package.json if it exists
pyproject.toml if it exists
Makefile if it exists
existing ci/ scripts if they exist
existing test configuration files
```

The agent must not start implementation before understanding the existing repository structure.

---

## 2. Do not hide failures

The agent must never:

```text
ignore failing tests silently
remove failing tests to make CI pass
weaken test assertions without explanation
mark a failed command as passed
suppress warnings without owner approval
remove lint rules just to pass CI
delete files to avoid failures
skip affected tests without recording why
```

Known debt may be documented, but it must not be hidden.

---

## 3. No destructive Git operations

The agent must never run:

```bash
git reset --hard
git clean -fd
git push --force
git push --force-with-lease
rm -rf
```

unless the user explicitly provides a separate written instruction for a specific emergency recovery case.

The default behavior must always protect user work.

---

## 4. No fake “done”

The agent must not say “done” unless it provides command evidence.

Every completion report must include:

```text
files changed
commands run
commands passed
commands failed
known debt status
new issue status
final CI result
remaining risks
next recommended phase
```

---

## 5. Treat the client as non-technical

The user may overlook risks, forget steps, or misunderstand whether something is safe.

Therefore, the agent must:

```text
protect files by default
avoid destructive shortcuts
explain risks in the phase report
validate all touched areas
never assume skipped tests are acceptable
never claim success without proof
```

---

# Target CI Gate Behavior

The CI gate must support these commands:

```bash
make ci-quick
make ci-full
make ci-ship
make ci-debt
make ship
```

## Command purposes

| Command | Purpose | Expected use |
|---|---|---|
| `make ci-quick` | Fast validation for changed work | During development |
| `make ci-full` | Full repository validation | Before major handoff |
| `make ci-ship` | Pre-push local gate | Before updating repo |
| `make ci-debt` | Known failure/debt comparison | Track legacy issues |
| `make ship` | Run ship flow after validation | Commit/push helper if allowed |

---

# Required CI Result States

The gate must not return only vague pass/fail results.

It must classify each run as one of these:

| Result | Meaning |
|---|---|
| `PASS` | Everything passed. No known debt. No new issues. |
| `PASS_WITH_KNOWN_DEBT` | Changed work passed. Known debt is unchanged. |
| `FAIL_NEW_ISSUE` | New warning, failure, or regression was introduced. |
| `FAIL_INFRA` | CI tool, dependency, environment, or script problem. |

Current acceptable temporary state:

```text
PASS_WITH_KNOWN_DEBT
```

Only allowed if:

```text
known debt is unchanged
changed files pass relevant checks
no new warnings exist
no new pytest failures exist
security checks pass
reports clearly show the debt
```

Final long-term target:

```text
PASS
```

---

# Required Directory Structure

Create or update this structure:

```text
ci/
  README.md
  preflight.sh
  ship.sh
  install-hooks.sh

  checks/
    git-safety.sh
    changed-files.sh
    node.sh
    python.sh
    security.sh
    build.sh
    debt.sh

  lib/
    common.sh
    git.sh
    report.sh

  debt/
    known-failures.yml
    README.md

  reports/
    .gitkeep

.githooks/
  pre-push

Makefile
```

If some files already exist, update them safely. Do not overwrite without reading current content first.

---

# Phase 0 — Discovery and Baseline

## Goal

Understand the project and record the current state before implementing more CI logic.

## Agent tasks

Inspect all relevant files:

```text
AGENTS.md
package.json
pnpm-lock.yaml
package-lock.json
yarn.lock
bun.lockb
biome.json
biome.jsonc
tsconfig.json
next.config.*
pyproject.toml
ruff.toml
pytest.ini
requirements.txt
uv.lock
poetry.lock
Makefile
ci/
.githooks/
install.sh
deploy.sh
README.md
```

## Commands to run if applicable

The agent should run only safe discovery commands:

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git diff --name-only
git diff --cached --name-only
find ci -maxdepth 3 -type f 2>/dev/null || true
```

If Node project exists:

```bash
node --version
npm --version || true
pnpm --version || true
yarn --version || true
```

If Python project exists:

```bash
python3 --version
python --version || true
ruff --version || true
pytest --version || true
```

## Required output file

Create:

```text
ci/reports/baseline-current-state.md
```

It must include:

```text
date/time
branch
commit SHA
detected package manager
detected Node version
detected Python version
detected test commands
detected build commands
existing CI files
existing known failures
changed files
staged files
risk notes
```

## Phase 0 exit criteria

The agent may proceed only after:

```text
baseline report exists
current known issues are documented
no implementation files were changed except reports if possible
```

---

# Phase 1 — Common CI Library

## Goal

Create shared helpers so all scripts behave consistently.

## Files

```text
ci/lib/common.sh
ci/lib/git.sh
ci/lib/report.sh
```

## `common.sh` requirements

Provide helpers for:

```text
strict bash mode
log section headers
error handling
command existence detection
safe command execution
mode parsing
project root detection
```

Minimum behavior:

```bash
set -Eeuo pipefail
```

No script should rely on the user being in a random working directory. Scripts must resolve the project root safely.

## `git.sh` requirements

Provide helpers for:

```text
current branch
current commit SHA
changed files
staged files
untracked files
merge conflict marker scan
sensitive staged file detection
```

## `report.sh` requirements

Provide helpers for writing:

```text
ci/reports/latest.md
ci/reports/latest.log
```

Every CI run must create or update these report files.

---

# Phase 2 — Git Safety Gate

## File

```text
ci/checks/git-safety.sh
```

## Goal

Prevent dangerous pushes, accidental secret commits, unresolved conflicts, and unsafe staged files.

## Required checks

Block if:

```text
not inside a git repository
branch cannot be detected
merge conflict markers exist
git diff --check fails
.env file is staged
private key is staged
known secret-like value is staged
node_modules is staged
.venv is staged
large accidental artifact is staged
build output is staged without explicit allowlist
```

## Must scan for conflict markers

```text
<<<<<<<
=======
>>>>>>>
```

## Sensitive files to block

At minimum:

```text
.env
.env.local
.env.production
*.pem
*.key
*.p12
*.pfx
id_rsa
id_ed25519
```

## Sensitive values to block

At minimum:

```text
ghp_
sk-
BEGIN PRIVATE KEY
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
DATABASE_URL=
CRON_SECRET
PHANTOM_AES_KEY
Authorization:
Cookie:
```

Pattern matching is a safety net, not complete secret prevention. It is context-insensitive, can produce false positives in docs/comments/test fixtures, and can miss obfuscated or non-standard credentials. Agents should recommend layered controls: correct `.gitignore` coverage, pre-commit scanning (`git-secrets`/equivalent), CI validation of required env vars, secret rotation/vaulting (for example AWS Secrets Manager), and manual review before shipping.

For OPUS / Phantom work, also block accidental exposure of:

```text
PHANTOM_EVIDENCE_DIR
raw filesystem evidence paths
raw IP diagnostics
raw user-agent diagnostics
raw auth headers
cookies
credentials
raw audit details
```

## Exit criteria

`ci/checks/git-safety.sh` must pass when no unsafe state exists and fail clearly when unsafe files are staged.

---

# Phase 3 — Changed Files Detection

## File

```text
ci/checks/changed-files.sh
```

## Goal

Allow fast checks to focus on changed areas while full checks still validate the full project.

## Required behavior

Detect:

```text
changed files against working tree
staged files
changed Node/frontend files
changed Python files
changed shell scripts
changed config files
changed CI files
changed docs
```

Output should be machine-readable enough for other scripts to use.

Recommended output files:

```text
ci/reports/changed-files.txt
ci/reports/staged-files.txt
```

---

# Phase 4 — Node / Frontend CI Lane

## File

```text
ci/checks/node.sh
```

## Goal

Run all applicable Node/frontend checks safely.

## Package manager detection

Detect by lockfile:

| Lockfile | Manager |
|---|---|
| `pnpm-lock.yaml` | pnpm |
| `package-lock.json` | npm |
| `yarn.lock` | yarn |
| `bun.lockb` | bun |

Do not guess incorrectly.

If multiple lockfiles exist, behavior must be deterministic:

```text
1) Check repository policy:
   - ci-config.yaml: lockfile_policy
   - package.json: ci.lockfilePolicy
2) Allowed values: warn | fail
3) If policy key is missing, default to warn.
4) Report the resolved policy and decision in ci/reports/latest.md.
```

## Required checks

Run scripts only if they exist in `package.json`:

```text
format check
lint
typecheck
test
test:unit
build
schema validation if present
```

Recommended mapping:

| Script name | Action |
|---|---|
| `format:check` | Run |
| `lint` | Run |
| `typecheck` | Run |
| `test` | Run |
| `test:unit` | Run |
| `build` | Run |
| `ci` | Run only if already trusted and documented |

## Zod v4 protection

Because recent fixes included Zod v4 work, the Node lane must catch:

```text
Zod v3/v4 incompatible API usage
invalid schema imports
runtime schema failures
TypeScript schema mismatch
broken generated manifest consumers
```

Add explicit checks in the Node lane with clear failure labels:

```text
zodVersionCheck:
  - Inspect installed zod version and fail when >=4 conflicts with v3-only code paths.

validateSchema:
  - Dynamic import/load of schema modules used by the app to detect invalid imports.
  - Runtime schema smoke checks with representative valid/invalid payloads.

manifestConsumerSmokeTest:
  - TypeScript checker plus generated-manifest consumer smoke test.
```

## Exit criteria

The Node lane must:

```text
not fail because a script is missing
clearly report skipped missing scripts
fail if an existing configured script fails
include all command outputs in reports
```

---

# Phase 5 — Python / Phantom CI Lane

## File

```text
ci/checks/python.sh
```

## Goal

Run all applicable Python checks safely while tracking known legacy debt.

## Detection logic

Detect:

```text
pyproject.toml
ruff.toml
pytest.ini
requirements.txt
uv.lock
poetry.lock
Python package directories
FastAPI app entrypoints if obvious
```

## Required checks

Run applicable checks:

```text
python syntax compile
ruff check
ruff format check if configured
pytest
import smoke tests
FastAPI app import check if applicable
```

## Current known issues

The following must be treated as known debt initially:

```text
Ruff ASYNC240 warnings
Ruff I001 warnings
4 pytest failures in capability diagnostic / manifest tests
```

## Ratchet rules

The Python lane must fail if:

```text
new Ruff warning codes appear
ASYNC240 count increases
I001 count increases
new pytest failing test names appear
any touched Python file introduces a new failure
Python tooling itself is broken
```

The Python lane may return `PASS_WITH_KNOWN_DEBT` if:

```text
only known failures remain
known failure counts are unchanged
no changed files are responsible
all other checks pass
```

---

# Phase 6 — Known Debt Registry

## Files

```text
ci/debt/known-failures.yml
ci/debt/README.md
```

## Goal

Document existing debt without hiding it.

## Required `known-failures.yml` structure

Use this structure:

```yaml
version: 1

known_failures:
  - id: PY-RUFF-ASYNC240-001
    type: ruff
    command: "ruff check ."
    status: known_debt
    first_seen: "2026-05-03"
    reason: "Pre-existing ASYNC240 pathlib-in-async warnings."
    allowed_until: "2026-05-17"
    owner: "project"
    blocking: false
    must_not_increase: true
    signatures:
      - "ASYNC240"

  - id: PY-RUFF-I001-001
    type: ruff
    command: "ruff check ."
    status: known_debt
    first_seen: "2026-05-03"
    reason: "Pre-existing import sorting warnings."
    allowed_until: "2026-05-17"
    owner: "project"
    blocking: false
    must_not_increase: true
    signatures:
      - "I001"

  - id: PYTEST-CAPABILITY-DIAGNOSTICS-001
    type: pytest
    command: "pytest"
    status: known_debt
    first_seen: "2026-05-03"
    reason: "Pre-existing capability diagnostic / manifest tests failed before CI gate changes."
    allowed_until: "2026-05-17"
    owner: "project"
    blocking: false
    must_not_increase: true
    affected_area:
      - "capability diagnostics"
      - "manifest tests"
```

## Rules for debt entries

No debt entry may be added without:

```text
unique ID
command
failure type
exact signature
reason
proof it is pre-existing
owner
expiry date
blocking flag
must_not_increase flag
```

No debt entry may be permanent.

Debt expiry enforcement is mandatory. The debt check must parse every `known_failures[]` entry and compare `allowed_until` to the current date:

```text
- Parse using structured tooling (yq or a small Python helper), not brittle grep-only parsing.
- For each entry: if today > allowed_until, fail as FAIL_NEW_ISSUE.
- Emit: ERROR: Debt entry <id> expired on <allowed_until>.
- Expired entries must block ship mode until renewed or removed with explicit justification.
```

---

# Phase 7 — Debt Ratchet Check

## File

```text
ci/checks/debt.sh
```

## Goal

Allow development to continue while preventing existing debt from growing.

## Required behavior

Run known failing checks and compare current output against baseline.

The script must:

```text
run known debt commands
capture output to ci/reports/debt-current.log
count known Ruff warning codes
extract pytest failing test names
compare against known-failures.yml
fail if new warning code appears
fail if warning count increases
fail if new pytest failing test appears
fail if known debt expiry has passed
report unchanged known debt clearly
```

## Example passing result

```text
Debt result: PASS_WITH_KNOWN_DEBT
Known Ruff ASYNC240 warnings: unchanged
Known Ruff I001 warnings: unchanged
Known pytest failures: unchanged
New Ruff codes: 0
New pytest failures: 0
Debt increased: no
```

## Example failing result

```text
Debt result: FAIL_NEW_ISSUE
Known Ruff ASYNC240 warnings increased.
Blocking ship.
```

---

# Phase 8 — Security Gate

## File

```text
ci/checks/security.sh
```

## Goal

Prevent accidental credential, token, evidence, or sensitive diagnostic leakage.

## Required checks

At minimum:

```text
scan staged files
scan changed files
block secret-like patterns
block .env staging
block private keys
block raw credentials
block unsafe Phantom evidence diagnostics
run dependency audit when available
```

## Dependency audit behavior

For Node:

```text
npm audit if npm is used
pnpm audit if pnpm is used and available
yarn audit if yarn is used and available
```

For Python:

```text
run pip-audit only if installed/configured
otherwise report skipped optional tool
```

The gate must not pretend optional tools ran when they did not.

---

# Phase 9 — Build Validation

## File

```text
ci/checks/build.sh
```

## Goal

Validate that the project can be built or packaged safely.

## Required checks

Run applicable checks:

```text
Next.js build if present
TypeScript build if present
Python import/package build if present
Prisma validate/generate if Prisma exists
Dockerfile syntax or build validation if appropriate
shell script syntax validation
README command sanity where possible
```

## Shell validation

Run:

```bash
bash -n ci/*.sh
bash -n ci/checks/*.sh
bash -n ci/lib/*.sh
```

If these files exist:

```bash
bash -n install.sh
bash -n deploy.sh
```

If `shellcheck` exists, run it.

If `shellcheck` is missing, report it as skipped optional validation and continue. Teams that require strict shell linting can enforce it via local policy by making `shellcheck` a mandatory prerequisite.

---

# Phase 10 — Main Preflight Script

## File

```text
ci/preflight.sh
```

## Goal

Central entrypoint for all CI gate modes.

## Required modes

```bash
./ci/preflight.sh --mode quick
./ci/preflight.sh --mode full
./ci/preflight.sh --mode ship
./ci/preflight.sh --mode debt
```

## Mode behavior

### Quick mode

Runs:

```text
git safety
changed files detection
changed-area lint/test checks
fast Node checks if applicable
fast Python checks if applicable
```

### Full mode

Runs:

```text
git safety
changed files detection
Node lane
Python lane
security lane
build lane
debt lane
```

### Ship mode

Runs:

```text
git safety
changed files detection
Node lane
Python lane
security lane
build lane
debt ratchet
```

Ship mode must block:

```text
new issues
security failures
build failures
known debt increase
unsafe git state
```

Ship mode may allow:

```text
unchanged known debt
```

### Debt mode

Runs only:

```text
known debt comparison
```

## Timeout and hang protection

Preflight should provide a reusable timeout wrapper (for example `run_with_timeout`) and apply it to long-running checks.

Required behavior:

```text
- timeout utility detection: timeout (GNU) or gtimeout (macOS via coreutils)
- configurable per-check timeouts via env vars
- clear timeout failure message when exit code 124 is returned
- non-timeout non-zero exits must propagate unchanged
```

Recommended defaults:

```text
lint/check scripts: 60s
unit tests: 300s
integration tests/build/security scans: 600s
```

---

# Phase 11 — Ship Script

## File

```text
ci/ship.sh
```

## Goal

Allow safe local shipping after the CI gate passes.

## Required behavior

The script must:

```text
run ./ci/preflight.sh --mode ship
stop if it fails
show staged files
show changed files
never force push
never reset
never clean
push only current branch
```

The script must not automatically stage every file unless explicitly designed and documented.

Prefer staged-first behavior:

```bash
git diff --cached --quiet
```

If nothing is staged, fail with guidance:

```text
- stage explicitly (recommended): git add -p or git add <paths>
- optional auto-stage tracked files only after explicit user confirmation
```

Auto-staging tracked files with `git add -u` is allowed only as an explicit opt-in mode and must print a clear `git status --short` summary first.

---

# Phase 12 — Git Hook Installation

## Files

```text
.githooks/pre-push
ci/install-hooks.sh
```

## `pre-push` behavior

Run:

```bash
./ci/preflight.sh --mode ship
```

The hook must block push if:

```text
new issue exists
build fails
security scan fails
known debt increases
unsafe git state exists
```

The hook may allow push if:

```text
only unchanged known debt exists
```

## `install-hooks.sh` behavior

Run:

```bash
git config core.hooksPath .githooks
```

Then print a clear message explaining that pre-push validation is active.

---

# Phase 13 — Makefile Targets

## File

```text
Makefile
```

## Required targets

```makefile
ci-quick:
	./ci/preflight.sh --mode quick

ci-full:
	./ci/preflight.sh --mode full

ci-ship:
	./ci/preflight.sh --mode ship

ci-debt:
	./ci/preflight.sh --mode debt

ship:
ifndef MESSAGE
	@echo "Usage: make ship MESSAGE=\"your commit message\""
	@exit 1
endif
	./ci/ship.sh "$(MESSAGE)"

install-hooks:
	./ci/install-hooks.sh
```

If a Makefile already exists, merge safely. Do not overwrite unrelated existing targets.

---

# Phase 14 — Reporting

## Files

```text
ci/reports/latest.md
ci/reports/latest.log
```

## Every run must report

```text
mode
branch
commit SHA
start time
finish time
duration
changed files
staged files
commands run
commands passed
commands failed
known debt status
new issue status
security status
build status
final result
next recommended action
```

## Final result examples

```text
PASS
PASS_WITH_KNOWN_DEBT
FAIL_NEW_ISSUE
FAIL_INFRA
```

The report must be understandable to a non-technical owner.

---

# Phase 15 — Cleanup Plan for Existing Debt

After the ratchet gate works, clean old issues in separate PRs or separate phases.

## Cleanup A — Ruff I001

Goal:

```text
fix import sorting warnings
```

Potential command:

```bash
ruff check . --select I001 --fix
```

Validation required:

```text
ruff check .
pytest affected tests
full Python import smoke
```

Do not run automated fixes without inspecting the diff.

---

## Cleanup B — Ruff ASYNC240

Goal:

```text
replace unsafe pathlib calls inside async contexts
```

The agent must inspect each case carefully. Do not blindly convert filesystem logic.

Validation required:

```text
ruff check .
pytest affected tests
async behavior tests if available
manual review of Phantom evidence safety
```

---

## Cleanup C — Capability Diagnostic / Manifest Tests

Goal:

```text
repair failing capability diagnostic / manifest tests
```

The agent must inspect:

```text
expected manifest contract
actual manifest output
platform capability registry
Hunter/Phantom contract compatibility
test fixtures
generated files
TypeScript/Python manifest consumers
```

Validation required:

```text
targeted failing pytest tests
full pytest
Node manifest consumer tests if present
shared manifest validation if present
```

---

# Phase 16 — Promotion to Strict Mode

After all known debt is fixed, update the CI gate so known debt is no longer accepted.

Target state:

```text
make ci-full = PASS
make ci-ship = PASS
make ci-debt = PASS with no active debt
```

Remove fixed debt entries or mark them as resolved with proof.

No permanent known debt is allowed.

---

# Testing and Validation Matrix

Before claiming completion, the agent must run every applicable command below.

## Bash validation

```bash
bash -n ci/*.sh
bash -n ci/checks/*.sh
bash -n ci/lib/*.sh
bash -n .githooks/pre-push
```

If present:

```bash
bash -n install.sh
bash -n deploy.sh
```

## CI gate validation

```bash
make ci-quick
make ci-debt
make ci-ship
```

If full mode is implemented:

```bash
make ci-full
```

## Node validation if applicable

Run package scripts discovered from `package.json`, such as:

```bash
npm run lint
npm run typecheck
npm test
npm run build
```

or equivalent `pnpm`, `yarn`, or `bun` commands.

## Python validation if applicable

Run discovered Python checks, such as:

```bash
ruff check .
pytest
python -m compileall .
```

Known failures must be classified through the debt system, not ignored.

## Security validation

The agent must verify that the security gate detects obvious staged secrets safely.

This should be done carefully without committing secrets.

If the agent creates a temporary test file, it must delete only that temporary test file and report it.

## Report validation

Confirm these files are generated:

```text
ci/reports/latest.md
ci/reports/latest.log
```

Confirm the report includes:

```text
final result
commands run
known debt status
new issue status
```

---

# Required Final Agent Report Format

At the end of each phase, the agent must report exactly this structure:

```text
Phase completed:

Files changed:
- ...

Commands run:
- command: result

Validation results:
- ...

Known debt status:
- unchanged / increased / reduced / not checked with reason

New issue status:
- none / found with details

Final result:
- PASS / PASS_WITH_KNOWN_DEBT / FAIL_NEW_ISSUE / FAIL_INFRA

Risks / gaps:
- ...

Next recommended phase:
- ...
```

No vague summaries are allowed.

---

# Agent Task Complexity Guidance

Select the agent/model based on task characteristics rather than specific model names:

| Task phase | Capability emphasis |
|---|---|
| Discovery and baseline | long-context reading, accurate repo state summarization |
| Bash/CI scripting | shell reliability, safe failure semantics, deterministic behavior |
| Python debt parsing | log parsing, structured-data handling, conservative ratchet logic |
| Node/frontend CI lane | JavaScript/TypeScript ecosystem knowledge and script orchestration |
| Security review | pattern + context analysis, secret-handling rigor |
| Final architecture review | cross-cutting validation and risk-focused review quality |

Final review questions should include:

```text
Did the implementation hide, suppress, or bypass any real failure?
Are the CI scripts safe against accidental data loss?
Does the ratchet correctly block new issues while allowing unchanged known debt?
```

---

# Emergency Stop Conditions

The agent must stop and report immediately if:

```text
files appear unexpectedly deleted
large unrelated diffs appear
secrets are detected
commands require destructive actions
package manager lockfiles conflict unexpectedly
tests require production credentials
CI scripts would push or deploy automatically
debt increased and the cause is unclear
```

Do not continue by guessing.

---

# Final Definition of Done

The CI gate implementation is complete only when all of the following are true:

```text
ci/preflight.sh exists and supports quick/full/ship/debt modes
ci/checks/ scripts exist and are wired correctly
ci/debt/known-failures.yml exists
known debt is documented
known debt does not increase silently
new issues are blocked
security gate blocks obvious secrets
build validation runs where applicable
Makefile targets exist
pre-push hook exists
hook installer exists
reports are generated
bash syntax checks pass
changed work passes applicable validation
agent provides command evidence
```

Temporary acceptable final state:

```text
PASS_WITH_KNOWN_DEBT
```

Final target state after debt cleanup:

```text
PASS
```

with:

```text
zero Ruff warnings
zero pytest failures
zero active known debt entries
```

---

# Agent Start Prompt

Use this prompt with OpenCode or another agent:

```text
Read AGENTS.md and CI_GATE_IMPLEMENTATION_PLAN_FOR_AGENTS.md fully before acting.

Implement the local Mac self-hosted CI gate as a ratchet-based CI system.

Current known pre-existing issues:
1. Ruff ASYNC240 pathlib-in-async warnings.
2. Ruff I001 import sorting warnings.
3. Four pytest failures in capability diagnostic / manifest tests.

Do not hide, delete, reset, suppress, or bypass these failures.

The CI gate must:
- block new issues,
- report existing known debt,
- fail if known debt increases,
- allow safe ship only when changed work passes and known debt is unchanged,
- generate reports under ci/reports/,
- never say done without command evidence.

Proceed phase by phase.
Start with Phase 0 discovery only.
After each phase, report files changed, commands run, exact results, known debt status, new issue status, risks, and next phase.

Do not push, force-push, reset, clean, delete files, or install global tools.
```
