# Agent Safety Rules

> **Mandatory reading for all agents.** Read this file fully before editing any code, running any command, or claiming completion. Violation of these rules will be treated as a critical failure.

---

## 1. Read before acting

Before editing any file, the agent must read:

```text
AGENTS.md
CI_GATE_IMPLEMENTATION_PLAN_FOR_AGENTS.md (if it exists)
package.json (if it exists)
pyproject.toml (if it exists)
Makefile
existing ci/ scripts
existing test configuration files
```

The agent must not start implementation before understanding the existing repository structure, current debt status, and the phase plan.

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
bypass debt ratchet by widening allowed counts
```

Known debt may be documented in `ci/debt/known-failures.yml`, but it must not be hidden or suppressed.

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

The default behavior must always protect user work, uncommitted changes, and repository history.

---

## 4. No fake "done"

The agent must not say "done" unless it provides command evidence.

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

Vague summaries such as "looks good" or "should work now" are prohibited.

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
never auto-stage untracked files without explicit confirmation
never commit or push automatically
```

---

## 6. No automatic commits or pushes

The agent must never:

```text
git commit -m "..." without user approval
git push origin <branch> without user approval
git tag without user approval
make ship without user approval
```

The `make ship` and `./ci/ship.sh` commands are reserved for explicit user invocation only.

---

## 7. Validate syntax before claiming success

Every modified `.sh` file must pass:

```bash
bash -n <file>
```

before the agent reports the phase as complete. If `shellcheck` is available, it should also be run.

Every modified `.yml` or `.json` file must be syntactically valid:

```bash
python3 -c "import yaml; yaml.safe_load(open('file.yml'))"  # for YAML
python3 -c "import json; json.load(open('file.json'))"      # for JSON
```

---

## 8. Preserve existing behavior

The agent must not:

```text
change the default mode of preflight.sh
remove existing Makefile targets
break existing git hooks
alter the debt registry without explicit justification
change result codes (0, 10, 20, 30, 99) in ci/lib/common.sh
```

New features may be added. Existing features may only be removed with user approval.

---

## 9. Report debt honestly

If the agent encounters pre-existing failures:

```text
1. Do not fix them silently unless the phase plan explicitly authorizes cleanup.
2. Document them in ci/reports/latest.md or ci/reports/baseline-current-state.md.
3. If they are new (not in known-failures.yml), classify as FAIL_NEW_ISSUE.
4. If they are known and unchanged, classify as PASS_WITH_KNOWN_DEBT.
```

---

## 10. Stop on emergency conditions

The agent must stop and report immediately if:

```text
files appear unexpectedly deleted
large unrelated diffs appear
secrets or tokens are detected in code or output
commands require destructive actions
package manager lockfiles conflict unexpectedly
tests require production credentials
CI scripts would push or deploy automatically
debt increased and the cause is unclear
bash -n fails on any modified file
```

Do not continue by guessing.

---

## 11. Environment hygiene

The agent must:

```text
run commands from the repository root (cd "$(git rev-parse --show-toplevel)")
use relative paths, never absolute paths outside the repo
not install global packages without user approval
not modify system-level configuration
not leave temporary files in the repository (clean up mktemp artifacts)
```

---

## 12. Evidence standard

Every claim must be backed by one of:

```text
- Command output (quoted verbatim)
- File diff (showing before/after)
- Exit code (explicitly stated)
- Report file path (ci/reports/...)
```

Claims without evidence will be rejected.

---

*Version: 1.0*
*Applies to: all agents working on local-self-hosted-ci-gate*
