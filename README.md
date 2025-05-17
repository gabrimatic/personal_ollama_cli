# Personal Ollama Terminal AI

A Zsh-based CLI tool providing direct terminal access to local Ollama models with context management, session persistence, and customizable system behavior.

## ✨ Features

*   🗣️ **Streaming Output**: Continuous token-by-token response display from your local Ollama models.
*   🧠 **Global Session Management**: Maintains a single conversation context across all terminal instances, with automatic token limit handling regardless of which terminal window you use.
*   📝 **Global Persistent Memory**: System-wide notes file (`~/.config/ollama/ai_persistent_notes.txt`) accessible to the model across all sessions.
*   🤖 **Customizable System Prompt**: Define model behavior and parameters via `~/.config/ollama/ai_system_prompt.txt`.
*   ⚙️ **Configurable Settings**: Set Ollama model, API endpoint, and context limits in `~/.config/ollama/ai_settings.conf`.
*   ✍️ **Multi-line Input**: Support for complex multi-line queries.
*   🛠️ **Session Management**:
    *   Edit notes, system prompts, and settings with `ai` subcommands (e.g., `ai --edit-notes`).
    *   Reset context (`ai --reset`).
    *   View context info (`ai --info context`).
*   🚀 **Simple Installation**: Automated setup via installer script.

## ✅ Prerequisites

Make sure you have these installed:

1.  **Ollama**: Running with a model pulled (e.g., `ollama pull gemma3:4b-it-qat`). See [ollama.com](https://ollama.com).
2.  **`jq`**: JSON processor (e.g., `brew install jq` or `apt-get install jq`).
3.  **`curl`**: Data transfer tool (usually pre-installed).
4.  **`zsh`**: The Z shell.

## 🛠️ Installation

1.  **Clone or Download**:
    ```bash
    # If you have git
    git clone <your_repository_url> # Replace <your_repository_url> with the actual URL
    cd personal_ollama_cli
    # If downloaded, navigate to the personal_ollama_cli directory
    ```

2.  **Run the Installer**:
    From the `personal_ollama_cli` directory:
    ```bash
    ./install.sh
    ```
    The installer will:
    *   Create config and cache directories (`~/.config/ollama`, `~/.config/zsh`, `~/.cache`).
    *   Copy `ollama_ai.zsh` and default configs.
    *   Add a source line to `~/.zshrc`.

3.  **Apply Changes**:
    Open a new terminal or run:
    ```bash
    source ~/.zshrc
    ```

## 🚀 How to Use

Interact with your Ollama model using the `ai` command:

**Basic Prompt**:
```bash
ai Tell me a joke
```

**Multi-line Input**:
(End with `"""` on a new line)
```bash
ai """
What are the best practices
for writing a good README file?
"""
```

### ⚙️ Management Commands

*   **Settings**:
    *   `ai --show-settings`: View current settings.
    *   `ai --edit-settings`: Open settings file in your editor.

*   **Persistent Notes**:
    *   `ai --view-notes`: Show your persistent notes.
    *   `ai --edit-notes`: Edit your notes. *Psst! Customize this with your info!*

*   **System Prompt**:
    *   `ai --view-system`: Display the system prompt.
    *   `ai --edit-system`: Customize the AI's base instructions.

*   **Conversation Context**:
    *   `ai --info context`: Show context token count and limit.
    *   `ai --reset`: Clear conversation context.
    *   `ai -r "New prompt"`: Reset context and send a new prompt.

*   **Temporary Overrides**:
    *   `ai -m <model_name> "Your prompt"`: Use a different model for this query (e.g., `ai -m gemma3:12b-it-qat "Hi"`).
    *   `ai -s "New system prompt" "Your prompt"`: Use a different system prompt (resets context).

*   **Help**:
    *   `ai --help` or `ai -h`: Show all commands and options.

## 🎨 Customization

*   **`~/.config/ollama/ai_settings.conf`**: Change default model (`AI_OLLAMA_MODEL`), API URL (`AI_OLLAMA_API_URL`), max context tokens (`AI_MAX_CONTEXT_TOKENS`).
*   **`~/.config/ollama/ai_persistent_notes.txt`**: Global information store for the AI across all sessions.
*   **`~/.config/ollama/ai_system_prompt.txt`**: Define the AI's personality and default instructions.

## 🗑️ Uninstalling

1.  Remove files from `~/.config/ollama/`, `~/.config/zsh/ollama_ai.zsh`, and `~/.cache/ollama_ai_context.json`.
2.  Remove the sourcing line from `~/.zshrc`.

## Developer
By [Soroush Yousefpour](https://gabrimatic.info "Soroush Yousefpour")

&copy; All rights reserved.

## Donate
<a href="https://www.buymeacoffee.com/gabrimatic" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Book" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>