#!/usr/bin/env bash
# PreToolUse hook: run agent shell commands in a login shell on HPC.
#
# Why: the agent's run_command tool spawns a bare, non-login shell. On an HPC
# login node the site environment (PATH, ordenv, module tools) is set up by the
# login profile, so a bare shell cannot resolve site tools and HPC commands
# fail. This hook rewrites the command to run under a login shell, which loads
# the site profile (and, with it, ordenv) before the command runs.
#
# It is OFF by default so it never changes behaviour on a normal workstation or
# for a running app. Enable it per session with AGY_HPC_WRAP=1 (HPC commands
# only) or AGY_HPC_WRAP=all (every command).
#
# Contract (see builtin agy-customizations docs/hooks.md): the agent sends the
# tool call as JSON on stdin; we answer with a JSON decision on stdout.
set -euo pipefail

# Default: let everything through untouched.
allow() { echo '{"decision":"allow"}'; exit 0; }

command -v jq >/dev/null 2>&1 || allow

payload="$(cat || true)"
[[ -n "$payload" ]] || allow

tool_name="$(jq -r '.toolCall.name // empty' <<<"$payload" 2>/dev/null || true)"
[[ "$tool_name" == "run_command" ]] || allow

cmd="$(jq -r '.toolCall.args.CommandLine // empty' <<<"$payload" 2>/dev/null || true)"
[[ -n "$cmd" ]] || allow

mode="${AGY_HPC_WRAP:-0}"
[[ "$mode" == "1" || "$mode" == "all" ]] || allow

# Already a login shell — wrapping again would nest profiles.
case "$cmd" in
  *'bash -l -c'*) allow ;;
esac

# Only wrap when the command actually needs the HPC environment, unless the
# caller asked for every command (=all). Keeps normal repo work untouched.
if [[ "$mode" != "all" ]]; then
  case "$cmd" in
    *module\ *|*'\bml '*|*qsub*|*qstat*|*qdel*|*sbatch*|*squeue*|*scancel*|*ordenv*|*srun*)
      ;;
    *) allow ;;
  esac
fi

# The hook runs with its cwd set to the repo root, but the agent's command may
# rely on relative paths in its own working directory. cd into the first
# workspace path (from the payload) so those resolve the same way.
ws="$(jq -r '.workspacePaths[0] // empty' <<<"$payload" 2>/dev/null || true)"

# Quote the inner command so embedded quotes/globs survive the agent's re-run
# verbatim. The single-quoted form is the robust one: only single quotes need
# escaping (as '\''), and everything else — double quotes, $vars, globs, pipes
# — passes through untouched. A printf %q plus an outer quote would
# double-escape and break the round-trip.
if [[ -n "$ws" ]]; then
  inner="cd $ws && $cmd"
else
  inner="$cmd"
fi
qinner="${inner//\'/\'\\\'\'}"
wrapped="$(jq -cn --arg c "$qinner" '{decision:"allow", reason:"hpc-shell-wrap: running in a login shell so the site environment (ordenv) is loaded", overwrite:{CommandLine:("bash -l -c '"'"'" + $c + "'"'"'")}}')"
echo "$wrapped"
