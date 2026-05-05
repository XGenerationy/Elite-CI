# CI Gate Checks Reference

> Auto-generated from `ci/checks/manifest.yml`. Run `make docs` to regenerate.

## Check Catalog

| ID | Description | Languages | Tool | Severity | Phase | Pre-commit |
|----|-------------|-----------|------|----------|-------|------------|
| `git-safety` | Whitespace, conflict markers, sensitive file detection | all | `-` | blocker | hygiene | yes |
| `commit-hygiene` | Conventional commit lint, max diff size, forbidden files | all | `-` | blocker | hygiene | yes |
| `branch-protection` | Local enforcement of branch protection rules | all | `-` | blocker | hygiene | no |
| `secrets` | Secret/credential scanning with gitleaks + regex fallback | all | `-` | blocker | security | yes |
| `lint-shell` | Shell script linting with shellcheck | shell | `shellcheck` | blocker | lint | yes |
| `lint-js` | JavaScript/TypeScript linting with eslint | javascript | `eslint` | blocker | lint | yes |
| `lint-python` | Python linting with ruff/flake8 | python | `ruff` | blocker | lint | yes |
| `lint-go` | Go linting with golangci-lint | go | `golangci-lint` | blocker | lint | yes |
| `lint-docker` | Dockerfile linting with hadolint | dockerfile | `hadolint` | warning | lint | yes |
| `lint-yaml` | YAML linting with yamllint | yaml | `yamllint` | warning | lint | yes |
| `format-shell` | Shell formatting check with shfmt | shell | `shfmt` | blocker | format | yes |
| `format-js` | JS/TS formatting check with prettier | javascript | `prettier` | blocker | format | yes |
| `format-python` | Python formatting check with black/ruff format | python | `black` | blocker | format | yes |
| `format-go` | Go formatting check with gofmt | go | `gofmt` | blocker | format | yes |
| `typecheck-js` | TypeScript type checking with tsc | javascript | `tsc` | blocker | typecheck | no |
| `typecheck-python` | Python type checking with mypy/pyright | python | `mypy` | warning | typecheck | no |
| `typecheck-go` | Go vet | go | `go` | blocker | typecheck | no |
| `tests-js` | JavaScript tests with jest/vitest | javascript | `-` | blocker | tests | no |
| `tests-python` | Python tests with pytest | python | `-` | blocker | tests | no |
| `tests-go` | Go tests | go | `-` | blocker | tests | no |
| `tests-shell` | Shell tests with bats | shell | `bats` | blocker | tests | no |
| `sast` | SAST scanning with semgrep/bandit/gosec | all | `-` | blocker | security | no |
| `supply-chain` | Lockfile integrity and drift detection | all | `-` | warning | security | no |
| `license` | License compatibility checking | all | `-` | warning | security | no |
| `container` | Container image security scanning | dockerfile | `-` | warning | security | no |
| `iac` | Infrastructure-as-Code scanning with tflint/checkov | terraform | `-` | warning | security | no |
