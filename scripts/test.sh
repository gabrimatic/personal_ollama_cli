#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CLI_FILE="$ROOT_DIR/src/config/zsh/ollama_ai.zsh"

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_json() {
  local file="$1"
  local filter="$2"
  jq -e "$filter" "$file" >/dev/null || fail "JSON assertion failed: $filter"
}

make_home() {
  local home
  home="$(mktemp -d)"
  mkdir -p "$home/bin" "$home/.config/ollama" "$home/.cache"
  cat > "$home/bin/curl" <<'MOCK'
#!/usr/bin/env zsh
payload=""
url=""
write_out=""

while (( $# > 0 )); do
  case "$1" in
    -d)
      shift
      payload="$1"
      ;;
    --write-out)
      shift
      write_out="$1"
      ;;
    -X|-H|--connect-timeout|--max-time|--output)
      shift
      ;;
    --fail|--silent|--show-error|-N)
      ;;
    *)
      url="$1"
      ;;
  esac
  shift
done

[[ -n "${AI_TEST_LAST_PAYLOAD:-}" ]] && print -r -- "$payload" > "$AI_TEST_LAST_PAYLOAD"
[[ -n "${AI_TEST_LAST_URL:-}" ]] && print -r -- "$url" > "$AI_TEST_LAST_URL"

if [[ "$url" == */api/tags ]]; then
  if [[ -n "$write_out" ]]; then
    print -n -- "200"
  else
    print -r -- '{"models":[{"name":"gemma3:4b","modified_at":"2026-01-01T00:00:00Z","details":{"parameter_size":"4B"}}]}'
  fi
  exit 0
fi

print -r -- '{"message":{"role":"assistant","content":"hello"},"done":false}'
print -r -- '{"message":{"role":"assistant","content":" world"},"done":true}'
MOCK
  chmod +x "$home/bin/curl"

  cat > "$home/.config/ollama/ai_settings.conf" <<'CONF'
AI_OLLAMA_MODEL=gemma3:4b
AI_OLLAMA_API_URL=http://localhost:11434/api/chat
AI_MAX_CONTEXT_MESSAGES=4
AI_KEEP_ALIVE=5m
CONF
  cat > "$home/.config/ollama/ai_system_prompt.txt" <<'PROMPT'
Keep it short.
PROMPT
  cat > "$home/.config/ollama/ai_persistent_notes.txt" <<'NOTES'
User likes concise answers.
NOTES
  print -r -- "$home"
}

run_ai() {
  local home="$1"
  shift
  HOME="$home" \
  XDG_CONFIG_HOME="$home/.config" \
  XDG_CACHE_HOME="$home/.cache" \
  PATH="$home/bin:$PATH" \
  AI_TEST_LAST_PAYLOAD="$home/payload.json" \
  AI_TEST_LAST_URL="$home/url.txt" \
  zsh -f -c 'source "$1"; shift; _ai_main "$@"' test-shell "$CLI_FILE" "$@"
}

zsh -n "$CLI_FILE"
bash -n "$ROOT_DIR/install.sh"

home="$(make_home)"
install_home=""
trap 'rm -rf "$home" "$install_home"' EXIT

settings_output="$(run_ai "$home" --show-settings)"
assert_contains "$settings_output" "personal_ollama_cli 2.0.0"
assert_contains "$settings_output" "http://localhost:11434/api/chat"

models_output="$(run_ai "$home" --models)"
assert_contains "$models_output" "gemma3:4b"

run_ai "$home" --reset >/tmp/personal_ollama_cli_reset.out 2>/tmp/personal_ollama_cli_reset.err
assert_json "$home/.cache/ollama_ai_context.json" 'length == 0'

prompt_output="$(run_ai "$home" -m qwen3:4b "hello there")"
assert_contains "$prompt_output" "hello world"
assert_json "$home/payload.json" '.model == "qwen3:4b"'
assert_json "$home/payload.json" '.messages[-1].role == "user"'
assert_json "$home/payload.json" '.messages[-1].content == "hello there"'
assert_json "$home/.cache/ollama_ai_context.json" 'length == 2'

printf 'first line\nsecond line\n"""\n' | run_ai "$home" '"""' >/tmp/personal_ollama_cli_multiline.out
assert_json "$home/payload.json" '.messages[-1].content == "first line\nsecond line"'

if run_ai "$home" --bad-option >/tmp/personal_ollama_cli_bad.out 2>/tmp/personal_ollama_cli_bad.err; then
  fail "unknown option should fail"
fi
assert_contains "$(cat /tmp/personal_ollama_cli_bad.err)" "Unknown option: --bad-option"

legacy_home="$(make_home)"
print -r -- "AI_OLLAMA_API_URL=http://localhost:11434/api/generate" > "$legacy_home/.config/ollama/ai_settings.conf"
run_ai "$legacy_home" "legacy url" >/tmp/personal_ollama_cli_legacy.out
assert_contains "$(cat "$legacy_home/url.txt")" "http://localhost:11434/api/chat"
rm -rf "$legacy_home"

install_home="$(mktemp -d)"
HOME="$install_home" "$ROOT_DIR/install.sh" --yes >/tmp/personal_ollama_cli_install.out
[[ -f "$install_home/.config/zsh/ollama_ai.zsh" ]] || fail "installer did not install zsh file"
grep -Fq "_ollama_ai_config_file=\"$install_home/.config/zsh/ollama_ai.zsh\"" "$install_home/.zshrc" || fail "installer wrote the wrong zshrc source block"

print -- "All tests passed."
