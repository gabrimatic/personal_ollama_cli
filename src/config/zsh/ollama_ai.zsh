# ~/.config/zsh/ollama_ai.zsh
# Polished 'ai' function for Ollama Interaction (File-Based Config).
# Features: Streaming, Rolling Context (Strict Pruning), Persistent Notes,
#           System Prompt File, Multi-line Input, Configurable, Action Commands.
# Author: gabrimatic.info
# Version: (v1.0.0)

# These define the standard locations used by the script.
# The settings file itself:
_AI_SETTINGS_FILE="$HOME/.config/ollama/ai_settings.conf"
# Files managed by the script (content comes from settings or defaults):
_AI_CONTEXT_FILE="$HOME/.cache/ollama_ai_context.json"
_AI_NOTES_FILE="$HOME/.config/ollama/ai_persistent_notes.txt"
_AI_SYSTEM_PROMPT_FILE="$HOME/.config/ollama/ai_system_prompt.txt"

# --- Configuration Variables (Populated from settings file) ---
_ai_conf_model=""
_ai_conf_api_url=""
_ai_conf_max_context_tokens=""

# --- Function to Load Core Settings (Model, API, Tokens ONLY) ---
# Reads $_AI_SETTINGS_FILE and validates mandatory keys. Uses reliable defaults if missing.
_ai_load_settings() {
    # Define reliable defaults for core operational settings
    local default_model="gemma3:4b-it-qat"
    local default_api_url="http://localhost:11434/api/generate"
    local default_max_tokens=4096

    # Initialize with defaults
    _ai_conf_model="$default_model"
    _ai_conf_api_url="$default_api_url"
    _ai_conf_max_context_tokens="$default_max_tokens"

    # Check if settings file exists and is readable, otherwise use defaults silently
    if [[ ! -f "$_AI_SETTINGS_FILE" || ! -r "$_AI_SETTINGS_FILE" ]]; then
        # Silently proceed with defaults if file is missing/unreadable
        return 0
    fi

    # Read file line by line, overriding defaults if specified
    local key value value_set
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        key=$(echo "$key" | awk '{$1=$1};1') # Trim key
        value=$(echo "$value" | sed 's/#.*//' | awk '{$1=$1};1') # Remove comments, trim value
        if [[ -z "$key" || "$key" == \#* ]]; then continue; fi # Skip empty/comments

        value_set=false # Flag to check if value is non-empty after trimming
        if [[ -n "$value" ]]; then value_set=true; fi

        case "$key" in
            AI_OLLAMA_MODEL)         if $value_set; then _ai_conf_model="$value"; fi ;;
            AI_OLLAMA_API_URL)       if $value_set; then _ai_conf_api_url="$value"; fi ;;
            AI_MAX_CONTEXT_TOKENS)
                if [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]]; then
                    _ai_conf_max_context_tokens="$value"
                elif $value_set; then # Only warn if a non-empty, invalid value was provided
                    echo "[Warning] Invalid AI_MAX_CONTEXT_TOKENS in settings: '$value'. Using default: $_ai_conf_max_context_tokens" >&2
                fi ;;
            # Ignore path keys from older versions if present
            AI_CONTEXT_FILE_PATH|AI_NOTES_FILE_PATH|AI_SYSTEM_PROMPT_FILE_PATH) ;;
            *) ;; # Ignore unknown keys silently
        esac
    done < "$_AI_SETTINGS_FILE"
    return 0
}

# --- Ensure Directories Exist Function ---
_ai_ensure_dirs() {
    local file_path dir_path
    # Ensure directories for all managed files exist
    for file_path in "$_AI_CONTEXT_FILE" "$_AI_NOTES_FILE" "$_AI_SYSTEM_PROMPT_FILE" "$_AI_SETTINGS_FILE"; do
        if [[ -z "$file_path" ]]; then continue; fi
        dir_path=$(dirname "$file_path")
        if [[ -n "$dir_path" && "$dir_path" != "/" && "$dir_path" != "." ]]; then
            if [[ ! -d "$dir_path" ]]; then
                mkdir -p "$dir_path" || { echo "Error: Cannot create directory $dir_path" >&2; return 1; }
            fi
        fi
    done
    return 0
}

# --- Internal Query Function (Handles API communication and Context) ---
# This function performs the core interaction with the Ollama API.
_ai_ollama_query_and_context() {
  local prompt_text="$1"          # The user's actual prompt
  local model_to_use="$2"         # Effective model (from config or -m flag)
  local system_prompt_to_use="$3" # Effective system prompt (from file or -s flag)
  local notes_content="$4"        # Content read from notes file
  # Use hardcoded paths and loaded config values for API interaction
  local context_file="$_AI_CONTEXT_FILE"
  local max_tokens="$_ai_conf_max_context_tokens"
  local api_url="$_ai_conf_api_url"

  # 1. Inject Persistent Notes into the prompt if they exist
  local final_prompt_text="$prompt_text"
  if [[ -n "$notes_content" ]]; then
      # Basic cleaning for safety
      local clean_notes=$(printf '%s' "$notes_content" | tr -cd "\t\n\r -~")
      if [[ -n "$clean_notes" ]]; then
          # Format clearly for the AI
          final_prompt_text=$(printf "[Persistent Notes For Your Reference:\n%s\n---\nUser Prompt:]\n%s" \
                               "$clean_notes" "$prompt_text")
      fi
  fi

  # 2. Prepare JSON Payload for Ollama API
  local prompt_json_escaped
  prompt_json_escaped=$(printf '%s' "$final_prompt_text" | jq -sRr @json)
  if [[ $? -ne 0 || -z "$prompt_json_escaped" ]]; then echo "Error: Failed to escape final prompt for JSON." >&2; return 1; fi

  # Build the base JSON structure
  local base_payload_jq_script='{model: $model, prompt: $prompt, stream: true}'
  # Add system prompt if it's not empty
  if [[ -n "$system_prompt_to_use" ]]; then
      base_payload_jq_script+=' | . + {system: $system}'
  fi
  # Create the JSON string
  local base_payload
  base_payload=$(jq -n --arg model "$model_to_use" --argjson prompt "$prompt_json_escaped" --arg system "$system_prompt_to_use" "$base_payload_jq_script")
  if [[ $? -ne 0 ]]; then echo "Error: Failed to construct base API payload using jq." >&2; return 1; fi

  # 3. Handle Rolling Conversation Context (Load existing)
  local previous_context_json=""
  if [[ -f "$context_file" && -r "$context_file" ]]; then
      previous_context_json=$(cat "$context_file")
      # Validate it looks like a JSON array
      if ! jq -e '. | type == "array"' <<< "$previous_context_json" > /dev/null 2>&1; then
          echo "[Warning] Invalid rolling context file found ($context_file). Starting new context." >&2
          previous_context_json="" # Discard invalid context
      fi
  fi

  # Construct final payload, merging context if it exists
  local data_payload
  if [[ -n "$previous_context_json" ]]; then
      data_payload=$(jq -n --argjson base "$base_payload" --argjson ctx "$previous_context_json" '$base + {context: $ctx}')
      if [[ $? -ne 0 ]]; then echo "Error: Failed to merge context into API payload using jq." >&2; return 1; fi
  else
      data_payload="$base_payload" # No previous context to merge
  fi

  # 4. Make API Call and Process Stream
  local new_context_to_save="" had_api_error=false response_received=false line
  # Use curl: --fail for HTTP errors, --no-progress-meter for cleaner output, -N for no buffering
  if ! curl --fail --no-progress-meter -N -X POST "$api_url" -H "Content-Type: application/json" -d "$data_payload" \
       | while IFS= read -r line; do # Process output line by line
           if [[ -z "$line" ]]; then continue; fi # Skip empty lines

           # Ensure line is valid JSON before parsing further
           if ! jq -e . <<< "$line" >/dev/null 2>&1; then
               echo "\n[Warning] Received non-JSON line from API stream: $line" >&2
               continue
           fi

           # Extract relevant fields from the JSON chunk
           local resp_chunk=$(jq -r '.response // ""' <<< "$line")
           local is_done=$(jq -r '.done // "false"' <<< "$line")
           local err_msg=$(jq -r '.error // ""' <<< "$line")

           # Print the response chunk to the user immediately
           if [[ -n "$resp_chunk" ]]; then echo -n "$resp_chunk"; response_received=true; fi

           # Check for API errors within the stream
           if [[ -n "$err_msg" ]]; then
               had_api_error=true
               if [[ "$response_received" == true ]]; then echo; fi # Newline if needed
               echo "[API Error] $err_msg" >&2
               break # Stop processing on error
           fi

           # If this is the final chunk, save the context and stop
           if [[ "$is_done" == "true" ]]; then
               new_context_to_save=$(jq -c '.context // null' <<< "$line" 2>/dev/null)
               break
           fi
         done; then
          # This empty 'then' block catches non-zero exit status from the pipeline (e.g., curl failure)
          : # Errors are handled via curl_pipe_status check below
  fi; local curl_pipe_status=$? # Capture overall pipeline status

  if [[ "$response_received" == true ]]; then echo; fi # Ensure final newline after streaming

  # Check for curl errors if no API error was explicitly reported
  if [[ "$curl_pipe_status" -ne 0 && "$had_api_error" == false ]]; then
      echo "Error: API call failed (curl exit status: $curl_pipe_status). Check Ollama server status and API URL ($api_url)." >&2
      return 1
  fi

  # 5. Handle Post-Streaming State and Save Context (Strict Pruning)
  if [[ "$had_api_error" == "true" ]]; then
      echo "[Info] Context not saved due to API error." >&2
      return 1 # Indicate failure
  fi

  # Save context only if successful and context was received
  if [[ -n "$new_context_to_save" ]] && [[ "$new_context_to_save" != "null" ]]; then
      local final_context="$new_context_to_save"
      local context_len=$(jq '. | length' <<< "$new_context_to_save" 2>/dev/null)

      # Prune if context length exceeds the configured maximum
      if [[ -n "$context_len" && "$context_len" -gt "$max_tokens" ]]; then
          local tokens_to_remove=$(( context_len - max_tokens ))
          # Basic sanity check for removal count
          if [[ "$tokens_to_remove" -lt 1 ]]; then tokens_to_remove=1; fi

          echo "[Info] Pruning context: $context_len -> $max_tokens tokens." >&2
          # Use jq array slicing: .[start:] keeps elements from 'start' index onwards
          final_context=$(jq --argjson idx "$tokens_to_remove" '.[$idx:]' <<< "$new_context_to_save")
          if [[ $? -ne 0 ]]; then
              echo "Error: Failed during context pruning with jq. Context not saved." >&2
              rm -f "$context_file" # Remove potentially corrupt file
              return 1
          fi
      fi

      # Final validation before writing
      if jq -e '. | type == "array"' <<< "$final_context" > /dev/null 2>&1; then
         # Write the final context (possibly pruned) to the file
         echo "$final_context" > "$context_file"
         if [[ $? -ne 0 ]]; then echo "Error: Failed writing context file $context_file." >&2; fi
      else
         # Should ideally not happen if pruning worked, but defensive check
         echo "[Warning] Final context content is invalid JSON array. Context not saved." >&2
         rm -f "$context_file"
      fi
  elif [[ "$had_api_error" == false ]]; then
      # Successful stream finish, but no context array found
      echo "[Warning] Could not extract context array from final API response. Context not saved." >&2
  fi

  return 0 # Indicate success
}

# --- Main AI Function (Handles arguments and input) ---
_ai_main() {
  # Check essential dependencies
  local dep err_msg
  for dep in jq curl grep cat rm printf wc touch awk sed dirname; do # Added dependencies for settings parsing
      if ! command -v "$dep" &> /dev/null; then err_msg+="Error: Command '$dep' not found. Please install it.\n"; fi
  done
  if [[ -n "$err_msg" ]]; then echo -e "$err_msg" >&2; return 1; fi

  # --- Load Settings (Mandatory Step) ---
  # Populates _ai_conf_* variables from file or uses reliable defaults for core settings
  _ai_load_settings || return 1 # Exit if loading fails

  # --- Ensure Directories Exist for all managed files ---
  _ai_ensure_dirs "$_AI_CONTEXT_FILE" "$_AI_NOTES_FILE" "$_AI_SYSTEM_PROMPT_FILE" "$_AI_SETTINGS_FILE" || return 1

  # --- Check for ACTION commands FIRST ---
  # These commands execute locally and stop the script immediately.
  case "$1" in
    -h|--help)
        # Generate help text dynamically using current config values
        local help_text=$(cat << EOF
Usage: ai [options] [prompt | \"\"\"]
       ai <command>

Interact with Ollama using streaming responses, rolling context, persistent notes & system prompt.

Core Commands:
  [prompt]            The prompt to send to the AI (if no other command is given).
  \"\"\"               Enter multi-line input mode after options (end with '\"\"\"').
  -h, --help          Show this help message and exit.

Options (can precede prompt or \"\"\", override settings for this run):
  -r, --reset         Reset the conversation context file before sending prompt.
                      If used alone, just resets and exits.
  -m, --model MODEL   Specify the Ollama model for this session (current: $_ai_conf_model).
  -s, --system PROMPT Set a system prompt for this session (overrides file content).
                      (Warning: Resets context if context exists)

Management Commands (execute locally and exit):
  --info context      Show current context token count (Limit: $_ai_conf_max_context_tokens).
  --view-notes        Display the notes file ($_AI_NOTES_FILE).
  --edit-notes        Open the notes file ($_AI_NOTES_FILE) in \$EDITOR.
  --view-system       Display the system prompt file ($_AI_SYSTEM_PROMPT_FILE).
  --edit-system       Open the system prompt file ($_AI_SYSTEM_PROMPT_FILE) in \$EDITOR.
  --show-settings     Display settings loaded from $_AI_SETTINGS_FILE.
  --edit-settings     Open the settings file ($_AI_SETTINGS_FILE) in \$EDITOR.

Configuration Files:
  Settings:   $_AI_SETTINGS_FILE (Optional, defines Model, API URL, Max Tokens)
  Notes:      $_AI_NOTES_FILE (Plain text, manually edited)
  SysPrompt:  $_AI_SYSTEM_PROMPT_FILE (Plain text, manually edited)
  Context:    $_AI_CONTEXT_FILE (JSON, auto-managed)
EOF
)
        echo "$help_text"; return 0 ;;

    --info)
        if [[ "$2" == "context" ]]; then
            if [[ -f "$_AI_CONTEXT_FILE" && -r "$_AI_CONTEXT_FILE" ]]; then
                local token_count=$(jq '. | length' "$_AI_CONTEXT_FILE" 2>/dev/null)
                if [[ $? -eq 0 && -n "$token_count" ]]; then echo "Context: $token_count tokens (Limit: $_ai_conf_max_context_tokens) in $_AI_CONTEXT_FILE";
                else echo "Error parsing context file $_AI_CONTEXT_FILE" >&2; fi
            else echo "No context file found at $_AI_CONTEXT_FILE" >&2; fi; return 0
        else echo "Error: Unknown target for --info: '$2'. Try '--info context'." >&2; return 1; fi ;;

    --edit-notes | --edit-system | --edit-settings)
        local file_to_edit target_name editor_to_use="$EDITOR"
        case "$1" in
           --edit-notes) file_to_edit="$_AI_NOTES_FILE"; target_name="notes";;
           --edit-system) file_to_edit="$_AI_SYSTEM_PROMPT_FILE"; target_name="system prompt";;
           --edit-settings) file_to_edit="$_AI_SETTINGS_FILE"; target_name="settings";;
        esac
        # Find editor if needed
        if [[ -z "$editor_to_use" ]]; then if command -v "nano" &>/dev/null; then editor_to_use="nano"; elif command -v "vim" &>/dev/null; then editor_to_use="vim"; elif command -v "vi" &>/dev/null; then editor_to_use="vi"; else echo "Error: No editor found. Set \$EDITOR or install nano/vim/vi." >&2; return 1; fi; elif ! command -v "$editor_to_use" &>/dev/null; then echo "Error: Editor '$editor_to_use' not found." >&2; return 1; fi
        # Ensure file can be created/written
        touch "$file_to_edit" 2>/dev/null || { echo "Error: Cannot touch $target_name file: $file_to_edit" >&2; return 1; }; if [[ ! -w "$file_to_edit" ]]; then echo "Error: Cannot write $target_name file: $file_to_edit" >&2; return 1; fi
        echo "Opening $target_name file ($file_to_edit) in $editor_to_use..." >&2
        "$editor_to_use" "$file_to_edit"; echo "$target_name file closed." >&2; return 0 ;;

    --view-notes | --view-system)
        local file_to_view target_name header footer
        if [[ "$1" == "--view-notes" ]]; then file_to_view="$_AI_NOTES_FILE"; target_name="Notes"; header="--- Notes ($_AI_NOTES_FILE) ---"; footer="--- End Notes ---";
        else file_to_view="$_AI_SYSTEM_PROMPT_FILE"; target_name="System Prompt"; header="--- System Prompt ($_AI_SYSTEM_PROMPT_FILE) ---"; footer="--- End System Prompt ---"; fi
        if [[ -f "$file_to_view" && -r "$file_to_view" ]]; then echo "$header"; cat "$file_to_view"; echo "$footer";
        else echo "No $target_name file found or readable at $file_to_view" >&2; fi; return 0 ;;

    --show-settings)
        # Display settings that were actually loaded or defaulted
        echo "Effective AI Settings:"
        echo "  Model (-m overrides):  $_ai_conf_model"
        echo "  API URL:             $_ai_conf_api_url"
        echo "  Max Context Tokens:  $_ai_conf_max_context_tokens"
        echo "--- File Paths Used ---"
        echo "  Context File:        $_AI_CONTEXT_FILE"
        echo "  Notes File:          $_AI_NOTES_FILE"
        echo "  System Prompt File:  $_AI_SYSTEM_PROMPT_FILE"
        echo "  Settings File Src:   $_AI_SETTINGS_FILE"
        return 0 ;;

    # If $1 wasn't an action command, fall through
    *) ;;
  esac
  # --- END ACTION COMMAND CHECK ---

  # --- Normal Prompt/Flag Processing ---
  # Initialize effective values for this run
  local prompt=""
  local effective_model="$_ai_conf_model"    # Start with configured model
  local effective_system_prompt=""          # Start empty, load from file
  local force_context_reset=false
  local in_multiline=false
  local multiline_content=""
  local system_flag_used=false # Track if -s flag was used

  # Load initial system prompt from its fixed file path
  if [[ -f "$_AI_SYSTEM_PROMPT_FILE" && -r "$_AI_SYSTEM_PROMPT_FILE" ]]; then
      effective_system_prompt=$(cat "$_AI_SYSTEM_PROMPT_FILE")
  fi

  # Parse remaining arguments for flags and prompt
  local args_for_flags=("$@")
  local remaining_args=()
  local i=0
  while [[ $i -lt ${#args_for_flags[@]} ]]; do
    local arg="${args_for_flags[$i]}"
    case "$arg" in
      # Skip action commands already handled
      -h|--help|--info|--edit-*|--view-*|--show-settings) ((i++)); if [[ "$arg" == "--info" ]]; then ((i++)); fi; continue ;;

      -r|--reset) force_context_reset=true; ((i++)); continue ;;
      -m|--model)
        local model_arg="${args_for_flags[$((i+1))]}"
        if [[ $i+1 -ge ${#args_for_flags[@]} || -z "$model_arg" || "$model_arg" == -* ]]; then echo "Error: -m requires value." >&2; return 1; fi
        effective_model="$model_arg"; i=$((i+2)); continue ;; # Flag overrides
      -s|--system)
        local system_arg="${args_for_flags[$((i+1))]}"
        if [[ $i+1 -ge ${#args_for_flags[@]} ]]; then echo "Error: -s requires value ('')." >&2; return 1; fi # Check index exists
        effective_system_prompt="$system_arg"; system_flag_used=true; i=$((i+2)); continue ;; # Flag overrides file content
      \"\"\") # Multi-line trigger
         if [[ $((i+1)) -eq ${#args_for_flags[@]} ]]; then in_multiline=true; i=$((i+1)); break; else echo "Error: '\"\"\"' must be last arg." >&2; return 1; fi ;;
      -*) # Unknown flag
         echo "Error: Unknown option: $arg" >&2; _ai_main -h; return 1 ;;
      *) # Not a flag, assume start of prompt
         remaining_args=("${args_for_flags[@]:$i}"); break ;; # Capture rest and break loop
    esac
  done

  # Assign prompt from remaining args if not multi-line
  if [[ "$in_multiline" == false ]]; then prompt="${remaining_args[*]}"; fi

  # Read multi-line input if triggered
  if [[ "$in_multiline" == true ]]; then
      echo "Entering multi-line mode (end with '\"\"\"' on a new line)..." >&2; local line
      while IFS= read -r line; do if printf '%s' "$line" | grep -Fxq '"""'; then break; fi; multiline_content+="$line"$'\n'; done
      # Use content or set empty if user just entered """ twice
      if [[ -n "$multiline_content" ]]; then prompt="${multiline_content%?}"; else prompt=""; fi
  fi

  # Handle context reset if needed (-r OR -s used with existing context)
  # Resetting due to -s only happens if the flag was actually used
  if [[ "$system_flag_used" == true && -f "$_AI_CONTEXT_FILE" && -s "$_AI_CONTEXT_FILE" ]]; then
      echo "[Info] Using -s flag with existing context forces context reset." >&2; force_context_reset=true;
  fi
  if [[ "$force_context_reset" == true ]]; then
      # Ensure the directory for the context file exists (though _ai_ensure_dirs should have done this)
      # mkdir -p "$(dirname "$_AI_CONTEXT_FILE")" # Usually not needed if _ai_ensure_dirs is robust
      echo "[]" > "$_AI_CONTEXT_FILE"
      echo "[Info] Conversation context reset and cleared." >&2
      # Exit if ONLY reset was intended (no prompt followed)
      if [[ -z "$prompt" && "$in_multiline" == false ]]; then return 0; fi
  fi

  # Final check for empty prompt if no action/reset-only occurred
  if [[ -z "$prompt" && "$in_multiline" == false ]]; then
      echo "Error: No prompt provided." >&2; return 1;
  fi

  # Read Persistent Notes (using fixed path)
  local notes_content=""
  if [[ -f "$_AI_NOTES_FILE" && -r "$_AI_NOTES_FILE" ]]; then
      notes_content=$(cat "$_AI_NOTES_FILE")
  fi

  # --- Call the Internal Query Function ---
  # Passes the final effective model, system prompt, notes, and user prompt
  _ai_ollama_query_and_context "$prompt" "$effective_model" "$effective_system_prompt" "$notes_content"
  return $? # Propagate exit status
}

# Alias 'ai' to call the main function using 'noglob' to prevent shell expansion of args
alias ai='noglob _ai_main'

# --- End Ollama Integration --- 