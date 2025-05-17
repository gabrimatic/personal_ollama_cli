#!/bin/bash

# Installer for the Personal Ollama Terminal AI Script

SCRIPT_VERSION="1.0.0"
PROJECT_NAME="Personal Ollama Terminal AI"

# Define source paths (relative to this script)
SRC_DIR="$(dirname "$0")/src"
SRC_ZSH_CONFIG_DIR="$SRC_DIR/config/zsh"
SRC_OLLAMA_CONFIG_DIR="$SRC_DIR/config/ollama"
SRC_CACHE_DIR="$SRC_DIR/cache"

# Define target paths in user's home directory
TARGET_ZSH_CONFIG_DIR="$HOME/.config/zsh"
TARGET_OLLAMA_CONFIG_DIR="$HOME/.config/ollama"
TARGET_CACHE_DIR="$HOME/.cache"

TARGET_OLLAMA_AI_SCRIPT="$TARGET_ZSH_CONFIG_DIR/ollama_ai.zsh"
TARGET_AI_SETTINGS_CONF="$TARGET_OLLAMA_CONFIG_DIR/ai_settings.conf"
TARGET_AI_SYSTEM_PROMPT_TXT="$TARGET_OLLAMA_CONFIG_DIR/ai_system_prompt.txt"
TARGET_AI_PERSISTENT_NOTES_TXT="$TARGET_OLLAMA_CONFIG_DIR/ai_persistent_notes.txt"
TARGET_OLLAMA_AI_CONTEXT_JSON="$TARGET_CACHE_DIR/ollama_ai_context.json"

RC_FILE="$HOME/.zshrc" # Assuming Zsh, add logic for Bash if needed
RC_MARKER_COMMENT="# Source Ollama AI functions if the file exists (added by $PROJECT_NAME installer)"
SOURCING_BLOCK="$_ollama_ai_config_file=\"$TARGET_OLLAMA_AI_SCRIPT\"\nif [[ -f \"\$_ollama_ai_config_file\" ]]; then\n    source \"\$_ollama_ai_config_file\"\nfi"

echo "Welcome to the $PROJECT_NAME v$SCRIPT_VERSION installer."
echo "This script will install the AI helper functions and configuration files."
echo ""
echo "It will perform the following actions:"
echo "1. Create directories (if they don't exist):"
echo "   - $TARGET_ZSH_CONFIG_DIR"
echo "   - $TARGET_OLLAMA_CONFIG_DIR"
echo "   - $TARGET_CACHE_DIR"
echo "2. Copy the following files:"
echo "   - $SRC_ZSH_CONFIG_DIR/ollama_ai.zsh -> $TARGET_OLLAMA_AI_SCRIPT"
echo "   - $SRC_OLLAMA_CONFIG_DIR/ai_settings.conf -> $TARGET_AI_SETTINGS_CONF"
echo "   - $SRC_OLLAMA_CONFIG_DIR/ai_system_prompt.txt -> $TARGET_AI_SYSTEM_PROMPT_TXT"
echo "   - $SRC_OLLAMA_CONFIG_DIR/ai_persistent_notes.txt.template -> $TARGET_AI_PERSISTENT_NOTES_TXT (you should customize this file)"
echo "   - $SRC_CACHE_DIR/ollama_ai_context.json -> $TARGET_OLLAMA_AI_CONTEXT_JSON"
echo "3. Add a sourcing command to your $RC_FILE (if not already present)."
echo ""

read -p "Do you want to proceed with the installation? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled by user."
    exit 1
fi

echo "Starting installation..."

# 1. Create directories
echo "Creating target directories..."
mkdir -p "$TARGET_ZSH_CONFIG_DIR"
mkdir -p "$TARGET_OLLAMA_CONFIG_DIR"
mkdir -p "$TARGET_CACHE_DIR"
echo "Directories created/ensured."

# 2. Copy files
echo "Copying files..."
cp "$SRC_ZSH_CONFIG_DIR/ollama_ai.zsh" "$TARGET_OLLAMA_AI_SCRIPT"
echo "Copied ollama_ai.zsh"

cp "$SRC_OLLAMA_CONFIG_DIR/ai_settings.conf" "$TARGET_AI_SETTINGS_CONF"
echo "Copied ai_settings.conf"

cp "$SRC_OLLAMA_CONFIG_DIR/ai_system_prompt.txt" "$TARGET_AI_SYSTEM_PROMPT_TXT"
echo "Copied ai_system_prompt.txt"

if [ -f "$TARGET_AI_PERSISTENT_NOTES_TXT" ]; then
    read -p "Persistent notes file $TARGET_AI_PERSISTENT_NOTES_TXT already exists. Overwrite with template? (y/N): " overwrite_notes
    if [[ "$overwrite_notes" =~ ^[Yy]$ ]]; then
        cp "$SRC_OLLAMA_CONFIG_DIR/ai_persistent_notes.txt.template" "$TARGET_AI_PERSISTENT_NOTES_TXT"
        echo "Copied ai_persistent_notes.txt.template (existing file overwritten)."
    else
        echo "Skipped overwriting ai_persistent_notes.txt."
    fi
else
    cp "$SRC_OLLAMA_CONFIG_DIR/ai_persistent_notes.txt.template" "$TARGET_AI_PERSISTENT_NOTES_TXT"
    echo "Copied ai_persistent_notes.txt.template."
fi

if [ -f "$TARGET_OLLAMA_AI_CONTEXT_JSON" ]; then
    echo "Context file $TARGET_OLLAMA_AI_CONTEXT_JSON already exists. Skipping creation."
else
    cp "$SRC_CACHE_DIR/ollama_ai_context.json" "$TARGET_OLLAMA_AI_CONTEXT_JSON"
    echo "Copied ollama_ai_context.json."
fi
echo "Files copied."

# 3. Add sourcing command to RC_FILE
echo "Updating $RC_FILE..."
if grep -Fxq "$RC_MARKER_COMMENT" "$RC_FILE"; then
    echo "Sourcing command already present in $RC_FILE. Skipping."
else
    echo "Adding sourcing command to $RC_FILE."
    echo "" >> "$RC_FILE" # Add a newline for separation
    echo "$RC_MARKER_COMMENT" >> "$RC_FILE"
    # Use printf for the SOURCING_BLOCK to handle special characters and newlines correctly
    printf "%b\n" "${SOURCING_BLOCK//'/\'}" >> "$RC_FILE"
    echo "Sourcing command added."
fi

echo ""
echo "Installation complete!"
echo ""
echo "IMPORTANT NEXT STEPS:"
echo "1. Customize your persistent notes: $TARGET_AI_PERSISTENT_NOTES_TXT"
echo "   You can use the command: ai --edit-notes"
echo "2. Review system prompt (optional): $TARGET_AI_SYSTEM_PROMPT_TXT"
echo "   You can use the command: ai --view-system or ai --edit-system"
echo "3. Review settings (optional): $TARGET_AI_SETTINGS_CONF"
echo "   You can use the command: ai --view-settings or ai --edit-settings"
echo "4. To apply changes, either open a new terminal window/tab or run:"
echo "   source $RC_FILE"

exit 0 