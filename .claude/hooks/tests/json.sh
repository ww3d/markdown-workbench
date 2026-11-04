#!/usr/bin/env bash
#
# Sourced by harness.sh and mkfixtures.sh: JSON text built without a process. Under Git Bash every `jq -cn`
# costs a process start (about 40 ms measured, ww3d/playbook#427), and the suite builds thousands of inputs.
#
#   js <string>   sets REPLY to the JSON string literal `jq -c` writes for it
#                 (valid UTF-8; jq writes U+FFFD for invalid bytes)
#
# cases/harness-parity.sh holds js against jq and the harness against the real hook call.

js() { # string -> REPLY
  local s="$1" out="" c i
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  case "$s" in *[$'\001'-$'\037\177']*)
    s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"; s="${s//$'\b'/\\b}"; s="${s//$'\f'/\\f}"
    case "$s" in *[$'\001'-$'\037\177']*)
      for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in [$'\001'-$'\037\177']) printf -v c '\\u%04x' "'$c" ;; esac
        out+="$c"
      done
      s="$out" ;;
    esac ;;
  esac
  REPLY="\"$s\""
}
