#!/usr/bin/env bash
# Bootstrap a local Obsidian vault from the tracked harness/ seeds.
# Usage: ./scripts/init-vault.sh [VAULT_PATH]
# Uses $1, else $VAULT_HOST_PATH, else $CMC_VAULT_ROOT. Idempotent; never overwrites.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

SEED_DIR="${CMC_SEED_DIR:-$ROOT/harness}"
VAULT="${1:-${VAULT_HOST_PATH:-${CMC_VAULT_ROOT:-}}}"
[[ -n "$VAULT" ]] || die "usage: $0 /path/to/vault (or set VAULT_HOST_PATH)"

mkdir -p "$VAULT"/{setup/cmc-profile,glossary,agent-sessions,adrs,lessons,runbooks}

copy_if_missing() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || return 0
  [[ -e "$dest" ]] && return 0
  cp -a "$src" "$dest"
  info "seeded $dest"
}

copy_if_missing "$SEED_DIR/vault-AGENTS.md" "$VAULT/AGENTS.md"
copy_if_missing "$SEED_DIR/CMC-Harness-Plan.md" "$VAULT/setup/CMC-Harness-Plan.md"
copy_if_missing "$SEED_DIR/CMC-Agent-Setup-Questionnaire.md" "$VAULT/setup/CMC-Agent-Setup-Questionnaire.md"
copy_if_missing "$SEED_DIR/cmc-profile/AGENTS.md" "$VAULT/setup/cmc-profile/AGENTS.md"
copy_if_missing "$SEED_DIR/glossary/MODEX-WINGS.md" "$VAULT/glossary/MODEX-WINGS.md"
copy_if_missing "$SEED_DIR/agent-sessions/README.md" "$VAULT/agent-sessions/README.md"

info "Vault ready: $VAULT"
info "  setup/ (plan, questionnaire, profile) + glossary/ + agent-sessions/ + adrs/ + lessons/ + runbooks/"

