# Kimi Code — Work Order: CI Gate Remaining Fixes

> **Scope:** Fix all P0 critical syntax bugs + wire all P1 dead subsystems.  
> **Constraint:** Do NOT add new features. Do NOT modify README. Do NOT change existing behavior. Only fix and wire what is broken or dead.  
> **Validation:** Every modified file must pass `bash -n` before you say "done".

---

## STOP — Read This First

Before touching any file:
1. Read `AGENTS.md` in the repo root.
2. Read this entire document.
3. Run `bash -n` on every `.sh` file in `ci/` to establish baseline.
4. Report baseline results before starting fixes.

You are NOT allowed to:
- Add new features (no new checks, no new Makefile targets, no new workflows)
- Modify `README.md`
- Change result codes in `ci/lib/common.sh`
- Delete tests or weaken assertions
- Run `git reset --hard`, `git clean -fd`, `rm -rf`, or `git push --force`
- Auto-commit or auto-push
- Claim "done" without command evidence

---

## Phase A — P0 Critical Syntax Fixes (Do These First)

These 5 files have broken syntax that will crash at runtime. Fix them before anything else.

---

### A.1 Fix `ci/lib/changeset.sh` — `emit_json` function (TRUNCATED)

**Problem:** The function ends with garbage:
```bash
done < "$CI_CHANGESET_JSON" <#
```
This is invalid bash. The `all` mode heredoc is also mangled:
```bash
done </dev/null)
EOF
```

**Fix:** Replace the entire `ci::changeset::emit_json` function (from the line `ci::changeset::emit_json() {` to the end of the function) with this exact code:

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

### A.2 Fix `ci/lib/changeset.sh` — `all` mode heredoc in `detect()`

**Problem:** The `all` mode in `ci::changeset::detect` has:
```bash
done </dev/null)
EOF
```

**Fix:** Replace the `all` case block with:

```bash
  all)
    # Full tree scan – emit all tracked files as "M\tpath"
    local f
    while IFS= read -r f; do
      if [ -n "$raw_entries" ]; then
        raw_entries="${raw_entries}
M\t${f}"
      else
        raw_entries="M\t${f}"
      fi
    done < <(git ls-files 2>/dev/null || true)
    ;;
```

**Validation:**
```bash
bash -n ci/lib/changeset.sh
```

---

### A.3 Fix `ci/lib/cache.sh` — Remove garbage text inside function body

**Problem:** Between `ci::cache::gc` and `ci::cache::hash_files`, there is literal garbage:
```bash
done < [file2 ...] – sha256 of concatenated file contents
ci::cache::hash_files() {
```

**Fix:** Remove the garbage line. The transition should be:

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

### A.4 Fix `ci/lib/affected.sh` — Complete `get_affected_tests`

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

**Validation:**
```bash
bash -n ci/lib/affected.sh
```

---

### A.5 Fix `ci/preflight.sh` — JUnit XML generation

**Problem:** The JUnit block uses broken format strings:
```bash
printf ' \n' \
  "$MODE" "$_total_count" "$_fail_count" "$DURATION_SEC"
```
This prints spaces and newlines, not XML tags.

**Fix:** Replace the entire JUnit XML block (from the comment `# ---- junit.xml ----` to the closing `} > "$JUNIT_XML"`) with:

```bash
# ---- junit.xml ----
JUNIT_XML="${CI_REPORT_DIR}/junit.xml"
{
  _pass_count="${#COMMANDS_PASSED[@]}"
  _fail_count="${#COMMANDS_FAILED[@]}"
  _total_count="${#COMMANDS_RUN[@]}"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<testsuites name="ci-gate-%s" tests="%d" failures="%d" time="%d">\n' \
    "$MODE" "$_total_count" "$_fail_count" "$DURATION_SEC"
  printf '  <testsuite name="ci-gate-%s" tests="%d" failures="%d" time="%d">\n' \
    "$MODE" "$_total_count" "$_fail_count" "$DURATION_SEC"
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

### A.6 Fix `ci/preflight.sh` — HTML dashboard structure

**Problem:** The HTML output lacks `<!DOCTYPE html>`, `<html>`, `<head>`, `<body>`, or `<table>`. Escaping is broken (`s/&/\&/g` instead of `&amp;`).

**Fix:** Replace the entire HTML block (from `# ---- HTML dashboard (index.html) ----` to `} > "$INDEX_HTML"`) with:

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

## Phase B — P1 Wire Dead Subsystems (Do After Phase A)

These subsystems exist but are ignored. Wire them into `preflight.sh` without changing existing defaults.

---

### B.1 Wire `ci/config/checks.yml` into `_check_should_skip`

**Problem:** `preflight.sh` has a hardcoded `_check_should_skip` function. `checks.yml` is never read.

**Fix:** Replace the `_check_should_skip` function in `preflight.sh` with:

```bash
_check_should_skip() {
  local label="$1"

  # 1. Respect checks.yml enabled: false
  if [ -f "ci/config/checks.yml" ]; then
    local in_check=0 check_id="" enabled="true"
    while IFS= read -r line; do
      case "$line" in
        ''|'#'*) continue ;;
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

  # 2. Skip by changeset if incremental and no relevant files changed
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

### B.2 Wire `ci/config/thresholds.yml` into coverage/complexity enforcement

**Problem:** `thresholds.yml` exists but is never read.

**Fix:** Add a thresholds loader in `ci/lib/common.sh` (after `load_gate_config`):

```bash
# ci::common::load_thresholds_config – simple parser for thresholds.yml
ci::common::load_thresholds_config() {
  local config_file="${1:-ci/config/thresholds.yml}"
  [ -f "$config_file" ] || return 0
  local key val
  while IFS= read -r line; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    key="${line%%:*}"
    val="${line#*:}"
    key="$(printf '%s' "$key" | tr -d ' ')"
    val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//')"
    case "$key" in
      coverage_min_percent)
        [ -n "$val" ] && export CI_GATE_COVERAGE_MIN="$val"
        ;;
      complexity_max)
        [ -n "$val" ] && export CI_GATE_COMPLEXITY_MAX="$val"
        ;;
      bundle_size_max)
        [ -n "$val" ] && export CI_GATE_BUNDLE_SIZE_MAX="$val"
        ;;
    esac
  done < "$config_file"
}
```

Then call it in `preflight.sh` after `load_gate_config`:
```bash
ci::common::load_thresholds_config "ci/config/thresholds.yml"
```

**Validation:**
```bash
bash -n ci/lib/common.sh
bash -n ci/preflight.sh
```

---

### B.3 Wire `ci/config/lanes.conf` into `run_mode()`

**Problem:** Phase grouping in `run_mode()` is hardcoded. `lanes.conf` is never read.

**Fix:** For now, add a comment and a fallback that reads `lanes.conf` if it exists, but keep the existing hardcoded behavior as default. Replace `run_mode()` with:

```bash
run_mode() {
  # If lanes.conf exists and CI_GATE_USE_LANES=1, read it. Otherwise use hardcoded defaults.
  if [ "${CI_GATE_USE_LANES:-0}" = "1" ] && [ -f "ci/config/lanes.conf" ]; then
    local lane_id="" lane_checks=""
    while IFS='|' read -r lane_id _lane_name _lane_cmd lane_checks _lane_blocking _lane_desc; do
      lane_id="$(echo "$lane_id" | tr -d ' ')"
      [ -z "$lane_id" ] && continue
      case "$lane_id" in '#') continue ;; esac
      local check_entries=""
      local chk
      for chk in $lane_checks; do
        local script_path="./ci/checks/${chk}.sh"
        [ -f "$script_path" ] || script_path="./ci/checks/${chk}"
        if [ -n "$check_entries" ]; then
          check_entries="${check_entries} "${chk}:${script_path}""
        else
          check_entries=""${chk}:${script_path}""
        fi
      done
      eval "run_phase $check_entries"
    done < "ci/config/lanes.conf"
    return 0
  fi

  case "$MODE" in
    quick)
      run_common_checks
      ;;
    full|ship)
      run_full_or_ship_checks
      ;;
    debt)
      run_phase "git-safety:./ci/checks/git-safety.sh"
      run_phase "debt:./ci/checks/debt.sh"
      ;;
    *)
      echo "Unhandled preflight mode: $MODE"
      INFRA_ISSUE_SEEN=1
      COMMANDS_FAILED+=("mode-dispatch")
      AGG_RESULT="$(ci::common::merge_results "$AGG_RESULT" "$CI_RESULT_FAIL_INFRA")"
      ;;
  esac
}
```

**Validation:**
```bash
bash -n ci/preflight.sh
```

---

### B.4 Wire `ci/config/path-rules.conf` into `changeset.sh`

**Problem:** `changeset.sh` hardcodes `_CI_CHANGESET_AUTO_IGNORE`. `path-rules.conf` is never read.

**Fix:** In `ci::changeset::should_ignore`, after the `.ci-gateignore` block, add:

```bash
  # path-rules.conf patterns (if present)
  if [ -f "ci/config/path-rules.conf" ]; then
    local pr_pattern
    while IFS='|' read -r pr_pattern _pr_area _pr_risk _pr_lanes _pr_full _pr_reason; do
      pr_pattern="$(echo "$pr_pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -z "$pr_pattern" ] && continue
      case "$pr_pattern" in '#') continue ;; esac
      # shellcheck disable=SC2254
      case "$path" in
        $pr_pattern) return 0 ;;
      esac
    done < "ci/config/path-rules.conf"
  fi
```

**Validation:**
```bash
bash -n ci/lib/changeset.sh
```

---

### B.5 Wire `ci/impact.sh` and `ci/test-plan.sh` stubs to real libraries

**Problem:** `ci/impact.sh` is 400 bytes and ignores `ci/lib/impact.sh` (11.6KB). `ci/test-plan.sh` is 492 bytes and ignores `ci/lib/test-plan.sh` (7.8KB).

**Fix for `ci/impact.sh`:** Replace the entire file with:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/ci/lib/common.sh"
source "$ROOT_DIR/ci/lib/impact.sh"

ci::impact::generate "$@"
```

**Fix for `ci/test-plan.sh`:** Replace the entire file with:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/ci/lib/common.sh"
source "$ROOT_DIR/ci/lib/impact.sh"
source "$ROOT_DIR/ci/lib/test-plan.sh"

ci::test_plan::generate "$@"
```

**Validation:**
```bash
bash -n ci/impact.sh
bash -n ci/test-plan.sh
```

---

## Phase C — Final Validation (Do This Last)

Run every applicable command and report results:

```bash
# 1. Syntax validation for ALL .sh files
for f in ci/*.sh ci/checks/*.sh ci/lib/*.sh ci/hook-dispatch.sh .githooks/*; do
  [ -f "$f" ] && bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"
done

# 2. Config file validation
python3 -c "import yaml; yaml.safe_load(open('ci/config/gate.yml'))" 2>/dev/null && echo "OK: gate.yml" || echo "FAIL: gate.yml"
python3 -c "import yaml; yaml.safe_load(open('ci/config/checks.yml'))" 2>/dev/null && echo "OK: checks.yml" || echo "FAIL: checks.yml"
python3 -c "import yaml; yaml.safe_load(open('ci/config/thresholds.yml'))" 2>/dev/null && echo "OK: thresholds.yml" || echo "FAIL: thresholds.yml"
python3 -c "import yaml; yaml.safe_load(open('ci/config/cache.yml'))" 2>/dev/null && echo "OK: cache.yml" || echo "FAIL: cache.yml"
python3 -c "import yaml; yaml.safe_load(open('ci/debt/known-failures.yml'))" 2>/dev/null && echo "OK: known-failures.yml" || echo "FAIL: known-failures.yml"

# 3. Self-test
make ci-self-test

# 4. Quick mode smoke test
make ci-quick

# 5. Verify reports are well-formed
python3 -c "import json; json.load(open('ci/reports/summary.json'))" 2>/dev/null && echo "OK: summary.json" || echo "FAIL: summary.json"
python3 -c "import json; json.load(open('ci/reports/trace.json'))" 2>/dev/null && echo "OK: trace.json" || echo "FAIL: trace.json"
python3 -c "import xml.etree.ElementTree as ET; ET.parse('ci/reports/junit.xml')" 2>/dev/null && echo "OK: junit.xml" || echo "FAIL: junit.xml"
python3 -c "import json; json.load(open('ci/reports/sarif.json'))" 2>/dev/null && echo "OK: sarif.json" || echo "FAIL: sarif.json"
```

---

## Required Completion Report Format

At the end, report exactly:

```text
Phase completed: A + B + C

Files changed:
- [list every file modified]

Commands run:
- [command]: [exit code] [output snippet]

Validation results:
- bash -n [file]: OK/FAIL
- [functional test]: OK/FAIL

Known debt status:
- unchanged / checked

New issue status:
- none

Final result:
- PASS / FAIL

Risks / gaps:
- [list any remaining issues]

Next recommended phase:
- [none — all planned fixes complete]
```

---

*Work order generated from full source audit. Every file, function, and wire was inspected.*
