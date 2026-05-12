# personal_ollama_cli
# Source this file from zsh to expose the `ai` command.

_AI_VERSION="2.0.0"

_AI_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
_AI_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

_AI_SETTINGS_FILE="${AI_SETTINGS_FILE:-$_AI_CONFIG_HOME/ollama/ai_settings.conf}"
_AI_CONTEXT_FILE="${AI_CONTEXT_FILE:-$_AI_CACHE_HOME/ollama_ai_context.json}"
_AI_NOTES_FILE="${AI_NOTES_FILE:-$_AI_CONFIG_HOME/ollama/ai_persistent_notes.txt}"
_AI_SYSTEM_PROMPT_FILE="${AI_SYSTEM_PROMPT_FILE:-$_AI_CONFIG_HOME/ollama/ai_system_prompt.txt}"

_ai_conf_model=""
_ai_conf_api_url=""
_ai_conf_max_context_messages=""
_ai_conf_keep_alive=""
_ai_conf_think=""
_ai_conf_num_ctx=""

_ai_error() {
  print -u2 -- "Error: $*"
}

_ai_warn() {
  print -u2 -- "[Warning] $*"
}

_ai_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  print -r -- "$value"
}

_ai_require_commands() {
  local dep missing=()
  for dep in jq curl mkdir mv dirname mktemp cat touch; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    _ai_error "Missing dependency: ${missing[*]}"
    return 1
  fi
}

_ai_load_settings() {
  _ai_conf_model="gemma3:4b"
  _ai_conf_api_url="http://localhost:11434/api/chat"
  _ai_conf_max_context_messages="24"
  _ai_conf_keep_alive="5m"
  _ai_conf_think=""
  _ai_conf_num_ctx=""

  [[ -r "$_AI_SETTINGS_FILE" ]] || return 0

  local raw key value
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    raw="$(_ai_trim "$raw")"
    [[ -z "$raw" || "$raw" == \#* ]] && continue
    [[ "$raw" == *"="* ]] || continue

    key="$(_ai_trim "${raw%%=*}")"
    value="$(_ai_trim "${raw#*=}")"
    value="${value%\"}"
    value="${value#\"}"

    case "$key" in
      AI_OLLAMA_MODEL)
        [[ -n "$value" ]] && _ai_conf_model="$value"
        ;;
      AI_OLLAMA_API_URL)
        [[ -n "$value" ]] && _ai_conf_api_url="$value"
        ;;
      AI_MAX_CONTEXT_MESSAGES)
        if [[ "$value" =~ '^[0-9]+$' && "$value" -gt 0 ]]; then
          _ai_conf_max_context_messages="$value"
        elif [[ -n "$value" ]]; then
          _ai_warn "Invalid AI_MAX_CONTEXT_MESSAGES in settings: $value. Using $_ai_conf_max_context_messages."
        fi
        ;;
      AI_MAX_CONTEXT_TOKENS)
        if [[ ! -n "${AI_MAX_CONTEXT_MESSAGES:-}" && "$value" =~ '^[0-9]+$' ]]; then
          _ai_conf_max_context_messages="24"
        fi
        ;;
      AI_KEEP_ALIVE)
        _ai_conf_keep_alive="$value"
        ;;
      AI_THINK)
        _ai_conf_think="$value"
        ;;
      AI_NUM_CTX)
        if [[ -z "$value" || "$value" =~ '^[0-9]+$' ]]; then
          _ai_conf_num_ctx="$value"
        else
          _ai_warn "Invalid AI_NUM_CTX in settings: $value. Ignoring it."
        fi
        ;;
      AI_CONTEXT_FILE_PATH|AI_NOTES_FILE_PATH|AI_SYSTEM_PROMPT_FILE_PATH)
        ;;
      *)
        ;;
    esac
  done < "$_AI_SETTINGS_FILE"
}

_ai_ensure_files() {
  local file
  for file in "$_AI_SETTINGS_FILE" "$_AI_CONTEXT_FILE" "$_AI_NOTES_FILE" "$_AI_SYSTEM_PROMPT_FILE"; do
    mkdir -p "$(dirname "$file")" || return 1
  done

  if [[ ! -e "$_AI_CONTEXT_FILE" ]]; then
    print -r -- "[]" > "$_AI_CONTEXT_FILE" || return 1
  fi
}

_ai_chat_url() {
  local url="${_ai_conf_api_url%/}"
  if [[ "$url" == */api/generate ]]; then
    url="${url%/generate}/chat"
  fi
  print -r -- "$url"
}

_ai_base_url() {
  local url="$(_ai_chat_url)"
  url="${url%/api/chat}"
  print -r -- "$url"
}

_ai_load_context() {
  if [[ -r "$_AI_CONTEXT_FILE" ]] && jq -e 'type == "array"' "$_AI_CONTEXT_FILE" >/dev/null 2>&1; then
    cat "$_AI_CONTEXT_FILE"
  else
    [[ -e "$_AI_CONTEXT_FILE" ]] && _ai_warn "Context file is not a JSON array. Starting with an empty context."
    print -r -- "[]"
  fi
}

_ai_write_context() {
  local json="$1"
  local tmp
  tmp="$(mktemp "${_AI_CONTEXT_FILE}.XXXXXX")" || return 1
  print -r -- "$json" > "$tmp" || return 1
  mv "$tmp" "$_AI_CONTEXT_FILE"
}

_ai_reset_context() {
  mkdir -p "$(dirname "$_AI_CONTEXT_FILE")" || return 1
  _ai_write_context "[]" || return 1
  print -u2 -- "[Info] Conversation context reset."
}

_ai_context_info() {
  local context count chars
  context="$(_ai_load_context)"
  count="$(jq 'length' <<< "$context" 2>/dev/null)"
  chars="$(jq '[.[].content // ""] | join("") | length' <<< "$context" 2>/dev/null)"
  print -- "Context: ${count:-0} messages, ${chars:-0} characters (limit: $_ai_conf_max_context_messages messages)"
  print -- "File: $_AI_CONTEXT_FILE"
}

_ai_help() {
  cat <<EOF
Usage:
  ai [options] "prompt"
  ai [options] \"\"\"
  ai <command>

Talk to a local Ollama model through the chat API.

Options:
  -m, --model MODEL       Use a different model for this request.
  -s, --system PROMPT     Use a one-off system prompt and reset context first.
  -r, --reset             Reset context before the prompt. Used alone, only resets.
  -h, --help              Show this help.

Commands:
  --info context          Show saved conversation size.
  --reset                 Clear saved conversation context.
  --doctor                Check local dependencies and Ollama reachability.
  --models                List models from the local Ollama server.
  --show-settings         Show effective settings and paths.
  --view-notes            Print persistent notes.
  --edit-notes            Edit persistent notes.
  --view-system           Print the system prompt.
  --edit-system           Edit the system prompt.
  --edit-settings         Edit settings.

Files:
  Settings:  $_AI_SETTINGS_FILE
  Notes:     $_AI_NOTES_FILE
  System:    $_AI_SYSTEM_PROMPT_FILE
  Context:   $_AI_CONTEXT_FILE
EOF
}

_ai_pick_editor() {
  if [[ -n "${EDITOR:-}" ]]; then
    print -r -- "$EDITOR"
  elif command -v nano >/dev/null 2>&1; then
    print -r -- "nano"
  elif command -v vim >/dev/null 2>&1; then
    print -r -- "vim"
  else
    print -r -- "vi"
  fi
}

_ai_edit_file() {
  local label="$1"
  local file="$2"
  local editor
  editor="$(_ai_pick_editor)"
  command -v "$editor" >/dev/null 2>&1 || {
    _ai_error "Editor '$editor' not found. Set EDITOR to a working command."
    return 1
  }

  mkdir -p "$(dirname "$file")" || return 1
  touch "$file" || {
    _ai_error "Cannot write $label file: $file"
    return 1
  }

  print -u2 -- "Opening $label: $file"
  "$editor" "$file"
}

_ai_view_file() {
  local label="$1"
  local file="$2"
  if [[ ! -r "$file" ]]; then
    _ai_error "No readable $label file at $file"
    return 1
  fi

  print -- "--- $label ($file) ---"
  cat "$file"
  print -- "--- end $label ---"
}

_ai_doctor() {
  local ok=true base tags_status
  print -- "personal_ollama_cli $_AI_VERSION"

  for dep in zsh jq curl; do
    if command -v "$dep" >/dev/null 2>&1; then
      print -- "ok: $dep"
    else
      print -- "missing: $dep"
      ok=false
    fi
  done

  base="$(_ai_base_url)"
  tags_status="$(curl --silent --show-error --connect-timeout 2 --max-time 5 --output /dev/null --write-out "%{http_code}" "$base/api/tags" 2>/dev/null)"
  if [[ "$tags_status" == "200" ]]; then
    print -- "ok: Ollama reachable at $base"
  else
    print -- "warning: Ollama was not reachable at $base"
    ok=false
  fi

  $ok
}

_ai_models() {
  local base
  base="$(_ai_base_url)"
  curl --fail --silent --show-error --connect-timeout 2 --max-time 10 "$base/api/tags" |
    jq -r '.models[]? | "\(.name)\t\(.details.parameter_size // "-")\t\(.modified_at)"'
}

_ai_build_messages() {
  local context="$1"
  local prompt="$2"
  local system_prompt="$3"
  local notes="$4"

  jq -n \
    --argjson context "$context" \
    --arg system "$system_prompt" \
    --arg notes "$notes" \
    --arg prompt "$prompt" '
      def message($role; $content): {role: $role, content: $content};
      (
        (if ($system | length) > 0 then [message("system"; $system)] else [] end) +
        (if ($notes | length) > 0 then [message("system"; "Persistent notes for this user. Use only when relevant.\n" + $notes)] else [] end) +
        $context +
        [message("user"; $prompt)]
      )
    '
}

_ai_save_turn() {
  local context="$1"
  local prompt="$2"
  local response="$3"
  local max_messages="$_ai_conf_max_context_messages"
  local next_context

  next_context="$(jq -c \
    --arg prompt "$prompt" \
    --arg response "$response" \
    --argjson max "$max_messages" '
      . + [
        {role: "user", content: $prompt},
        {role: "assistant", content: $response}
      ] | .[-$max:]
    ' <<< "$context")" || return 1

  _ai_write_context "$next_context"
}

_ai_stream_chat() {
  local prompt="$1"
  local model="$2"
  local system_prompt="$3"
  local notes="$4"
  local context messages payload url status_file curl_status line chunk err done assistant_response

  context="$(_ai_load_context)"
  messages="$(_ai_build_messages "$context" "$prompt" "$system_prompt" "$notes")" || {
    _ai_error "Could not build chat messages."
    return 1
  }

  payload="$(jq -n \
    --arg model "$model" \
    --argjson messages "$messages" \
    --arg keep_alive "$_ai_conf_keep_alive" \
    --arg think "$_ai_conf_think" \
    --arg num_ctx "$_ai_conf_num_ctx" '
      {
        model: $model,
        messages: $messages,
        stream: true
      }
      + (if ($keep_alive | length) > 0 then {keep_alive: $keep_alive} else {} end)
      + (if ($think | length) > 0 then {think: (if $think == "true" then true elif $think == "false" then false else $think end)} else {} end)
      + (if ($num_ctx | length) > 0 then {options: {num_ctx: ($num_ctx | tonumber)}} else {} end)
    ')" || {
      _ai_error "Could not build request payload."
      return 1
    }

  url="$(_ai_chat_url)"
  status_file="$(mktemp "${TMPDIR:-/tmp}/personal_ollama_cli.curl_status.XXXXXX")" || return 1
  assistant_response=""
  err=""
  done=false

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    if ! jq -e . <<< "$line" >/dev/null 2>&1; then
      _ai_warn "Ignoring non-JSON stream line: $line"
      continue
    fi

    err="$(jq -r '.error // ""' <<< "$line")"
    if [[ -n "$err" ]]; then
      print -u2 -- "[API Error] $err"
      break
    fi

    chunk="$(jq -r '.message.content // .response // ""' <<< "$line")"
    if [[ -n "$chunk" ]]; then
      print -n -- "$chunk"
      assistant_response+="$chunk"
    fi

    done="$(jq -r '.done // false' <<< "$line")"
  done < <(
    curl --fail --silent --show-error -N \
      --connect-timeout 5 \
      --max-time 300 \
      -H "Content-Type: application/json" \
      -X POST "$url" \
      -d "$payload"
    print -r -- "$?" > "$status_file"
  )

  [[ -n "$assistant_response" ]] && print
  curl_status="$(cat "$status_file" 2>/dev/null)"
  command rm -f "$status_file" 2>/dev/null

  if [[ -n "$err" ]]; then
    print -u2 -- "[Info] Context not saved due to API error."
    return 1
  fi

  if [[ "${curl_status:-1}" != "0" ]]; then
    _ai_error "Ollama request failed. Check that Ollama is running and reachable at $url."
    return 1
  fi

  if [[ "$done" != "true" ]]; then
    _ai_warn "Stream ended before Ollama sent done=true. Context not saved."
    return 1
  fi

  if [[ -z "$assistant_response" ]]; then
    _ai_warn "Ollama returned an empty response. Context not saved."
    return 1
  fi

  _ai_save_turn "$context" "$prompt" "$assistant_response" || {
    _ai_error "Could not save context."
    return 1
  }
}

_ai_parsed_prompt=""
_ai_parsed_model=""
_ai_parsed_system_prompt=""
_ai_parsed_force_reset=false

_ai_parse_prompt() {
  _ai_parsed_prompt=""
  _ai_parsed_model="$1"
  _ai_parsed_system_prompt="$2"
  _ai_parsed_force_reset="$3"
  shift 3

  local remaining=()
  local arg next line multiline=false

  while (( $# > 0 )); do
    arg="$1"
    case "$arg" in
      -r|--reset)
        _ai_parsed_force_reset=true
        shift
        ;;
      -m|--model)
        shift
        if (( $# == 0 )) || [[ "$1" == -* ]]; then
          _ai_error "$arg requires a model name."
          return 1
        fi
        _ai_parsed_model="$1"
        shift
        ;;
      -s|--system)
        shift
        if (( $# == 0 )); then
          _ai_error "$arg requires a prompt."
          return 1
        fi
        _ai_parsed_system_prompt="$1"
        _ai_parsed_force_reset=true
        shift
        ;;
      '"""')
        if (( $# != 1 )); then
          _ai_error '""" must be the final argument.'
          return 1
        fi
        multiline=true
        shift
        break
        ;;
      -*)
        _ai_error "Unknown option: $arg"
        _ai_help
        return 1
        ;;
      *)
        remaining=("$@")
        break
        ;;
    esac
  done

  if [[ "$multiline" == true ]]; then
    print -u2 -- 'Entering multi-line mode. End with """ on its own line.'
    _ai_parsed_prompt=""
    while IFS= read -r line; do
      [[ "$line" == '"""' ]] && break
      _ai_parsed_prompt+="${line}"$'\n'
    done
    _ai_parsed_prompt="${_ai_parsed_prompt%$'\n'}"
  else
    _ai_parsed_prompt="${remaining[*]}"
  fi
}

_ai_main() {
  _ai_require_commands || return 1
  _ai_load_settings || return 1
  _ai_ensure_files || return 1

  case "${1:-}" in
    -h|--help)
      _ai_help
      return 0
      ;;
    --info)
      if [[ "${2:-}" == "context" ]]; then
        _ai_context_info
        return 0
      fi
      _ai_error "Unknown --info target: ${2:-}"
      return 1
      ;;
    --reset)
      _ai_reset_context
      return $?
      ;;
    --doctor)
      _ai_doctor
      return $?
      ;;
    --models)
      _ai_models
      return $?
      ;;
    --show-settings)
      print -- "personal_ollama_cli $_AI_VERSION"
      print -- "Model:        $_ai_conf_model"
      print -- "API URL:      $(_ai_chat_url)"
      print -- "Keep alive:   ${_ai_conf_keep_alive:-default}"
      print -- "Think:        ${_ai_conf_think:-default}"
      print -- "num_ctx:      ${_ai_conf_num_ctx:-default}"
      print -- "Context max:  $_ai_conf_max_context_messages messages"
      print -- "Settings:     $_AI_SETTINGS_FILE"
      print -- "Notes:        $_AI_NOTES_FILE"
      print -- "System:       $_AI_SYSTEM_PROMPT_FILE"
      print -- "Context:      $_AI_CONTEXT_FILE"
      return 0
      ;;
    --view-notes)
      _ai_view_file "notes" "$_AI_NOTES_FILE"
      return $?
      ;;
    --view-system)
      _ai_view_file "system prompt" "$_AI_SYSTEM_PROMPT_FILE"
      return $?
      ;;
    --edit-notes)
      _ai_edit_file "notes" "$_AI_NOTES_FILE"
      return $?
      ;;
    --edit-system)
      _ai_edit_file "system prompt" "$_AI_SYSTEM_PROMPT_FILE"
      return $?
      ;;
    --edit-settings)
      _ai_edit_file "settings" "$_AI_SETTINGS_FILE"
      return $?
      ;;
  esac

  local prompt=""
  local model="$_ai_conf_model"
  local system_prompt=""
  local force_reset=false
  local notes=""

  [[ -r "$_AI_SYSTEM_PROMPT_FILE" ]] && system_prompt="$(cat "$_AI_SYSTEM_PROMPT_FILE")"

  _ai_parse_prompt "$model" "$system_prompt" "$force_reset" "$@" || return 1
  prompt="$_ai_parsed_prompt"
  model="$_ai_parsed_model"
  system_prompt="$_ai_parsed_system_prompt"
  force_reset="$_ai_parsed_force_reset"

  if [[ "$force_reset" == true ]]; then
    _ai_reset_context || return 1
    [[ -z "$prompt" ]] && return 0
  fi

  if [[ -z "$prompt" ]]; then
    _ai_error "No prompt provided."
    return 1
  fi

  [[ -r "$_AI_NOTES_FILE" ]] && notes="$(cat "$_AI_NOTES_FILE")"

  _ai_stream_chat "$prompt" "$model" "$system_prompt" "$notes"
}

alias ai='noglob _ai_main'
