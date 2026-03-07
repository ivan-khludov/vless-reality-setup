#!/usr/bin/env bash
# health-responder.sh — health check for VLESS Reality

readonly XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json"
readonly XRAY_BINARY="/usr/local/bin/xray"
readonly XRAY_TEST_TIMEOUT=15

declare -A RESPONSES=(
  [200]='{"status":"OK"}|OK'
  [400]='{"status":"error","problems":["bad_request"]}|Bad Request'
  [404]='{"status":"error","problems":["not_found"]}|Not Found'
)

COMMON_HEADERS=(
  "Content-Type: application/json"
  "Connection: close"
)

read_request_line() {
  read -r request_line || return 1
  return 0
}

skip_headers() {
  local max=32
  while [[ $max -gt 0 ]]; do
    IFS= read -r header || true
    header="${header%%$'\r'}"
    [[ -z "$header" ]] && break
    ((max--)) || true
  done
}

parse_path() {
  local line="$1"
  local method_path="${line#* }"
  local path="${method_path%% *}"
  path="${path%%\?*}"
  echo "$path"
}

run_health_checks() {
  local -a problems=()

  # 1. Binary
  [[ -x "$XRAY_BINARY" ]] || problems+=(xray_binary_missing)

  # 2. Config exists + non-empty
  if [[ ! -f "$XRAY_CONFIG_PATH" || ! -s "$XRAY_CONFIG_PATH" ]]; then
    problems+=(config_missing)
  else
    # 3. Reality
    if ! jq -e '.inbounds[0].streamSettings.security == "reality"' "$XRAY_CONFIG_PATH" >/dev/null 2>&1; then
      problems+=(invalid_config)
    fi
  fi

  # 4. Systemd (always)
  systemctl is-active --quiet xray 2>/dev/null || problems+=(xray_not_running)

  # 5. Process (always)
  pgrep -x xray >/dev/null || problems+=(xray_process_dead)

  # 6. Port listening (only if config exists)
  if [[ -f "$XRAY_CONFIG_PATH" && -s "$XRAY_CONFIG_PATH" ]]; then
    local port
    port=$(jq -r '.inbounds[0].port' "$XRAY_CONFIG_PATH" 2>/dev/null)
    if [[ "$port" =~ ^[1-9][0-9]{0,4}$ && "$port" -le 65535 ]]; then
      timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" >/dev/null 2>&1 || problems+=(port_not_listening)
    fi

    # 7. xray -test
    local xray_ret=0
    timeout "${XRAY_TEST_TIMEOUT}" xray -test -config "$XRAY_CONFIG_PATH" >/dev/null 2>&1 || xray_ret=$?
    if [[ $xray_ret -eq 124 ]]; then
      problems+=(config_test_timeout)
    elif [[ $xray_ret -ne 0 ]]; then
      problems+=(config_test_failed)
    fi
  fi

  printf '%s\n' "${problems[@]}"
}

determine_response() {
  local path="$1"

  if [[ "$path" != "/health" ]]; then
    status=404
    return
  fi

  local problems_str
  problems_str=$(run_health_checks)
  local -a problems=()
  if [[ -n "$problems_str" ]]; then
    mapfile -t problems <<< "$problems_str"
  fi

  local checked_at
  checked_at=$(date -Iseconds 2>/dev/null || echo "unknown")

  if [[ ${#problems[@]} -eq 0 ]]; then
    status=200
    response_body="{\"status\":\"OK\",\"checked_at\":\"$checked_at\"}"
  else
    status=503
    local problems_json
    problems_json=$(printf '"%s",' "${problems[@]}")
    problems_json="[${problems_json%,}]"
    response_body="{\"status\":\"error\",\"problems\":$problems_json,\"checked_at\":\"$checked_at\"}"
  fi
}

build_http_response() {
  local status="$1"
  local body="${2:-}"

  local status_text
  if [[ -n "$body" && "$status" -eq 503 ]]; then
    status_text="Service Unavailable"
  else
    local entry="${RESPONSES[$status]:-{\"status\":\"error\",\"problems\":[\"internal_error\"]}|Internal Server Error}"
    body="${body:-${entry%%|*}}"
    status_text="${entry#*|}"
  fi

  local headers=""
  for h in "${COMMON_HEADERS[@]}"; do
    headers+="$h\r\n"
  done

  printf 'HTTP/1.0 %d %s\r\n%sContent-Length: %d\r\n\r\n%s' \
    "$status" "$status_text" "$headers" "${#body}" "$body"
}

status=400
response_body=""

if read_request_line; then
  skip_headers
  path=$(parse_path "$request_line")
  determine_response "$path"
fi

build_http_response "$status" "$response_body"
exit 0
