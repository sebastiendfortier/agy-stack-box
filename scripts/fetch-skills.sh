#!/usr/bin/env bash
# Wire ponytail + caveman for:
#   1) host Cursor account (~/.cursor hooks + skills)
#   2) host agy / Antigravity IDE (~/.gemini)
#   3) agy-stack-box state/ (instance $HOME/.gemini)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

CAVEMAN_REF="${CAVEMAN_REF:-v4.0.1}"
PONYTAIL_URL="${PONYTAIL_URL:-https://github.com/DietrichGebert/ponytail.git}"
PONYTAIL_SRC="${PONYTAIL_SRC:-$HOME/src/ponytail}"
WIRE_HOST="${WIRE_HOST:-1}"

require_cmd node
require_cmd npx
require_cmd git

mkdir -p "$STATE_DIR"/{home,gemini/antigravity/skills,gemini/config/{skills,plugins}}
chmod 700 "$STATE_DIR"
rm -f "$STATE_DIR/home/.gemini"
ln -sfn ../gemini "$STATE_DIR/home/.gemini"

if [[ ! -d "$PONYTAIL_SRC/.git" ]]; then
  info "Cloning ponytail -> $PONYTAIL_SRC"
  mkdir -p "$(dirname "$PONYTAIL_SRC")"
  git clone --depth 1 "$PONYTAIL_URL" "$PONYTAIL_SRC"
fi

if [[ "$WIRE_HOST" == "1" ]]; then
  if [[ -d "$HOME/.cursor" ]]; then
    info "Host Cursor: always-on ultra/ultracave user rules (no /slash needed)"
    mkdir -p "$HOME/.config/ponytail" "$HOME/.config/caveman" "$HOME/.cursor/rules"
    printf '%s\n' '{"defaultMode":"ultra"}' >"$HOME/.config/ponytail/config.json"
    printf '%s\n' '{"defaultMode":"ultracave"}' >"$HOME/.config/caveman/config.json"
    # Skills still useful for explicit invoke; rules make modes default-on.
    npx -y "github:JuliusBrussee/caveman#${CAVEMAN_REF}" -- --only cursor || true
    npx -y skills add DietrichGebert/ponytail --skill '*' -a cursor --yes -g || true
    # Prefer alwaysApply rules over sessionStart hooks (CLI/agent often skips hooks).
    if [[ -f "$HOME/.cursor/rules/ponytail.mdc" ]]; then
      info "keeping existing ~/.cursor/rules/ponytail.mdc"
    fi
  fi

  if command -v agy >/dev/null 2>&1; then
    info "Host agy: plugins ponytail + caveman"
    agy plugin install "$PONYTAIL_URL" || true
    npx -y "github:JuliusBrussee/caveman#${CAVEMAN_REF}" -- --only antigravity-cli || true
  fi

  info "Host Antigravity IDE skill trees"
  npx -y "github:JuliusBrussee/caveman#${CAVEMAN_REF}" -- --only antigravity || true
  npx -y "github:JuliusBrussee/caveman#${CAVEMAN_REF}" -- --only antigravity-2 || true
  for d in "$HOME/.gemini/antigravity/skills" "$HOME/.gemini/config/skills"; do
    mkdir -p "$d"
    for s in "$PONYTAIL_SRC"/skills/*; do
      [[ -d "$s" ]] || continue
      name="$(basename "$s")"
      rm -rf "$d/$name"
      cp -a "$s" "$d/$name"
    done
  done
  mkdir -p "$HOME/.gemini/antigravity"
  cp -a "$PONYTAIL_SRC/AGENTS.md" "$HOME/.gemini/antigravity/AGENTS.md"
fi

sync_tree() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || return 0
  mkdir -p "$dest"
  # Copy contents; refresh owned skill/plugin dirs.
  cp -a "$src"/. "$dest"/
}

info "Mirroring host ~/.gemini skills/plugins into $STATE_DIR/gemini"
sync_tree "$HOME/.gemini/antigravity/skills" "$STATE_DIR/gemini/antigravity/skills"
sync_tree "$HOME/.gemini/config/skills" "$STATE_DIR/gemini/config/skills"
sync_tree "$HOME/.gemini/config/plugins" "$STATE_DIR/gemini/config/plugins"
if [[ -f "$HOME/.gemini/antigravity/AGENTS.md" ]]; then
  cp -a "$HOME/.gemini/antigravity/AGENTS.md" "$STATE_DIR/gemini/antigravity/AGENTS.md"
fi
# Ensure ponytail skills exist even if host mirror was empty
for d in "$STATE_DIR/gemini/antigravity/skills" "$STATE_DIR/gemini/config/skills"; do
  mkdir -p "$d"
  for s in "$PONYTAIL_SRC"/skills/*; do
    [[ -d "$s" ]] || continue
    name="$(basename "$s")"
    rm -rf "$d/$name"
    cp -a "$s" "$d/$name"
  done
done
cp -a "$PONYTAIL_SRC/AGENTS.md" "$STATE_DIR/gemini/antigravity/AGENTS.md"

info "Done."
info "  Cursor: open a new chat — sessionStart loads ponytail + caveman; /ponytail lite|full|ultra|off"
info "  agy:    plugins $(command -v agy >/dev/null && agy plugin list 2>/dev/null | tr '\n' ' ' || echo '(install agy)')"
info "  stack:  $STATE_DIR/gemini (bound into instance as \$HOME/.gemini)"
