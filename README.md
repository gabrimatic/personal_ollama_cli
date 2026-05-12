# personal_ollama_cli

[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)
[![Shell: zsh](https://img.shields.io/badge/shell-zsh-blue.svg)]()
[![Runtime: Ollama](https://img.shields.io/badge/runtime-Ollama-green.svg)](https://ollama.com)
[![Local-first](https://img.shields.io/badge/local--first-terminal-green.svg)]()

`personal_ollama_cli` is a small zsh command for talking to local Ollama models from the terminal. It gives you one `ai` command with streaming replies, saved chat context, persistent notes, a configurable system prompt, pipe-friendly prompts, and simple local management commands.

The runtime path stays local: the CLI sends requests to your Ollama server, stores context in your cache directory, and keeps notes and prompts in your config directory. No account. No hosted API. No telemetry.

## At a Glance

| Surface | Runtime scope | Status |
|---------|---------------|--------|
| Terminal chat | `ai "prompt"` streams from the local Ollama chat API. | Ready |
| Conversation memory | Saves user and assistant messages in `~/.cache/ollama_ai_context.json`, with lock-protected writes and import/export commands. | Ready |
| Persistent notes | Adds stable local notes from `~/.config/ollama/ai_persistent_notes.txt` to each request. | Ready |
| System prompt | Reads default behavior from `~/.config/ollama/ai_system_prompt.txt`. | Ready |
| Pipe workflows | Accepts stdin for commands like `git diff | ai "review this"`. | Ready |
| Local management | Reset, view, import, export context, inspect settings, list installed and running models, and run a local doctor check. | Ready |

## Quick Start

Requirements: **zsh**, **curl**, **jq**, and [Ollama](https://ollama.com) with a model pulled.

```bash
git clone https://github.com/gabrimatic/personal_ollama_cli.git
cd personal_ollama_cli
./install.sh
```

Open a new terminal, or source the installed file:

```bash
source ~/.config/zsh/ollama_ai.zsh
```

Check the setup:

```bash
ai --doctor
ai --models
```

Then chat:

```bash
ai "say hello in one short sentence"
```

## Features

- **Streaming terminal output** from Ollama's `/api/chat` endpoint.
- **Real chat history** stored as message objects instead of deprecated generate-context token arrays.
- **Explicit context modes** with `--no-context`, `--no-save`, `--view-context`, `--export-context`, and `--import-context`.
- **Pipe-friendly prompts**: stdin is appended to the typed instruction, so `git diff | ai "review this"` works naturally.
- **Context reset** with `ai --reset` or per-request reset with `ai -r "prompt"`.
- **One-off model selection** with `ai -m qwen3:4b "prompt"`.
- **One-off system prompt** with `ai -s "answer as a terse shell helper" "prompt"`.
- **One-off runtime controls** for JSON mode, response format, thinking mode, keep-alive, context window, and stats.
- **Multi-line prompts** with `ai """`, then end input with `"""` on its own line.
- **Persistent notes** for stable local preferences and context.
- **Doctor check** for dependencies, Ollama reachability, and default model availability.
- **Safer installer** that keeps existing config by default and only overwrites with `--force`.

## Commands

| Command | Action |
|---------|--------|
| `ai "prompt"` | Send a prompt using the configured model. |
| `git diff | ai "review this"` | Append stdin to the prompt. |
| `ai -r "prompt"` | Clear saved context, then send a prompt. |
| `ai --no-context "prompt"` | Send a one-off prompt without reading or saving chat history. |
| `ai --no-save "prompt"` | Read chat history but do not save this turn. |
| `ai --json "prompt"` | Ask Ollama for JSON-mode output. |
| `ai --stats "prompt"` | Print final token and timing stats to stderr. |
| `ai --reset` | Clear saved context and exit. |
| `ai --info context` | Show saved context size and path. |
| `ai --view-context` | Print saved context as readable turns. |
| `ai --export-context context.json` | Export saved context JSON. |
| `ai --import-context context.json` | Replace saved context from an export. |
| `ai --models` | List local Ollama models. |
| `ai --status` | List currently loaded Ollama models. |
| `ai --doctor` | Check dependencies and Ollama reachability. |
| `ai --show-settings` | Show effective settings and file paths. |
| `ai --view-notes` / `ai --edit-notes` | Read or edit persistent notes. |
| `ai --view-system` / `ai --edit-system` | Read or edit the system prompt. |
| `ai --edit-settings` | Edit the settings file. |

## Configuration

Default files:

| File | Purpose |
|------|---------|
| `~/.config/ollama/ai_settings.conf` | Model, API URL, context message limit, and optional Ollama runtime settings. |
| `~/.config/ollama/ai_system_prompt.txt` | Default system prompt. |
| `~/.config/ollama/ai_persistent_notes.txt` | Stable local notes injected into requests. |
| `~/.cache/ollama_ai_context.json` | Saved chat history. |

Default settings:

```conf
AI_OLLAMA_MODEL=gemma3:4b
AI_OLLAMA_API_URL=http://localhost:11434/api/chat
AI_MAX_CONTEXT_MESSAGES=24
AI_KEEP_ALIVE=5m
# AI_THINK=false
# AI_NUM_CTX=8192
# AI_RESPONSE_FORMAT=json
AI_CONNECT_TIMEOUT=5
AI_REQUEST_TIMEOUT=300
AI_CONTEXT_LOCK_TIMEOUT=10
AI_SHOW_STATS=false
```

The CLI accepts old `.../api/generate` values and normalizes them to `.../api/chat` at runtime.

## Installer

The installer updates the zsh command and creates missing config files. It does not overwrite existing settings, notes, or prompts unless you pass `--force`.

```bash
./install.sh --dry-run
./install.sh --yes
./install.sh --yes --force
./install.sh --yes --no-shell
```

With `--force`, existing config templates are copied to timestamped `.bak.*` files before replacement.

## Development

Run the local checks:

```bash
zsh scripts/test.sh
```

The test harness uses a temporary home directory and a mocked `curl`, so it does not touch your real Ollama config or live chat history.

## Uninstall

Remove the source block from `~/.zshrc`, then remove the installed files you no longer want:

```bash
trash ~/.config/zsh/ollama_ai.zsh
trash ~/.config/ollama/ai_settings.conf
trash ~/.config/ollama/ai_system_prompt.txt
trash ~/.config/ollama/ai_persistent_notes.txt
trash ~/.cache/ollama_ai_context.json
```

Use `rm` instead of `trash` if your system does not have `trash` installed.

## Author

Built and maintained by [Soroush Yousefpour](https://gabrimatic.info).

## License

MIT. See [LICENSE](LICENSE).
