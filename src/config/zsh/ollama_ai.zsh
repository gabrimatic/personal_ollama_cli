# personal_ollama_cli
# Source this file from zsh to expose the `ai` command.

_AI_VERSION="2.1.0"

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
_ai_conf_format=""
_ai_conf_connect_timeout=""
_ai_conf_request_timeout=""
_ai_conf_context_lock_timeout=""
_ai_conf_show_stats=""

_AI_ACTIVE_LOCK_DIR=""

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

_ai_bool_value() {
  case "$1" in
    true|TRUE|True|1|yes|YES|Yes|on|ON|On) print -r -- "true" ;;
    false|FALSE|False|0|no|NO|No|off|OFF|Off) print -r -- "false" ;;
    *) return 1 ;;
  esac
}

_ai_require_commands() {
  local dep missing=()
  for dep in jq curl mkdir mv dirname mktemp cat touch sleep rmdir cp chmod date rm; do
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
  _ai_conf_format=""
  _ai_conf_connect_timeout="5"
  _ai_conf_request_timeout="300"
  _ai_conf_context_lock_timeout="10"
  _ai_conf_show_stats="false"

  [[ -r "$_AI_SETTINGS_FILE" ]] || return 0

  local raw key value bool_value
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    raw="$(_ai_trim "$raw")"
    [[ -z "$raw" || "$raw" == \#* ]] && continue
    [[ "$raw" == *"="* ]] || continue

    key="$(_ai_trim "${raw%%=*}")"
    value="$(_ai_trim "${raw#*=}")"
    value="${value%%#*}"
    value="$(_ai_trim "$value")"
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
      AI_RESPONSE_FORMAT)
        _ai_conf_format="$value"
        ;;
      AI_CONNECT_TIMEOUT)
        if [[ "$value" =~ '^[0-9]+$' && "$value" -gt 0 ]]; then
          _ai_conf_connect_timeout="$value"
        else
          _ai_warn "Invalid AI_CONNECT_TIMEOUT in settings: $value. Using $_ai_conf_connect_timeout."
        fi
        ;;
      AI_REQUEST_TIMEOUT)
        if [[ "$value" =~ '^[0-9]+$' && "$value" -gt 0 ]]; then
          _ai_conf_request_timeout="$value"
        else
          _ai_warn "Invalid AI_REQUEST_TIMEOUT in settings: $value. Using $_ai_conf_request_timeout."
        fi
        ;;
      AI_CONTEXT_LOCK_TIMEOUT)
        if [[ "$value" =~ '^[0-9]+$' ]]; then
          _ai_conf_context_lock_timeout="$value"
        else
          _ai_warn "Invalid AI_CONTEXT_LOCK_TIMEOUT in settings: $value. Using $_ai_conf_context_lock_timeout."
        fi
        ;;
      AI_SHOW_STATS)
        if bool_value="$(_ai_bool_value "$value")"; then
          _ai_conf_show_stats="$bool_value"
        else
          _ai_warn "Invalid AI_SHOW_STATS in settings: $value. Using $_ai_conf_show_stats."
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
    chmod 0600 "$_AI_CONTEXT_FILE" 2>/dev/null || true
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

_ai_normalize_context_json() {
  jq -c '
    if type != "array" then
      error("context must be a JSON array")
    else
      [
        .[]
        | select(type == "object")
        | select((.role == "user") or (.role == "assistant"))
        | select((.content // "") | type == "string")
        | {role, content}
      ]
    end
  ' 2>/dev/null
}

_ai_validate_context_json() {
  jq -c '
    if (
      type == "array"
      and all(.[]; (
        type == "object"
        and ((.role == "user") or (.role == "assistant"))
        and ((.content // null) | type == "string")
      ))
    ) then
      map({role, content})
    else
      error("context must be an array of user or assistant messages")
    end
  ' 2>/dev/null
}

_ai_load_context() {
  local normalized
  if [[ -r "$_AI_CONTEXT_FILE" ]]; then
    normalized="$(_ai_validate_context_json < "$_AI_CONTEXT_FILE")"
    if [[ $? -eq 0 && -n "$normalized" ]]; then
      print -r -- "$normalized"
      return 0
    fi
    _ai_warn "Context file is not a valid saved chat history. Starting with an empty context."
    normalized="$(_ai_normalize_context_json < "$_AI_CONTEXT_FILE")"
    if [[ $? -eq 0 && -n "$normalized" ]]; then
      print -r -- "$normalized"
      return 0
    fi
  fi
  print -r -- "[]"
}

_ai_write_context() {
  local json="$1"
  local normalized tmp
  normalized="$(print -r -- "$json" | _ai_normalize_context_json)" || return 1
  tmp="$(mktemp "${_AI_CONTEXT_FILE}.XXXXXX")" || return 1
  print -r -- "$normalized" > "$tmp" || {
    command rm -f "$tmp" 2>/dev/null
    return 1
  }
  chmod 0600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$_AI_CONTEXT_FILE"
}

_ai_acquire_context_lock() {
  local lock_dir="${_AI_CONTEXT_FILE}.lock"
  local waited=0
  local timeout="$_ai_conf_context_lock_timeout"

  while ! mkdir "$lock_dir" 2>/dev/null; do
    if (( waited >= timeout )); then
      _ai_error "Timed out waiting for context lock: $lock_dir"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  _AI_ACTIVE_LOCK_DIR="$lock_dir"
  print -r -- "$$" > "$lock_dir/pid" 2>/dev/null || true
}

_ai_release_context_lock() {
  if [[ -n "$_AI_ACTIVE_LOCK_DIR" ]]; then
    command rm -f "$_AI_ACTIVE_LOCK_DIR/pid" 2>/dev/null || true
    rmdir "$_AI_ACTIVE_LOCK_DIR" 2>/dev/null || true
    _AI_ACTIVE_LOCK_DIR=""
  fi
}

_ai_reset_context() {
  mkdir -p "$(dirname "$_AI_CONTEXT_FILE")" || return 1
  _ai_acquire_context_lock || return 1
  _ai_write_context "[]"
  local rc=$?
  _ai_release_context_lock
  [[ "$rc" -eq 0 ]] || return "$rc"
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

_ai_view_context() {
  local context
  context="$(_ai_load_context)"
  if [[ "$(jq 'length' <<< "$context")" == "0" ]]; then
    print -- "Context is empty."
    return 0
  fi
  jq -r '
    to_entries[]
    | "\(.key + 1). \(.value.role)\n\(.value.content)\n"
  ' <<< "$context"
}

_ai_export_context() {
  local target="${1:-}"
  local context
  context="$(_ai_load_context)"

  if [[ -z "$target" || "$target" == "-" ]]; then
    print -r -- "$context" | jq .
    return $?
  fi

  mkdir -p "$(dirname "$target")" || return 1
  print -r -- "$context" | jq . > "$target" || return 1
  chmod 0600 "$target" 2>/dev/null || true
  print -- "Exported context: $target"
}

_ai_import_context() {
  local source="$1"
  local normalized

  if [[ ! -r "$source" ]]; then
    _ai_error "Cannot read context file: $source"
    return 1
  fi

  normalized="$(_ai_validate_context_json < "$source")" || {
    _ai_error "Context import must be a JSON array of {role, content} messages."
    return 1
  }

  _ai_acquire_context_lock || return 1
  _ai_write_context "$normalized"
  local rc=$?
  _ai_release_context_lock
  [[ "$rc" -eq 0 ]] || return "$rc"
  print -- "Imported context: $source"
}

_ai_help() {
  cat <<EOF
Usage:
  ai [options] "prompt"
  ai [options] \"\"\"
  command-output | ai [options] "instruction"
  ai <command>

Talk to a local Ollama model through the chat API.

Options:
  -m, --model MODEL       Use a different model for this request.
  -s, --system PROMPT     Use a one-off system prompt and reset context first.
  -r, --reset             Reset context before the prompt. Used alone, only resets.
  --no-context            Do not read or save conversation context for this request.
  --no-save               Read context, but do not save this turn.
  --no-notes              Do not include persistent notes.
  --no-system             Do not include the saved system prompt.
  --stdin                 Read stdin even when it is attached to a terminal.
  --json                  Ask Ollama for JSON mode.
  --format VALUE          Set Ollama response format, for example json.
  --think VALUE           Set Ollama thinking mode: true, false, low, medium, high.
  --keep-alive VALUE      Override model keep-alive for this request.
  --num-ctx TOKENS        Override Ollama num_ctx for this request.
  --stats                 Print final token and duration stats to stderr.
  -h, --help              Show this help.

Commands:
  --info context          Show saved conversation size.
  --view-context          Print saved context as readable turns.
  --export-context [PATH] Export saved context JSON. Prints to stdout without PATH.
  --import-context PATH   Replace saved context from a JSON export.
  --reset                 Clear saved conversation context.
  --doctor                Check dependencies, Ollama reachability, and default model.
  --models                List models from the local Ollama server.
  --status                List currently running Ollama models.
  --version               Print the installed command version.
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
  local ok=true base tags tags_status model_found
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
  tags="$(curl --silent --show-error --connect-timeout "$_ai_conf_connect_timeout" --max-time 10 "$base/api/tags" 2>/dev/null)"
  tags_status=$?
  if [[ "$tags_status" == "0" ]] && jq -e '.models | type == "array"' <<< "$tags" >/dev/null 2>&1; then
    print -- "ok: Ollama reachable at $base"
    model_found="$(jq -r --arg model "$_ai_conf_model" 'first(.models[]?.name | select(. == $model)) // ""' <<< "$tags")"
    if [[ -n "$model_found" ]]; then
      print -- "ok: default model installed ($_ai_conf_model)"
    else
      print -- "warning: default model is not installed ($_ai_conf_model)"
      ok=false
    fi
  else
    print -- "warning: Ollama was not reachable at $base"
    ok=false
  fi

  $ok
}

_ai_models() {
  local base
  base="$(_ai_base_url)"
  curl --fail --silent --show-error --connect-timeout "$_ai_conf_connect_timeout" --max-time 10 "$base/api/tags" |
    jq -r '.models[]? | "\(.name)\t\(.details.parameter_size // "-")\t\(.modified_at)"'
}

_ai_status() {
  local base
  base="$(_ai_base_url)"
  curl --fail --silent --show-error --connect-timeout "$_ai_conf_connect_timeout" --max-time 10 "$base/api/ps" |
    jq -r '
      if (.models | length) == 0 then
        "No models currently loaded."
      else
        .models[] | "\(.name // .model)\t\(.details.parameter_size // "-")\tuntil \(.expires_at // "-")"
      end
    '
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

_ai_format_payload_value() {
  local format="$1"
  jq -n --arg format "$format" 'try ($format | fromjson) catch $format'
}

_ai_print_stats() {
  local final_meta="$1"
  [[ -n "$final_meta" ]] || return 0

  jq -r '
    [
      "model=\(.model // "-")",
      "done_reason=\(.done_reason // "-")",
      "prompt_tokens=\(.prompt_eval_count // "-")",
      "output_tokens=\(.eval_count // "-")",
      "total_ms=\((.total_duration // 0) / 1000000 | floor)"
    ] | "[stats] " + join(" ")
  ' <<< "$final_meta" >&2 2>/dev/null || true
}

_ai_stream_chat() {
  local prompt="$1"
  local model="$2"
  local system_prompt="$3"
  local notes="$4"
  local use_context="$5"
  local save_context="$6"
  local think="$7"
  local keep_alive="$8"
  local num_ctx="$9"
  local format="${10}"
  local show_stats="${11}"
  local context messages payload url status_file curl_status line chunk err done assistant_response final_meta payload_format
  local lock_acquired=false

  if [[ "$save_context" == true ]]; then
    _ai_acquire_context_lock || return 1
    lock_acquired=true
  fi

  if [[ "$use_context" == true ]]; then
    context="$(_ai_load_context)"
  else
    context="[]"
  fi

  messages="$(_ai_build_messages "$context" "$prompt" "$system_prompt" "$notes")" || {
    [[ "$lock_acquired" == true ]] && _ai_release_context_lock
    _ai_error "Could not build chat messages."
    return 1
  }

  if [[ -n "$format" ]]; then
    payload_format="$(_ai_format_payload_value "$format")" || {
      [[ "$lock_acquired" == true ]] && _ai_release_context_lock
      _ai_error "Could not parse response format."
      return 1
    }
  else
    payload_format="null"
  fi

  payload="$(jq -n \
    --arg model "$model" \
    --argjson messages "$messages" \
    --arg keep_alive "$keep_alive" \
    --arg think "$think" \
    --arg num_ctx "$num_ctx" \
    --argjson format "$payload_format" '
      {
        model: $model,
        messages: $messages,
        stream: true
      }
      + (if ($keep_alive | length) > 0 then {keep_alive: $keep_alive} else {} end)
      + (if ($think | length) > 0 then {think: (if $think == "true" then true elif $think == "false" then false else $think end)} else {} end)
      + (if ($num_ctx | length) > 0 then {options: {num_ctx: ($num_ctx | tonumber)}} else {} end)
      + (if $format != null then {format: $format} else {} end)
    ')" || {
      [[ "$lock_acquired" == true ]] && _ai_release_context_lock
      _ai_error "Could not build request payload."
      return 1
    }

  url="$(_ai_chat_url)"
  status_file="$(mktemp "${TMPDIR:-/tmp}/personal_ollama_cli.curl_status.XXXXXX")" || {
    [[ "$lock_acquired" == true ]] && _ai_release_context_lock
    return 1
  }
  assistant_response=""
  final_meta=""
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
    [[ "$done" == "true" ]] && final_meta="$line"
  done < <(
    curl --fail --silent --show-error -N \
      --connect-timeout "$_ai_conf_connect_timeout" \
      --max-time "$_ai_conf_request_timeout" \
      -H "Content-Type: application/json" \
      -X POST "$url" \
      -d "$payload"
    print -r -- "$?" > "$status_file"
  )

  [[ -n "$assistant_response" ]] && print
  curl_status="$(cat "$status_file" 2>/dev/null)"
  command rm -f "$status_file" 2>/dev/null || true

  if [[ -n "$err" ]]; then
    [[ "$lock_acquired" == true ]] && _ai_release_context_lock
    print -u2 -- "[Info] Context not saved due to API error."
    return 1
  fi

  if [[ "${curl_status:-1}" != "0" ]]; then
    [[ "$lock_acquired" == true ]] && _ai_release_context_lock
    _ai_error "Ollama request failed. Check that Ollama is running and reachable at $url."
    return 1
  fi

  if [[ "$done" != "true" ]]; then
    [[ "$lock_acquired" == true ]] && _ai_release_context_lock
    _ai_warn "Stream ended before Ollama sent done=true. Context not saved."
    return 1
  fi

  if [[ -z "$assistant_response" ]]; then
    [[ "$lock_acquired" == true ]] && _ai_release_context_lock
    _ai_warn "Ollama returned an empty response. Context not saved."
    return 1
  fi

  if [[ "$save_context" == true ]]; then
    _ai_save_turn "$context" "$prompt" "$assistant_response" || {
      _ai_release_context_lock
      _ai_error "Could not save context."
      return 1
    }
  fi

  [[ "$lock_acquired" == true ]] && _ai_release_context_lock
  [[ "$show_stats" == true ]] && _ai_print_stats "$final_meta"
  return 0
}

_ai_parsed_prompt=""
_ai_parsed_model=""
_ai_parsed_system_prompt=""
_ai_parsed_force_reset=false
_ai_parsed_use_context=true
_ai_parsed_save_context=true
_ai_parsed_use_notes=true
_ai_parsed_use_system=true
_ai_parsed_read_stdin=false
_ai_parsed_format=""
_ai_parsed_think=""
_ai_parsed_keep_alive=""
_ai_parsed_num_ctx=""
_ai_parsed_show_stats=false

_ai_parse_prompt() {
  _ai_parsed_prompt=""
  _ai_parsed_model="$1"
  _ai_parsed_system_prompt="$2"
  _ai_parsed_force_reset=false
  _ai_parsed_use_context=true
  _ai_parsed_save_context=true
  _ai_parsed_use_notes=true
  _ai_parsed_use_system=true
  _ai_parsed_read_stdin=false
  _ai_parsed_format="$_ai_conf_format"
  _ai_parsed_think="$_ai_conf_think"
  _ai_parsed_keep_alive="$_ai_conf_keep_alive"
  _ai_parsed_num_ctx="$_ai_conf_num_ctx"
  _ai_parsed_show_stats="$_ai_conf_show_stats"
  shift 2

  local remaining=()
  local arg line stdin_content multiline=false

  while (( $# > 0 )); do
    arg="$1"
    case "$arg" in
      --)
        shift
        remaining=("$@")
        break
        ;;
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
      --no-context)
        _ai_parsed_use_context=false
        _ai_parsed_save_context=false
        shift
        ;;
      --no-save)
        _ai_parsed_save_context=false
        shift
        ;;
      --no-notes)
        _ai_parsed_use_notes=false
        shift
        ;;
      --no-system)
        _ai_parsed_use_system=false
        shift
        ;;
      --stdin)
        _ai_parsed_read_stdin=true
        shift
        ;;
      --json)
        _ai_parsed_format="json"
        shift
        ;;
      --format)
        shift
        if (( $# == 0 )); then
          _ai_error "$arg requires a value."
          return 1
        fi
        _ai_parsed_format="$1"
        shift
        ;;
      --think)
        shift
        if (( $# == 0 )); then
          _ai_error "$arg requires a value."
          return 1
        fi
        _ai_parsed_think="$1"
        shift
        ;;
      --keep-alive)
        shift
        if (( $# == 0 )); then
          _ai_error "$arg requires a value."
          return 1
        fi
        _ai_parsed_keep_alive="$1"
        shift
        ;;
      --num-ctx)
        shift
        if (( $# == 0 )) || [[ ! "$1" =~ '^[0-9]+$' ]]; then
          _ai_error "$arg requires a positive integer."
          return 1
        fi
        _ai_parsed_num_ctx="$1"
        shift
        ;;
      --stats)
        _ai_parsed_show_stats=true
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

  if [[ "$_ai_parsed_use_system" != true ]]; then
    _ai_parsed_system_prompt=""
  fi

  if [[ "$multiline" == true ]]; then
    print -u2 -- 'Entering multi-line mode. End with """ on its own line.'
    while IFS= read -r line; do
      [[ "$line" == '"""' ]] && break
      _ai_parsed_prompt+="${line}"$'\n'
    done
    _ai_parsed_prompt="${_ai_parsed_prompt%$'\n'}"
  else
    _ai_parsed_prompt="${remaining[*]}"
  fi

  if [[ "$_ai_parsed_read_stdin" == true || ! -t 0 ]]; then
    stdin_content="$(cat)"
    if [[ -n "$stdin_content" ]]; then
      if [[ -n "$_ai_parsed_prompt" ]]; then
        _ai_parsed_prompt="${_ai_parsed_prompt}"$'\n\n'"$stdin_content"
      else
        _ai_parsed_prompt="$stdin_content"
      fi
    fi
  fi
}

_ai_show_settings() {
  print -- "personal_ollama_cli $_AI_VERSION"
  print -- "Model:        $_ai_conf_model"
  print -- "API URL:      $(_ai_chat_url)"
  print -- "Keep alive:   ${_ai_conf_keep_alive:-default}"
  print -- "Think:        ${_ai_conf_think:-default}"
  print -- "Format:       ${_ai_conf_format:-default}"
  print -- "num_ctx:      ${_ai_conf_num_ctx:-default}"
  print -- "Context max:  $_ai_conf_max_context_messages messages"
  print -- "Connect:      $_ai_conf_connect_timeout seconds"
  print -- "Request:      $_ai_conf_request_timeout seconds"
  print -- "Lock wait:    $_ai_conf_context_lock_timeout seconds"
  print -- "Stats:        $_ai_conf_show_stats"
  print -- "Settings:     $_AI_SETTINGS_FILE"
  print -- "Notes:        $_AI_NOTES_FILE"
  print -- "System:       $_AI_SYSTEM_PROMPT_FILE"
  print -- "Context:      $_AI_CONTEXT_FILE"
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
    --version)
      print -- "$_AI_VERSION"
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
    --view-context)
      _ai_view_context
      return $?
      ;;
    --export-context)
      _ai_export_context "${2:-}"
      return $?
      ;;
    --import-context)
      if [[ -z "${2:-}" ]]; then
        _ai_error "--import-context requires a path."
        return 1
      fi
      _ai_import_context "$2"
      return $?
      ;;
    --reset)
      if (( $# == 1 )); then
        _ai_reset_context
        return $?
      fi
      ;;
    --doctor)
      _ai_doctor
      return $?
      ;;
    --models)
      _ai_models
      return $?
      ;;
    --status)
      _ai_status
      return $?
      ;;
    --show-settings)
      _ai_show_settings
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
  local notes=""

  [[ -r "$_AI_SYSTEM_PROMPT_FILE" ]] && system_prompt="$(cat "$_AI_SYSTEM_PROMPT_FILE")"

  _ai_parse_prompt "$model" "$system_prompt" "$@" || return 1
  prompt="$_ai_parsed_prompt"
  model="$_ai_parsed_model"
  system_prompt="$_ai_parsed_system_prompt"

  if [[ "$_ai_parsed_force_reset" == true ]]; then
    _ai_reset_context || return 1
    [[ -z "$prompt" ]] && return 0
  fi

  if [[ -z "$prompt" ]]; then
    _ai_error "No prompt provided."
    return 1
  fi

  if [[ "$_ai_parsed_use_notes" == true && -r "$_AI_NOTES_FILE" ]]; then
    notes="$(cat "$_AI_NOTES_FILE")"
  fi

  _ai_stream_chat \
    "$prompt" \
    "$model" \
    "$system_prompt" \
    "$notes" \
    "$_ai_parsed_use_context" \
    "$_ai_parsed_save_context" \
    "$_ai_parsed_think" \
    "$_ai_parsed_keep_alive" \
    "$_ai_parsed_num_ctx" \
    "$_ai_parsed_format" \
    "$_ai_parsed_show_stats"
}

alias ai='noglob _ai_main'
