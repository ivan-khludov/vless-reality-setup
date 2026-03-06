#!/usr/bin/env bash
# health-responder.sh — minimal HTTP health check for VLESS Reality
# socat TCP-LISTEN:... fork SYSTEM:"this_script"

declare -A RESPONSES=(
  [200]='{"status":"OK"}|OK'
  [400]='{"status":"error","problems":["bad_request"]}|Bad Request'
  [404]='{"status":"error","problems":["not_found"]}|Not Found'
  [503]='{"status":"error","problems":["xray not running"]}|Service Unavailable'
)

COMMON_HEADERS=(
  "Content-Type: application/json"
  "Connection: close"
)

read_request_line() {
  read -r request_line || {
    status=400
    return 1
  }
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

determine_response() {
  local path="$1"
  if [[ "$path" != "/health" ]]; then
    status=404
    return
  fi
  if systemctl is-active --quiet xray 2>/dev/null; then
    status=200
  else
    status=503
  fi
}

build_http_response() {
  local status="$1"
  local entry="${RESPONSES[$status]:-{\"status\":\"error\",\"problems\":[\"internal_error\"]}|Internal Server Error}"
  local body="${entry%%|*}"
  local status_text="${entry#*|}"

  local headers=""
  for h in "${COMMON_HEADERS[@]}"; do
    headers+="$h\r\n"
  done

  printf 'HTTP/1.0 %d %s\r\n%sContent-Length: %d\r\n\r\n%s' \
    "$status" "$status_text" "$headers" "${#body}" "$body"
}

status=400

if read_request_line; then
  skip_headers
  path=$(parse_path "$request_line")
  determine_response "$path"
fi

build_http_response "$status"
exit 0
