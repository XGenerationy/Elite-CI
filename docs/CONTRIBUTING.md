# Contributing

Thank you for contributing to the CI Gate project!

## How to Add a New Check

1. **Create the check script** at `ci/checks/<name>.sh`:

   ```bash
   #!/usr/bin/env bash
   set -Eeuo pipefail
   # shellcheck source=../lib/common.sh
   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

   ci::<name>::detect() { ... }
   ci::<name>::plan()   { ... }
   ci::<name>::run()    { ... }
   ci::<name>::report() { ... }
   ```

2. **Register it** in `ci/checks/manifest.yml`:

   ```yaml
   - id: my-check
     script: ci/checks/my-check.sh
     description: "What this check does"
     languages: [python]       # or [] for all languages
     requires_tool: mytool     # optional
     severity: blocker         # blocker | warning | advisory
     phase: lint               # lint | typecheck | format | tests | coverage | security | hygiene
     pre_commit: true          # runs in pre-commit fast mode?
     timeout_sec: 60
   ```

3. **Write tests** in `ci/tests/test_<name>.bats`.

4. **Run the gate**: `make verify && make ci-self-test`.

## Code Conventions

- All scripts must start with `#!/usr/bin/env bash` and `set -Eeuo pipefail`.
- Function names use the namespace `ci::<module>::<function>` (e.g., `ci::cache::hit`).
- Exit codes follow the standard defined in `ci/lib/common.sh`:
  - `0` — PASS
  - `10` — PASS_WITH_KNOWN_DEBT
  - `20` — FAIL_NEW_ISSUE
  - `30` — FAIL_INFRA
- Never use `exit 1` directly — use the named constants.
- Prefer `ci::log::*` functions over raw `echo` for structured output.
- Never mutate files outside of `ci/reports/` and `ci/artifacts/`.
- Annotate all shellcheck disables with a comment explaining why.

## Testing Requirements

- Every new check must have at least one bats test.
- Tests that require unavailable tools must use `skip` gracefully.
- The self-test suite (`ci/self-test.sh`) must pass before submitting a PR.
- Run `make lint-ci` to validate script syntax before submitting.

## Submitting PRs

1. Fork the repository.
2. Create a feature branch: `git checkout -b feat/my-check`.
3. Make your changes.
4. Run `make verify` and `make ci-self-test`.
5. Commit using [Conventional Commits](https://www.conventionalcommits.org/): `feat: add my-check`.
6. Open a pull request against `main`.
