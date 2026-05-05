# CI Gate — Agent Implementation & Fix Plan

> **Agent Instruction:** Read this file fully before editing any code. Do not skip phases. Do not claim "done" without command evidence. Follow the safety rules in `AGENTS.md` and `CI_GATE_IMPLEMENTATION_PLAN_FOR_AGENTS.md`.

---

## 0. Agent Safety Rules (Non-Negotiable)

```text
1. NEVER run: git reset --hard, git clean -fd, git push --force, rm -rf
2. NEVER hide failures by deleting tests, suppressing output, or weakening assertions
3. NEVER auto-stage untracked files without explicit user confirmation
4. ALWAYS run bash -n on modified .sh files before claiming success
5. ALWAYS provide: files changed, commands run, pass/fail counts, debt status, next phase
6. Read existing files before editing. Do not overwrite without understanding context.
```

---

## Phase 0 — Baseline & Discovery (Do This First)

### Commands to run

```bash
git status --short
git branch --show-current
git rev-parse HEAD
find ci -maxdepth 3 -type f | sort
bash -n ci/lib/changeset.sh
bash -n ci/lib/cache.sh
bash -n ci/lib/affected.sh
bash -n ci/preflight.sh
bash -n ci/checks/node.sh
bash -n ci/checks/python.sh
bash -n ci/checks/security.sh
bash -n ci/checks/debt.sh
bash -n ci/ship.sh
```

### Expected output file

Create `ci/reports/baseline-current-state.md` documenting:
- Current branch, commit SHA, date/time
- List of all broken syntax issues found by `bash -n`
- List of unwired subsystems (cache, config, affected)
- Current known debt status from `ci/debt/known-failures.yml`

**Exit criteria:** Baseline report exists. No implementation files changed yet.

---

## Phase 1 — P0 Critical Syntax & Logic Fixes

These fix broken/truncated code that will crash or produce garbage. **Do Phase 1 completely before Phase 2.**

---

### 1.1 Fix `ci/lib/changeset.sh` — `emit_json` function (TRUNCATED)

**Problem:** The `emit_json` function is corrupted. It ends with:
```bash
done < "$CI_CHANGESET_JSON" <#
```
This is invalid bash. The heredoc for `all` mode is also mangled.

**Fix:** Replace the entire `emit_json` function with this corrected version:

```bash
# ci::changeset::emit_json – write structured JSON to CI_CHANGESET_JSON
ci::changeset::emit_json() {
  local out_dir
  out_dir="$(dirname "$CI_CHANGESET_JSON")"
  mkdir -p "$out_dir"

  local ts generated_languages="" generated_checks=""
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # Seed always-present checks
  generated_checks="$_CI_CHANGESET_ALWAYS_CHECKS"

  # Build the "files" JSON array
  local files_json="" first=1
  local status path lang file_checks checks_json

  if [ -n "$_CI_CHANGESET_FILES_RAW" ]; then
    while IFS=$'\t' read -r status path; do
      [ -z "$path" ] && continue
      # Rename status: R100\t... -> R
      case "$status" in R*) status="R" ;; esac

      ci::changeset::should_ignore "$path" && continue

      lang="$(ci::changeset::classify_file "$path")"
      generated_languages="$(ci::changeset::_add_unique "$generated_languages" "$lang")"

      # Compute checks triggered for this file
      file_checks="$(ci::changeset::_checks_for_language "$lang")"
      # Build checks_json array
      checks_json=""
      local ck ck_first=1
      for ck in $file_checks; do
        generated_checks="$(ci::changeset::_add_unique "$generated_checks" "$ck")"
        if [ "$ck_first" = "1" ]; then
          checks_json="\"${ck}\""
          ck_first=0
        else
          checks_json="${checks_json},\"${ck}\""
        fi
      done

      # Escape path for JSON
      local escaped_path="${path//\\/\\\\}"
      escaped_path="${escaped_path//\"/\\\"}"

      local file_entry
      file_entry="{\"path\":\"${escaped_path}\",\"language\":\"${lang}\",\"change_type\":\"${status}\",\"checks_triggered\":[${checks_json}]}"

      if [ "$first" = "1" ]; then
        files_json="$file_entry"
        first=0
      else
        files_json="${files_json},${file_entry}"
      fi
    done <<< "$_CI_CHANGESET_FILES_RAW"
  fi

  # Build languages JSON array
  local languages_json="" lfirst=1
  local lword
  for lword in $generated_languages; do
    if [ "$lfirst" = "1" ]; then
      languages_json="\"${lword}\""
      lfirst=0
    else
      languages_json="${languages_json},\"${lword}\""
    fi
  done

  # Build checks JSON array
  local checks_json_out="" cfirst=1
  local cword
  for cword in $generated_checks; do
    if [ "$cfirst" = "1" ]; then
      checks_json_out="\"${cword}\""
      cfirst=0
    else
      checks_json_out="${checks_json_out},\"${cword}\""
    fi
  done

  cat > "$CI_CHANGESET_JSON" <<EOF
{
  "mode": "$_CI_CHANGESET_MODE",
  "generated_at": "$ts",
  "languages": [${languages_json}],
  "checks": [${checks_json_out}],
  "files": [${files_json}]
}
EOF
}
```

**Validation:**
```bash
bash -n ci/lib/changeset.sh
```

---

### 1.2 Fix `ci/lib/cache.sh` — Remove garbage text inside function

**Problem:** Between `ci::cache::gc` and `ci::cache::hash_files`, there is literal garbage:
```bash
done < [file2 ...] – sha256 of concatenated file contents
ci::cache::hash_files() {
```

**Fix:** Remove the garbage line. The corrected transition should be:

```bash
  done < "$stale_list_file"
  rm -f "$stale_list_file"
}

# ci::cache::hash_files [file1 file2 ...] – sha256 of concatenated file contents
ci::cache::hash_files() {
```

**Validation:**
```bash
bash -n ci/lib/cache.sh
```

---

### 1.3 Fix `ci/lib/affected.sh` — Complete `get_affected_tests`

**Problem:** The function is truncated at the end:
```bash
done </dev/null || true
fi
done <
```

**Fix:** Replace the entire `ci::affected::get_affected_tests` function with:

```bash
# ci::affected::get_affected_tests [file1 file2 ...]
# Given a list of changed files, echoes newline-separated test patterns to run.
ci::affected::get_affected_tests() {
  local unique_patterns=""
  local f pattern found word

  for f in "$@"; do
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      # Deduplicate
      found=0
      for word in $unique_patterns; do
        [ "$word" = "$pattern" ] && found=1 && break
      done
      if [ "$found" -eq 0 ]; then
        if [ -n "$unique_patterns" ]; then
          unique_patterns="${unique_patterns}
${pattern}"
        else
          unique_patterns="$pattern"
        fi
      fi
    done < <(ci::affected::map_file_to_tests "$f")
  done

  printf '%s\n' "$unique_patterns"
}
```

**Also fix** the `map_file_to_tests` function — it uses `value="${line#*- source:}"` which is fragile. Replace the rule parsing block with:

```bash
      value="${line#*- source:}"
      value="${value#"${value%%[![:space:]]*}"}"  # ltrim
      value="${value#\"}"
      value="${value%\"}"
```

Wait — actually the existing code already has that. The main issue is `get_affected_tests` truncation. Just fix that function.

**Validation:**
```bash
bash -n ci/lib/affected.sh
```

---

### 1.4 Fix `ci/preflight.sh` — JUnit XML generation

**Problem:** The JUnit generation uses broken format strings:
```bash
printf ' \n' \
  "$MODE" "$_total_count" "$_fail_count" "$DURATION_SEC"
```
This prints spaces and newlines, not XML tags.

**Fix:** Replace the JUnit XML block in `preflight.sh` with:

```bash
# ---- junit.xml ----
JUNIT_XML="${CI_REPORT_DIR}/junit.xml"
{
  _pass_count="${#COMMANDS_PASSED[@]}"
  _fail_count="${#COMMANDS_FAILED[@]}"
  _total_count="${#COMMANDS_RUN[@]}"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<testsuites name="ci-gate-%s" tests="%d" failures="%d" time="%d">\n'     "$MODE" "$_total_count" "$_fail_count" "$DURATION_SEC"
  printf '  <testsuite name="ci-gate-%s" tests="%d" failures="%d" time="%d">\n'     "$MODE" "$_total_count" "$_fail_count" "$DURATION_SEC"
  _juidx=0
  while [ "$_juidx" -lt "${#_TIMING_LABELS[@]}" ]; do
    _julabel="${_TIMING_LABELS[$_juidx]}"
    _justart="${_TIMING_STARTS[$_juidx]}"
    _juend="${_TIMING_ENDS[$_juidx]}"
    _jurc="${_TIMING_RESULTS[$_juidx]}"
    _judur=$(( _juend - _justart ))
    if [ "$_jurc" -eq 0 ] || [ "$_jurc" -eq 10 ]; then
      printf '    <testcase name="%s" time="%d"/>\n' "$_julabel" "$_judur"
    else
      printf '    <testcase name="%s" time="%d">\n' "$_julabel" "$_judur"
      printf '      <failure message="Check %s failed with exit code %d"/>\n' "$_julabel" "$_jurc"
      printf '    </testcase>\n'
    fi
    _juidx=$(( _juidx + 1 ))
  done
  printf '  </testsuite>\n'
  printf '</testsuites>\n'
} > "$JUNIT_XML"
```

**Validation:**
```bash
bash -n ci/preflight.sh
```

---

### 1.5 Fix `ci/preflight.sh` — HTML dashboard structure

**Problem:** The HTML output lacks `<!DOCTYPE html>`, `<html>`, `<head>`, `<body>`, or `<table>` wrappers.

**Fix:** Replace the HTML generation block with:

```bash
# ---- HTML dashboard (index.html) ----
INDEX_HTML="${CI_REPORT_DIR}/index.html"
{
  # Build check rows
  _html_rows=""
  _hridx=0
  while [ "$_hridx" -lt "${#_TIMING_LABELS[@]}" ]; do
    _hrlabel="${_TIMING_LABELS[$_hridx]}"
    _hrstart="${_TIMING_STARTS[$_hridx]}"
    _hrend="${_TIMING_ENDS[$_hridx]}"
    _hrrc="${_TIMING_RESULTS[$_hridx]}"
    _hrdur=$(( _hrend - _hrstart ))
    _hrstatus="$(ci::common::result_name "$_hrrc")"
    case "$_hrrc" in
      0) _hrclass="pass" ;;
      10) _hrclass="warn" ;;
      *) _hrclass="fail" ;;
    esac
    _log_file="${CI_REPORT_DIR}/${_hrlabel}.log"
    _log_content=""
    [ -f "$_log_file" ] && _log_content="$(sed \
      -e 's/&/\&amp;/g' \
      -e 's/</\&lt;/g' \
      -e 's/>/\&gt;/g' \
      -e 's/"/\&quot;/g' \
      -e "s/'/\&#39;/g" \
      "$_log_file" 2>/dev/null || true)"
    _html_rows="${_html_rows}<tr class=\"${_hrclass}\"><td>${_hrlabel}</td><td>${_hrstatus}</td><td>${_hrdur}s</td><td><details><summary>show log</summary><pre>${_log_content}</pre></details></td></tr>"
    _hridx=$(( _hridx + 1 ))
  done

  _res_class="pass"
  [ "$AGG_RESULT" -ne 0 ] && _res_class="fail"

  cat << ENDHTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CI Gate Report</title>
<style>
  body { font-family: system-ui, -apple-system, sans-serif; max-width: 960px; margin: 2rem auto; padding: 0 1rem; color: #333; }
  h1 { border-bottom: 2px solid #ddd; padding-bottom: .5rem; }
  table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
  th, td { text-align: left; padding: .5rem; border-bottom: 1px solid #eee; }
  th { background: #f5f5f5; }
  .pass { color: #2ea44f; }
  .warn { color: #d29922; }
  .fail { color: #cf222e; }
  .badge { display: inline-block; padding: .2rem .5rem; border-radius: 4px; font-size: .85rem; font-weight: 600; }
  .badge.pass { background: #dafbe1; }
  .badge.fail { background: #ffebe9; }
  pre { background: #f6f8fa; padding: 1rem; overflow-x: auto; font-size: .85rem; }
  details summary { cursor: pointer; color: #0969da; }
</style>
</head>
<body>
<h1>CI Gate Report</h1>
<p><strong>Mode:</strong> ${MODE} | <strong>Result:</strong> <span class="badge ${_res_class}">${FINAL_RESULT_NAME}</span> | <strong>Duration:</strong> ${DURATION_SEC}s</p>
<table>
<thead><tr><th>Check</th><th>Status</th><th>Duration</th><th>Log</th></tr></thead>
<tbody>
${_html_rows}
</tbody>
</table>
<h2>Changed Files</h2>
<pre>${CHANGED_FILES}</pre>
<h2>Next Action</h2>
<p>${NEXT_ACTION}</p>
</body>
</html>
ENDHTML
} > "$INDEX_HTML"
```

**Validation:**
```bash
bash -n ci/preflight.sh
```

---

### 1.6 Fix `ci/preflight.sh` — SARIF generation (minimal but valid)

**Problem:** SARIF only lists failed check names. No `physicalLocation`, no `ruleIndex`.

**Fix:** At minimum, add rule metadata so GitHub can ingest it. Replace the SARIF block:

```bash
# ---- sarif.json ----
SARIF_JSON="${CI_REPORT_DIR}/sarif.json"
{
  printf '{\n'
  printf '  "\$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",\n'
  printf '  "version": "2.1.0",\n'
  printf '  "runs": [{\n'
  printf '    "tool": {"driver": {"name": "ci-gate", "version": "1.0.0", "rules": ['
  _rule_first=1
  _saidx=0
  while [ "$_saidx" -lt "${#_TIMING_LABELS[@]}" ]; do
    _salabel="${_TIMING_LABELS[$_saidx]}"
    if [ "$_rule_first" = "1" ]; then
      printf '\n'
      _rule_first=0
    else
      printf ',\n'
    fi
    printf '      {"id":"%s","name":"%s","shortDescription":{"text":"CI check %s"}}' "$_salabel" "$_salabel" "$_salabel"
    _saidx=$(( _saidx + 1 ))
  done
  if [ "$_rule_first" = "0" ]; then
    printf '\n    '
  fi
  printf ']}},\n'
  printf '    "results": ['
  _sarif_first=1
  _saidx=0
  while [ "$_saidx" -lt "${#_TIMING_LABELS[@]}" ]; do
    _salabel="${_TIMING_LABELS[$_saidx]}"
    _sarc="${_TIMING_RESULTS[$_saidx]}"
    if [ "$_sarc" -ne 0 ] && [ "$_sarc" -ne 10 ]; then
      if [ "$_sarif_first" = "1" ]; then
        printf '\n'
        _sarif_first=0
      else
        printf ',\n'
      fi
      printf '      {"ruleId":"%s","level":"error","message":{"text":"Check %s failed with exit code %d"},"locations":[{"physicalLocation":{"artifactLocation":{"uri":"ci/reports/%s.log"}}}]}'         "$_salabel" "$_salabel" "$_sarc" "$_salabel"
    fi
    _saidx=$(( _saidx + 1 ))
  done
  if [ "$_sarif_first" = "0" ]; then
    printf '\n    '
  fi
  printf ']\n'
  printf '  }]\n'
  printf '}\n'
} > "$SARIF_JSON"
```

**Validation:**
```bash
bash -n ci/preflight.sh
```

---

## Phase 2 — P1 Wire the Dead Subsystems

These subsystems exist but are never called. Wire them into `preflight.sh`.

---

### 2.1 Wire `ci/lib/cache.sh` into check execution

**Problem:** Cache system is fully implemented but no check uses it.

**Implementation:** In `ci/preflight.sh`, modify `run_check()` to use cache. Add after the `source` of libraries:

```bash
# In preflight.sh, after sourcing libraries, add:
ci::cache::init
```

Then wrap check execution in `run_check()` with cache logic. Find the `run_check` function and replace its body with:

```bash
run_check() {
  local label="$1"
  local script="$2"
  local check_start check_end
  check_start="$(date '+%s')"

  if _check_should_skip "$label"; then
    echo "Skipping [$label] (filtered)"
    return 0
  fi

  COMMANDS_RUN+=("$label")
  ci::report::append_log ""
  ci::report::append_log ">>> ${label} (${script})"

  # Compute cache key if cache is enabled and script supports it
  local cache_key="" cache_hit=0
  if [ "${CI_GATE_CACHE_ENABLED:-1}" = "1" ] && type ci::cache::key >/dev/null 2>&1; then
    local tool_ver="unknown"
    # Extract tool version from script name heuristic
    case "$label" in
      node) tool_ver="$(ci::cache::tool_version node)" ;;
      python) tool_ver="$(ci::cache::tool_version python3)" ;;
      *) tool_ver="bash-$(bash --version | head -1)" ;;
    esac
    local files_hash=""
    if [ -n "${_CI_CHANGESET_FILES_RAW:-}" ]; then
      files_hash="$(printf '%s' "$_CI_CHANGESET_FILES_RAW" | sha256sum | cut -d' ' -f1)"
    else
      files_hash="$(git rev-parse HEAD 2>/dev/null || echo 'none')"
    fi
    local config_hash=""
    if [ -f "ci/config/checks.yml" ]; then
      config_hash="$(ci::cache::_sha256_file ci/config/checks.yml)"
    else
      config_hash="none"
    fi
    cache_key="$(ci::cache::key "$label" "$tool_ver" "$files_hash" "$config_hash")"
    local cache_dest="${CI_REPORT_DIR}/.cache/${label}"
    if ci::cache::get "$cache_key" "$cache_dest"; then
      echo "  [cache hit] $label"
      cache_hit=1
      # Restore cached result
      if [ -f "$cache_dest/result.txt" ]; then
        local cached_rc
        cached_rc="$(cat "$cache_dest/result.txt")"
        check_end="$(date '+%s')"
        _collect_check_result "$label" "$cached_rc" "" "$check_start" "$check_end"
        return 0
      fi
    fi
  fi

  local output="" rc=0
  set +e
  output=$("$script" 2>&1)
  rc=$?
  set -e

  check_end="$(date '+%s')"

  # Store result in cache
  if [ "$cache_hit" = "0" ] && [ -n "$cache_key" ]; then
    local cache_dest="${CI_REPORT_DIR}/.cache/${label}"
    mkdir -p "$cache_dest"
    printf '%d' "$rc" > "$cache_dest/result.txt"
    printf '%s' "$output" > "$cache_dest/output.txt"
    ci::cache::put "$cache_key" "$cache_dest"
  fi

  _collect_check_result "$label" "$rc" "$output" "$check_start" "$check_end"
}
```

**Also add to `ci/config/gate.yml`** (or create if missing):
```yaml
# Add this key if not present
cache_enabled: true
```

**Validation:**
```bash
bash -n ci/preflight.sh
./ci/preflight.sh --mode quick
# Verify ci/reports/.cache/ is created and populated
```

---

### 2.2 Wire `ci/config/gate.yml` into preflight

**Problem:** `gate.yml` is never read. `preflight.sh` hardcodes all behavior.

**Implementation:** Create a config loader in `ci/lib/common.sh` or `ci/preflight.sh`. Add after library sourcing:

```bash
# Load gate configuration
ci::common::load_gate_config() {
  local config_file="${1:-ci/config/gate.yml}"
  [ -f "$config_file" ] || return 0
  # Simple grep-based parser for key: value pairs
  local key val
  while IFS= read -r line; do
    # Skip comments and blank lines
    case "$line" in
      ''|'#'*) continue ;;
    esac
    # Extract key: value
    key="${line%%:*}"
    val="${line#*:}"
    key="$(echo "$key" | tr -d ' ')"
    val="$(echo "$val" | sed 's/^[[:space:]]*//')"
    case "$key" in
      parallelism)
        [ -n "$val" ] && [ "$val" != "0" ] && CI_GATE_PARALLEL="$val"
        ;;
      default_timeout_sec)
        [ -n "$val" ] && CI_GATE_TIMEOUT="$val"
        ;;
      pre_commit_budget_sec)
        [ -n "$val" ] && CI_GATE_PRE_COMMIT_BUDGET="$val"
        ;;
      pre_push_budget_sec)
        [ -n "$val" ] && CI_GATE_PRE_PUSH_BUDGET="$val"
        ;;
      fail_fast_on_blocker)
        [ "$val" = "true" ] && CI_GATE_FAIL_FAST=1 || CI_GATE_FAIL_FAST=0
        ;;
      incremental)
        [ "$val" = "true" ] && CI_GATE_INCREMENTAL=1 || CI_GATE_INCREMENTAL=0
        ;;
      cache_enabled)
        [ "$val" = "true" ] && CI_GATE_CACHE_ENABLED=1 || CI_GATE_CACHE_ENABLED=0
        ;;
      verbose)
        [ "$val" = "true" ] && CI_GATE_VERBOSE=1 || CI_GATE_VERBOSE=0
        ;;
    esac
  done < "$config_file"
}
```

Call it in `preflight.sh`:
```bash
ci::common::load_gate_config "ci/config/gate.yml"
```

**Validation:**
```bash
bash -n ci/lib/common.sh
bash -n ci/preflight.sh
```

---

### 2.3 Wire `ci/config/checks.yml` into check dispatch

**Problem:** `checks.yml` exists but `preflight.sh` hardcodes check phases.

**Implementation:** For now, add a check skipper that reads `checks.yml`. In `preflight.sh`, replace `_check_should_skip` with:

```bash
_check_should_skip() {
  local label="$1"
  # If checks.yml exists, respect enabled: false
  if [ -f "ci/config/checks.yml" ]; then
    local in_check=0 check_id="" enabled="true"
    while IFS= read -r line; do
      case "$line" in
        '#'*|'') continue ;;
      esac
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*id:[[:space:]]*(.*)$ ]]; then
        in_check=1
        check_id="${BASH_REMATCH[1]}"
        check_id="$(echo "$check_id" | tr -d ' ' | tr -d '"')"
        enabled="true"
      fi
      if [ "$in_check" = "1" ] && [[ "$line" =~ ^[[:space:]]*enabled:[[:space:]]*(.*)$ ]]; then
        enabled="${BASH_REMATCH[1]}"
        enabled="$(echo "$enabled" | tr -d ' ')"
      fi
      if [ "$in_check" = "1" ] && [ "$check_id" = "$label" ] && [ "$enabled" = "false" ]; then
        return 0  # skip
      fi
    done < "ci/config/checks.yml"
  fi
  # Also skip by changeset if incremental and no relevant files changed
  if [ "${CI_GATE_INCREMENTAL:-1}" = "1" ] && [ -n "${_CI_CHANGESET_CHECKS:-}" ]; then
    local found=0
    local ck
    for ck in $_CI_CHANGESET_CHECKS; do
      [ "$ck" = "$label" ] && found=1 && break
    done
    if [ "$found" = "0" ]; then
      # Always-run checks are never skipped by changeset
      case "$label" in
        git-safety|changed-files|security|debt) ;;
        *) return 0 ;;
      esac
    fi
  fi
  return 1
}
```

**Validation:**
```bash
bash -n ci/preflight.sh
```

---

### 2.4 Wire `ci/lib/affected.sh` into test execution

**Problem:** `affected.sh` is fixed in Phase 1, but `tests.sh` and `preflight.sh` never call it.

**Implementation:** In `ci/checks/tests.sh`, before running tests, compute affected tests:

```bash
# In tests.sh, after sourcing libraries, add:
AFFECTED_TESTS=""
if type ci::affected::get_affected_tests >/dev/null 2>&1 && [ -f "ci/config/affected.yml" ]; then
  local changed_files=""
  changed_files="$(git diff --cached --name-only 2>/dev/null || git diff --name-only 2>/dev/null || true)"
  if [ -n "$changed_files" ]; then
    AFFECTED_TESTS="$(printf '%s' "$changed_files" | xargs ci::affected::get_affected_tests 2>/dev/null || true)"
  fi
fi
```

Then in each `tests::run_*` function, if `AFFECTED_TESTS` is set and the runner supports file filtering, pass it. For pytest:

```bash
# In tests::run_python, replace the pytest call with:
if [ -n "$AFFECTED_TESTS" ]; then
  pytest --junitxml="$JUNIT_DIR/python.xml" $(printf '%s' "$AFFECTED_TESTS" | tr '\n' ' ') || rc=$?
else
  pytest --junitxml="$JUNIT_DIR/python.xml" || rc=$?
fi
```

For jest:
```bash
# In tests::run_js:
if [ -n "$AFFECTED_TESTS" ]; then
  jest --ci --testPathPattern="$(printf '%s' "$AFFECTED_TESTS" | tr '\n' '|')" || rc=$?
else
  jest --ci || rc=$?
fi
```

**Validation:**
```bash
bash -n ci/checks/tests.sh
```

---

### 2.5 Add timeout enforcement to `ci/lib/runner.sh`

**Problem:** `timeout_sec` is in manifest but runner ignores it.

**Implementation:** In `ci::runner::submit`, add timeout wrapper:

```bash
# In runner.sh, inside ci::runner::submit, replace the background job launch with:
  # Determine timeout
  local timeout_cmd=""
  if [ -n "${CI_GATE_TIMEOUT:-}" ] && [ "${CI_GATE_TIMEOUT}" != "0" ]; then
    if command -v timeout >/dev/null 2>&1; then
      timeout_cmd="timeout ${CI_GATE_TIMEOUT}"
    elif command -v gtimeout >/dev/null 2>&1; then
      timeout_cmd="gtimeout ${CI_GATE_TIMEOUT}"
    fi
  fi

  # Launch background job
  printf '%s' "$(ci::runner::_epoch)" > "$start_file"
  (
    trap - ERR
    set +e
    if [ -n "$timeout_cmd" ]; then
      $timeout_cmd "$check_script" ${args[@]+"${args[@]}"} > "$log_file" 2>&1
    else
      "$check_script" ${args[@]+"${args[@]}"} > "$log_file" 2>&1
    fi
    ec=$?
    printf '%d' "$ec" > "${_CI_RUNNER_JOBS_DIR}/${job_id}.rc"
    printf '%s' "$(ci::runner::_epoch)" > "${_CI_RUNNER_JOBS_DIR}/${job_id}.end"
  ) &
```

**Validation:**
```bash
bash -n ci/lib/runner.sh
```

---

### 2.6 Add dependency install caching to `node.sh` and `python.sh`

**Problem:** `npm ci` and `pip install` run on every gate invocation.

**Implementation for node.sh:** Before installing, check if `node_modules` exists and lockfile hash matches:

```bash
# In node.sh, after detecting MANAGER, before install, add:
LOCKFILE=""
case "$MANAGER" in
  pnpm) LOCKFILE="pnpm-lock.yaml" ;;
  npm) LOCKFILE="package-lock.json" ;;
  yarn) LOCKFILE="yarn.lock" ;;
  bun) LOCKFILE="bun.lockb" ;;
esac

SKIP_INSTALL=0
if [ -n "$LOCKFILE" ] && [ -d "node_modules" ] && [ -f ".ci-gate/node_modules.hash" ]; then
  CURRENT_HASH="$(sha256sum "$LOCKFILE" | cut -d' ' -f1)"
  CACHED_HASH="$(cat .ci-gate/node_modules.hash)"
  if [ "$CURRENT_HASH" = "$CACHED_HASH" ]; then
    echo "node_modules up to date. Skipping install."
    SKIP_INSTALL=1
  fi
fi

if [ "$SKIP_INSTALL" = "0" ]; then
  # ... existing install block ...
  mkdir -p .ci-gate
  sha256sum "$LOCKFILE" | cut -d' ' -f1 > .ci-gate/node_modules.hash
fi
```

**Implementation for python.sh:** Similarly cache `.venv` state:

```bash
# In python.sh, after detecting requirements.txt, before install, add:
SKIP_INSTALL=0
if [ -f "requirements.txt" ] && [ -d ".venv" ] && [ -f ".ci-gate/venv.hash" ]; then
  CURRENT_HASH="$(sha256sum requirements.txt | cut -d' ' -f1)"
  CACHED_HASH="$(cat .ci-gate/venv.hash)"
  if [ "$CURRENT_HASH" = "$CACHED_HASH" ]; then
    echo ".venv up to date. Skipping install."
    SKIP_INSTALL=1
  fi
fi

if [ "$SKIP_INSTALL" = "0" ] && [ -f "requirements.txt" ]; then
  # ... existing install block ...
  mkdir -p .ci-gate
  sha256sum requirements.txt | cut -d' ' -f1 > .ci-gate/venv.hash
fi
```

**Validation:**
```bash
bash -n ci/checks/node.sh
bash -n ci/checks/python.sh
```

---

## Phase 3 — P2 Elite Features & Polish

Do **not** start Phase 3 until Phase 1 and Phase 2 are fully validated.

---

### 3.1 Create GitHub Actions Bridge

Create `.github/workflows/ci-gate.yml`:

```yaml
name: CI Gate Mirror

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  ci-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run CI Gate
        run: |
          ./ci/preflight.sh --mode full
      - name: Upload reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ci-gate-reports
          path: ci/reports/
      - name: Upload SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: ci/reports/sarif.json
          category: ci-gate
```

**Validation:** Push to a branch and verify the workflow runs.

---

### 3.2 Add `make ci-watch` target

Add to `Makefile`:

```makefile
ci-watch:
	@which fswatch >/dev/null 2>&1 || (echo "fswatch not installed. Run: brew install fswatch" && exit 1)
	@echo "Watching for changes... (Ctrl-C to stop)"
	@fswatch -o . | while read; do 		echo "\n[$(shell date +%H:%M:%S)] Change detected. Running quick gate..."; 		./ci/preflight.sh --mode quick || true; 	done
```

**Validation:**
```bash
make -n ci-watch
```

---

### 3.3 Add performance budget enforcement

In `ci/preflight.sh`, after computing `DURATION_SEC`, add:

```bash
# Performance budget check
BUDGET_EXCEEDED=0
if [ "$MODE" = "quick" ] && [ -n "${CI_GATE_PRE_COMMIT_BUDGET:-}" ]; then
  if [ "$DURATION_SEC" -gt "$CI_GATE_PRE_COMMIT_BUDGET" ]; then
    echo "WARNING: Quick mode budget exceeded: ${DURATION_SEC}s > ${CI_GATE_PRE_COMMIT_BUDGET}s"
    BUDGET_EXCEEDED=1
  fi
fi
if [ "$MODE" = "ship" ] && [ -n "${CI_GATE_PRE_PUSH_BUDGET:-}" ]; then
  if [ "$DURATION_SEC" -gt "$CI_GATE_PRE_PUSH_BUDGET" ]; then
    echo "WARNING: Ship mode budget exceeded: ${DURATION_SEC}s > ${CI_GATE_PRE_PUSH_BUDGET}s"
    BUDGET_EXCEEDED=1
  fi
fi
```

**Validation:**
```bash
bash -n ci/preflight.sh
```

---

### 3.4 Add flaky test detection script

Create `ci/checks/flaky.sh`:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/ci/lib/common.sh"

ci::common::section "Check: flaky test detection"

FLAKY_RUNS="${CI_GATE_FLAKY_RUNS:-3}"
echo "Running affected tests ${FLAKY_RUNS} times to detect flakes..."

# Run tests multiple times, capture failing test names
# This is a stub — expand with actual test runner integration
echo "Flaky detection: stub (implement per-project test runner integration)"
exit "$CI_RESULT_PASS"
```

Add to `Makefile`:
```makefile
ci-flaky:
	./ci/checks/flaky.sh
```

**Validation:**
```bash
bash -n ci/checks/flaky.sh
```

---

## Phase 4 — Validation Matrix

Before claiming completion, run every applicable command:

### Syntax validation
```bash
bash -n ci/*.sh
bash -n ci/checks/*.sh
bash -n ci/lib/*.sh
bash -n ci/hook-dispatch.sh
bash -n .githooks/*
```

### Self-test
```bash
make ci-self-test
```

### Mode validation
```bash
make ci-quick
make ci-debt
make ci-ship
make ci-full
```

### Report validation
Confirm these files are generated and well-formed:
```text
ci/reports/summary.md        (readable markdown)
ci/reports/summary.json      (valid JSON)
ci/reports/trace.json        (valid Chrome trace format)
ci/reports/junit.xml         (valid JUnit XML)
ci/reports/sarif.json        (valid SARIF 2.1.0)
ci/reports/index.html        (valid HTML5 with CSS)
```

Validate with:
```bash
python3 -c "import json; json.load(open('ci/reports/summary.json'))"
python3 -c "import xml.etree.ElementTree as ET; ET.parse('ci/reports/junit.xml')"
```

### Cache validation
```bash
ls -la ci/reports/.cache/ 2>/dev/null || echo "Cache dir not created — check Phase 2.1"
```

---

## Required Final Agent Report Format

At the end of each phase, report exactly:

```text
Phase completed: [phase name]

Files changed:
- [file path]

Commands run:
- [command]: [result]

Validation results:
- bash -n [file]: [OK/FAIL]
- [functional test]: [OK/FAIL]

Known debt status:
- unchanged / increased / reduced / not checked with reason

New issue status:
- none / found with details

Final result:
- PASS / PASS_WITH_KNOWN_DEBT / FAIL_NEW_ISSUE / FAIL_INFRA

Risks / gaps:
- [list remaining risks]

Next recommended phase:
- [phase name]
```

---

## Emergency Stop Conditions

Stop and report immediately if:
- `bash -n` fails on any modified file
- Files appear unexpectedly deleted
- Secrets are detected in modified code
- Commands require destructive actions
- Debt increased and cause is unclear
- CI scripts would push or deploy automatically

---

*Generated from full source audit. Every file, function, and wire was inspected.*
