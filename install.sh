#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="personal_ollama_cli"
SCRIPT_VERSION="2.0.0"

YES=false
FORCE=false
DRY_RUN=false
INSTALL_SHELL=true

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Install the ai zsh command and default Ollama config files.

Options:
  -y, --yes          Run without confirmation.
  --force            Overwrite config templates after creating timestamped backups.
  --dry-run          Print planned changes without writing files.
  --no-shell         Do not update ~/.zshrc.
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      YES=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-shell)
      INSTALL_SHELL=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
SRC_ZSH="$SRC_DIR/config/zsh/ollama_ai.zsh"
SRC_SETTINGS="$SRC_DIR/config/ollama/ai_settings.conf"
SRC_SYSTEM="$SRC_DIR/config/ollama/ai_system_prompt.txt"
SRC_NOTES="$SRC_DIR/config/ollama/ai_persistent_notes.txt.template"

TARGET_ZSH_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
TARGET_OLLAMA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ollama"
TARGET_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
TARGET_ZSH="$TARGET_ZSH_DIR/ollama_ai.zsh"
TARGET_SETTINGS="$TARGET_OLLAMA_DIR/ai_settings.conf"
TARGET_SYSTEM="$TARGET_OLLAMA_DIR/ai_system_prompt.txt"
TARGET_NOTES="$TARGET_OLLAMA_DIR/ai_persistent_notes.txt"
TARGET_CONTEXT="$TARGET_CACHE_DIR/ollama_ai_context.json"
RC_FILE="$HOME/.zshrc"

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

backup_if_needed() {
  local target="$1"
  if [[ -f "$target" && "$FORCE" == true ]]; then
    run cp "$target" "$target.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

install_file() {
  local src="$1"
  local target="$2"
  local mode="$3"
  local label="$4"
  local preserve_existing="$5"

  if [[ -f "$target" && "$preserve_existing" == true && "$FORCE" != true ]]; then
    echo "Keeping existing $label: $target"
    return 0
  fi

  backup_if_needed "$target"
  run mkdir -p "$(dirname "$target")"
  run cp "$src" "$target"
  run chmod "$mode" "$target"
  echo "Installed $label: $target"
}

append_shell_block() {
  local marker="# personal_ollama_cli"
  local block
  block="$(cat <<EOF

$marker
_ollama_ai_config_file="$TARGET_ZSH"
if [ -f "\$_ollama_ai_config_file" ]; then
    source "\$_ollama_ai_config_file"
fi
EOF
)"

  if [[ -f "$RC_FILE" ]] && grep -Fq "$TARGET_ZSH" "$RC_FILE"; then
    echo "Shell source block already present in $RC_FILE"
    return 0
  fi

  run touch "$RC_FILE"
  if [[ "$DRY_RUN" == true ]]; then
    echo "dry-run: append source block to $RC_FILE"
  else
    printf '%s\n' "$block" >> "$RC_FILE"
  fi
  echo "Updated shell profile: $RC_FILE"
}

echo "$PROJECT_NAME $SCRIPT_VERSION installer"
echo
echo "Target files:"
echo "  $TARGET_ZSH"
echo "  $TARGET_SETTINGS"
echo "  $TARGET_SYSTEM"
echo "  $TARGET_NOTES"
echo "  $TARGET_CONTEXT"
[[ "$INSTALL_SHELL" == true ]] && echo "  $RC_FILE"
echo

if [[ "$YES" != true && "$DRY_RUN" != true ]]; then
  read -r -p "Install now? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 1
  fi
fi

install_file "$SRC_ZSH" "$TARGET_ZSH" "0644" "zsh command" false
install_file "$SRC_SETTINGS" "$TARGET_SETTINGS" "0644" "settings" true
install_file "$SRC_SYSTEM" "$TARGET_SYSTEM" "0644" "system prompt" true
install_file "$SRC_NOTES" "$TARGET_NOTES" "0600" "persistent notes" true

if [[ ! -f "$TARGET_CONTEXT" ]]; then
  run mkdir -p "$(dirname "$TARGET_CONTEXT")"
  if [[ "$DRY_RUN" == true ]]; then
    echo "dry-run: create $TARGET_CONTEXT"
  else
    printf '[]\n' > "$TARGET_CONTEXT"
    chmod 0600 "$TARGET_CONTEXT"
  fi
  echo "Created context: $TARGET_CONTEXT"
else
  echo "Keeping existing context: $TARGET_CONTEXT"
fi

if [[ "$INSTALL_SHELL" == true ]]; then
  append_shell_block
fi

cat <<EOF

Done.
Open a new terminal, or run:
  source "$TARGET_ZSH"

Then try:
  ai --doctor
  ai "say hello in one short sentence"
EOF
