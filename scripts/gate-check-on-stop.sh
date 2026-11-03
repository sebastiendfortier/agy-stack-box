#!/usr/bin/env bash
# Stop hook: enforce GATES.md before the agent is allowed to stop.
#
# When the agent finishes a turn and is about to stop, this hook runs every
# gate listed in GATES.md (the CHECK/EXPECT pairs). If all runnable gates pass
# the stop is allowed; if any gate fails, the stop is blocked and the failing
# gates are injected back into the loop so the agent has to address them.
#
# A gate is skipped (not failed) when it carries "SKIP: 1" — used for gates
# whose runner lives outside the repo and is therefore not reproducible here.
# GATES.md is a repo-local artifact (it carries machine-specific EVIDENCE), so
# when it is absent the hook simply allows the stop.
#
# Contract (see builtin agy-customizations docs/hooks.md): the agent sends the
# stop event as JSON on stdin; we answer with a JSON decision on stdout.
set -euo pipefail

allow() { echo '{"decision":"allow"}'; exit 0; }
block() {
  # $1 = reason text. Block the stop and hand the reason back to the agent.
  local reason="$1"
  jq -cn --arg r "$reason" '{decision:"continue", reason:$r}'
  exit 0
}

command -v jq >/dev/null 2>&1 || allow

payload="$(cat || true)"

# Locate GATES.md: prefer the workspace path from the payload, then the repo
# root (the directory containing this script).
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gates=""
ws="$(jq -r '.workspacePaths[0] // empty' <<<"$payload" 2>/dev/null || true)"
for cand in "${ws:-}" "$repo_root"; do
  [[ -n "$cand" && -f "$cand/GATES.md" ]] && { gates="$cand/GATES.md"; break; }
done
[[ -n "$gates" ]] || allow

# Parse the gates. Each gate is a "- [ ] G<n>: title" line followed by
# indented CHECK / EXPECT / SKIP lines. Collected into parallel arrays.
re_header='^- \[( |x|X)\] (G[0-9]+):[[:space:]]*(.*)$'
re_check='^[[:space:]]+CHECK:[[:space:]]*(.*)$'
re_expect='^[[:space:]]+EXPECT:[[:space:]]*(.*)$'
re_skip='^[[:space:]]+SKIP:[[:space:]]*1'

declare -a g_id=() g_title=() g_check=() g_expect=() g_skip=()
while IFS= read -r line; do
  # New gate header.
  if [[ "$line" =~ $re_header ]]; then
    g_id+=("${BASH_REMATCH[2]}")
    g_title+=("${BASH_REMATCH[3]}")
    g_check+=("")
    g_expect+=("")
    g_skip+=("0")
    continue
  fi
  # Indented field lines belonging to the most recent gate.
  if [[ ${#g_id[@]} -gt 0 ]]; then
    if [[ "$line" =~ $re_check ]]; then
      g_check[-1]="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ $re_expect ]]; then
      g_expect[-1]="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ $re_skip ]]; then
      g_skip[-1]="1"
    fi
  fi
done < "$gates"

[[ ${#g_id[@]} -gt 0 ]] || allow

run_dir="$(cd "$(dirname "$gates")" && pwd)"
failed=()
skipped=0
for i in "${!g_id[@]}"; do
  check="${g_check[i]}"
  expect="${g_expect[i]}"
  [[ -n "$check" ]] || continue
  # Strip a trailing "  # comment" (a # preceded by whitespace) from the check.
  check="$(printf '%s' "$check" | sed -E 's/[[:space:]]+#.*$//')"
  if [[ "${g_skip[i]}" == "1" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  out="$(cd "$run_dir" && timeout 60 bash -c "$check" 2>&1)" || true
  # A gate passes when the expected substring appears in the output.
  if [[ -n "$expect" && "$out" == *"$expect"* ]]; then
    continue
  fi
  # Trim the evidence to a short excerpt for the agent.
  excerpt="$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
  failed+=("${g_id[i]} ${g_title[i]} — got: ${excerpt:-<no output>}; expected: ${expect}")
done

if [[ ${#failed[@]} -eq 0 ]]; then
  # All runnable gates green. Report the skip count so skipped gates are
  # visible (not silently ignored) without blocking the stop.
  if [[ "$skipped" -gt 0 ]]; then
    jq -cn --arg r "GATES.md: all runnable gates passed; $skipped skipped (SKIP: 1 or missing runner)" '{decision:"allow", reason:$r}'
  else
    echo '{"decision":"allow"}'
  fi
  exit 0
fi

reason="GATES.md not satisfied before stopping. Failing gate(s):"
for f in "${failed[@]}"; do
  reason+=$'\n'"  - $f"
done
reason+=" — fix these, or update GATES.md EVIDENCE if they are already green."
block "$reason"
