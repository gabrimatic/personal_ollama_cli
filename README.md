# Personal Ollama Terminal AI

A Zsh-based CLI for talking to local Ollama models from the terminal. Includes context management, persistent sessions, and configurable system behavior.

## Features

- **Streaming output**: token-by-token responses from local Ollama models.
- **Global session management**: one shared conversation context across all terminal instances, with automatic token-limit handling.
- **Global persistent memory**: a system-wide notes file (`~/.config/ollama/ai_persistent_notes.txt`) the model can read across sessions.
- **Customizable system prompt**: edit the model's behavior and parameters in `~/.config/ollama/ai_system_prompt.txt`.
- **Configurable settings**: model, API endpoint, and context limits in `~/.config/ollama/ai_settings.conf`.
- **Multi-line input** for longer prompts.
- **Session controls**:
    - Edit notes, system prompt, and settings via `ai` subcommands (e.g. `ai --edit-notes`).
    - Reset context with `ai --reset`.
    - Inspect context state with `ai --info context`.
- **Installer script** for first-time setup.

## Prerequisites

1. **Ollama** running with at least one model pulled (e.g. `ollama pull gemma3:4b-it-qat`). See [ollama.com](https://ollama.com).
2. **`jq`**: JSON processor (`brew install jq` or `apt-get install jq`).
3. **`curl`**: usually pre-installed.
4. **`zsh`**: the Z shell.

## Installation

1. **Clone or download**:

    ```bash
    git clone <your_repository_url>
    cd personal_ollama_cli
    ```

2. **Run the installer**:

    ```bash
    ./install.sh
    ```

    The installer will:
    - Create config and cache directories (`~/.config/ollama`, `~/.config/zsh`, `~/.cache`).
    - Copy `ollama_ai.zsh` and default configs into place.
    - Add a source line to `~/.zshrc`.

3. **Reload your shell**:

    ```bash
    source ~/.zshrc
    ```

## Usage

Talk to the model with `ai`:

**Basic prompt**:
```bash
ai Tell me a joke
```

**Multi-line input** (end with `"""` on its own line):
```bash
ai """
What are good practices
for writing a README?
"""
```

### Management commands

- **Settings**:
    - `ai --show-settings`: view current settings.
    - `ai --edit-settings`: open settings in your editor.

- **Persistent notes**:
    - `ai --view-notes`: show notes.
    - `ai --edit-notes`: edit notes.

- **System prompt**:
    - `ai --view-system`: display the system prompt.
    - `ai --edit-system`: edit the system prompt.

- **Conversation context**:
    - `ai --info context`: show context token count and limit.
    - `ai --reset`: clear context.
    - `ai -r "New prompt"`: reset context, then send a new prompt.

- **Temporary overrides**:
    - `ai -m <model_name> "Your prompt"`: use a different model for this query.
    - `ai -s "New system prompt" "Your prompt"`: use a different system prompt (resets context).

- **Help**:
    - `ai --help` or `ai -h`: list all commands and options.

## Customization

- **`~/.config/ollama/ai_settings.conf`**: default model (`AI_OLLAMA_MODEL`), API URL (`AI_OLLAMA_API_URL`), max context tokens (`AI_MAX_CONTEXT_TOKENS`).
- **`~/.config/ollama/ai_persistent_notes.txt`**: shared note store the model can read across sessions.
- **`~/.config/ollama/ai_system_prompt.txt`**: system prompt and default behavior.

## Uninstall

1. Remove files from `~/.config/ollama/`, `~/.config/zsh/ollama_ai.zsh`, and `~/.cache/ollama_ai_context.json`.
2. Remove the source line from `~/.zshrc`.

## Developer
By [Soroush Yousefpour](https://gabrimatic.info "Soroush Yousefpour")

&copy; All rights reserved.

## Donate
<a href="https://www.buymeacoffee.com/gabrimatic" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Book" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>
