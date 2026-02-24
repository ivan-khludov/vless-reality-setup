# Shared constants and functions for VLESS Reality manager.
# Sourced first by bin/vless-manager.sh. Caller must set -euo pipefail.

IFS=$'\n\t'

# ===== Constants =====
readonly XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json"
readonly DEFAULT_PORT=443
readonly DEFAULT_SNI="www.cloudflare.com"
readonly DEFAULT_CLIENT_NAME="auto-vless-reality"

# Script root: parent of lib/ (this file lives in lib/)
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_root="$(dirname "${_lib_dir}")"
readonly FILES_DIR="${_root}/files"
readonly BACKUPS_DIR="${FILES_DIR}/backups"
readonly CLIENT_LINKS_FILE="${FILES_DIR}/vless-reality-clients.txt"
readonly SERVER_PUBLIC_KEY_FILE="${FILES_DIR}/.vless-reality-public-key"
readonly SERVER_IP_FILE="${FILES_DIR}/server-ip"

# ===== Helpers =====


#
# Prints text in green when stdout is a TTY; plain text otherwise.
#
# @description
#   Use for highlighting VLESS links in interactive output without polluting files or pipes
#   with ANSI escape codes.
#
# @param $* text - text to print
#
print_green() {
  local text="$*"
  local GREEN=$'\e[32m'
  local RESET=$'\e[0m'

  # If stdout is not a terminal (e.g. piped to a file), avoid color codes.
  if [[ ! -t 1 ]]; then
    printf '%s\n' "$text"
    return
  fi

  printf '%s%s%s\n' "$GREEN" "$text" "$RESET"
}

#
# Returns 0 if XRAY_CONFIG_PATH exists, 1 otherwise.
#
# @description
#   Use before operations that need the config file. Does not log or exit.
#
config_exists() {
  [[ -f "${XRAY_CONFIG_PATH}" ]]
}

#
# Exits with status 1 if config file does not exist.
#
# @description
#   If config_exists is false, logs error and exits 1. Use in lib entry points that require config.
#
require_config_or_exit() {
  config_exists || {
    log_error "Config not found: ${XRAY_CONFIG_PATH}. Run install first."
    exit 1
  }
}

#
# Exits with status 1 if not running as root.
#
# @description
#   Ensures the script is run with root privileges (e.g. sudo). Prints message to stderr and exits 1 otherwise.
#
require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    log_error "This command must be run as root (or with sudo)."
    exit 1
  fi
}

#
# Sets config file permissions so the xray process user can read it.
#
# @description
#   chmod 644 on XRAY_CONFIG_PATH. Call after writing the config file.
#
make_config_readable() {
  chmod 644 "${XRAY_CONFIG_PATH}"
}

#
# Replaces live config with a temp file and sets permissions.
#
# @description
#   Moves the given temp config path to XRAY_CONFIG_PATH and calls make_config_readable.
#
# @param $1 path to temporary config file (will be moved)
#
apply_config_from_temp() {
  mv "$1" "${XRAY_CONFIG_PATH}"
  make_config_readable
}

#
# Tests config with xray -test then moves temp file to XRAY_CONFIG_PATH; exits on test failure.
#
# @description
#   Calls test_config then apply_config_from_temp. Use after writing a temp config file with jq.
#
# @param $1 path to temporary config file (will be tested then moved)
#
safe_apply_config() {
  test_config "$1"
  apply_config_from_temp "$1"
}

#
# Prompts user to type expected word; returns 1 and logs cancel_message if input does not match.
#
# @description
#   Reads one line, trims whitespace. Returns 0 if input equals expected_word (case-sensitive); otherwise log_warn with cancel_message and returns 1.
#
# @param $1 prompt - string shown before read (e.g. "Type YES to remove client 2: ")
# @param $2 expected_word - exact string user must type (e.g. YES or DELETE)
# @param $3 cancel_message - message logged when input does not match (e.g. "Removal cancelled.")
# @returns 0 if input matches, 1 otherwise
#
confirm_with() {
  local prompt="$1"
  local expected_word="$2"
  local cancel_message="$3"
  local input
  read -r -p "${prompt}" input || true
  input="${input//[[:space:]]/}"
  if [[ "${input}" != "${expected_word}" ]]; then
    log_warn "${cancel_message}"
    return 1
  fi
  return 0
}

#
# Creates a timestamped backup of the current Xray config.
#
# @description
#   Copies XRAY_CONFIG_PATH to BACKUPS_DIR with name config.json.bak.<unix_timestamp>.
#   Logs the backup path via log_info. Call before any config change (add/remove client, update port/sni).
#
backup_config() {
  mkdir -p "${BACKUPS_DIR}"
  local backup_path="${BACKUPS_DIR}/config.json.bak.$(date +%s)"
  cp "${XRAY_CONFIG_PATH}" "${backup_path}"
  log_info "Config backed up to ${backup_path}"
}

#
# Interactive: lists backups, prompts for number and RESTORE, then restores selected backup to XRAY_CONFIG_PATH.
#
# @description
#   Requires root. Does not require config to exist (restore is for recovering missing/corrupted config).
#   Lists config.json.bak.* in BACKUPS_DIR (newest first by timestamp in filename), prompts for 1-based index,
#   confirms with "Type RESTORE", runs test_config on selected file, copies to XRAY_CONFIG_PATH, make_config_readable,
#   restart_xray_then_rewrite_links. On empty list or cancelled confirmation returns 1.
#
restore_from_backup() {
  require_root

  local backup_files sorted count i path base ts date_str n selected
  shopt -s nullglob
  backup_files=( "${BACKUPS_DIR}"/config.json.bak.* )
  shopt -u nullglob

  if [[ ${#backup_files[@]} -eq 0 ]]; then
    log_warn "No backups found in ${BACKUPS_DIR}."
    return 1
  fi

  # Sort by timestamp (suffix after last dot in basename), newest first. Avoids sort -t. -k4 which breaks when path contains dots.
  mapfile -t sorted < <(
    for p in "${backup_files[@]}"; do
      base="$(basename "${p}")"
      ts="${base##*.}"
      printf '%s\t%s\n' "${ts}" "${p}"
    done | sort -t$'\t' -k1 -nr | cut -f2-
  )
  count=${#sorted[@]}

  echo "Backups (newest first):"
  for i in "${!sorted[@]}"; do
    path="${sorted[i]}"
    base="$(basename "${path}")"
    ts="${base##*.}"
    date_str="$(date -d "@${ts}" 2>/dev/null || echo "${ts}")"
    echo "  $(( i + 1 ))) ${base}  (${date_str})"
  done
  echo ""

  read -r -p "Backup number to restore (1-${count}): " n || true
  n="${n//[[:space:]]/}"
  if [[ ! "${n}" =~ ^[0-9]+$ ]] || [[ "${n}" -lt 1 ]] || [[ "${n}" -gt "${count}" ]]; then
    log_warn "Invalid backup number."
    return 1
  fi

  selected="${sorted[n-1]}"
  if ! confirm_with "Type RESTORE to restore config from backup ${n}: " "RESTORE" "Restore cancelled."; then
    return 1
  fi

  log_info "Testing config..."
  test_config "${selected}"
  cp "${selected}" "${XRAY_CONFIG_PATH}"
  make_config_readable
  restart_xray_then_rewrite_links
  log_info "Done. Config restored from backup."
}

#
# Runs xray -test against a config file; exits 1 if test fails.
#
# @description
#   If config_path is not in the same directory as XRAY_CONFIG_PATH, copies it there temporarily so xray
#   resolves paths correctly, then runs xray -test. On failure, prints xray's stderr and exits 1.
#
# @param $1 config_path - path to config.json (or temp file) to test
#
# Timeout for xray -test (seconds); avoids hanging if xray -test stalls
readonly XRAY_TEST_TIMEOUT=15

test_config() {
  local config_path="$1"
  local config_dir
  config_dir="$(dirname "${XRAY_CONFIG_PATH}")"
  local path_to_test="${config_path}"

  if [[ "$(dirname "${config_path}")" != "${config_dir}" ]]; then
    path_to_test="${config_dir}/config.test.$$.json"
    cp "${config_path}" "${path_to_test}"
  fi

  local xray_out xray_ret=0
  xray_out="$(timeout "${XRAY_TEST_TIMEOUT}" xray -test -config "${path_to_test}" 2>&1)" || xray_ret=$?
  [[ "${path_to_test}" != "${config_path}" ]] && rm -f "${path_to_test}"

  if [[ "${xray_ret}" -ne 0 ]]; then
    if [[ "${xray_ret}" -eq 124 ]]; then
      log_error "Config test timed out (xray -test did not finish in ${XRAY_TEST_TIMEOUT}s). Check config or try again."
    else
      log_error "Config test failed: xray -test -config ${path_to_test}. Fix config and try again."
    fi
    [[ -n "${xray_out}" ]] && echo "${xray_out}" >&2
    exit 1
  fi
}

#
# Parses port from user input; echoes valid port or default.
#
# @description
#   If input is empty, echoes default. If input is a number in 1..65535, echoes it. Otherwise echoes default and logs to stderr.
#
# @param $1 default port value
# @param $2 user input (trimmed internally)
# @returns port number on stdout
#
parse_port() {
  local default="$1"
  local input="${2//[[:space:]]/}"
  if [[ -z "${input}" ]]; then
    echo "${default}"
    return
  fi
  local validated
  if validated="$(validate_port "${input}" 2>/dev/null)" && [[ -n "${validated}" ]]; then
    echo "${validated}"
    return
  fi
  log_warn "Invalid port, using ${default}."
  echo "${default}"
}

#
# Exits with error if config does not exist or is not VLESS Reality.
#
# @description
#   Checks XRAY_CONFIG_PATH exists and that inbounds[0].streamSettings.security is "reality". Exits 1 otherwise.
#
require_reality_config() {
  require_config_or_exit
  jq -e '.inbounds[0].streamSettings.security == "reality"' "${XRAY_CONFIG_PATH}" >/dev/null 2>&1 || {
    log_error "Config is not VLESS Reality. Run install first."
    exit 1
  }
}

#
# Returns server external IP on stdout; caches in SERVER_IP_FILE.
#
# @description
#   If SERVER_IP_FILE exists and is non-empty, echoes its content. Otherwise detects IP via curl or prompts user,
#   writes to SERVER_IP_FILE, and echoes. Messages go to stderr.
#
# @returns IP address on stdout
#
get_server_ip() {
  local ip
  if [[ -f "${SERVER_IP_FILE}" ]] && [[ -s "${SERVER_IP_FILE}" ]]; then
    ip="$(cat "${SERVER_IP_FILE}")"
    ip="${ip//[[:space:]]/}"
    echo "${ip}"
    return
  fi
  log_info "Detecting server external IP..."
  ip="$(curl -4 -s --max-time 5 https://ipv4.icanhazip.com || curl -4 -s --max-time 5 https://ifconfig.me || true)"
  ip="${ip//[[:space:]]/}"
  if [[ -z "${ip}" ]]; then
    log_info "Could not detect external IP automatically. Enter it manually:"
    read -r ip || true
    if [[ -z "${ip//[[:space:]]/}" ]]; then
      log_error "External IP is required. Run the script again and enter the server IP when prompted."
      exit 1
    fi
    ip="${ip//[[:space:]]/}"
  fi
  mkdir -p "$(dirname "${SERVER_IP_FILE}")"
  echo "${ip}" > "${SERVER_IP_FILE}"
  echo "${ip}"
}

#
# Outputs current SNI and port from config as "sni|port".
#
# @description
#   Reads inbounds[0].streamSettings.realitySettings.serverNames[0] and inbounds[0].port via jq. Exits 1 if config missing.
#
# @returns "sni|port" on stdout
#
get_sni_and_port() {
  require_config_or_exit
  local sni port
  sni="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "${XRAY_CONFIG_PATH}")"
  port="$(jq -r '.inbounds[0].port' "${XRAY_CONFIG_PATH}")"
  echo "${sni}|${port}"
}

#
# Builds a single VLESS Reality link line for one client.
#
# @description
#   Constructs vless://... URL with encryption=none, flow=xtls-rprx-vision, security=reality, and query params.
#
# @param $1 uuid - client UUID
# @param $2 short_id - short id
# @param $3 public_key - server public key
# @param $4 ip - server IP
# @param $5 port - optional; defaults to DEFAULT_PORT
# @param $6 sni - optional; defaults to DEFAULT_SNI
# @param $7 client_name - optional; defaults to DEFAULT_CLIENT_NAME
# @returns single line vless://... on stdout
#
format_link() {
  local uuid="$1"
  local short_id="$2"
  local public_key="$3"
  local ip="$4"
  local port="${5:-$DEFAULT_PORT}"
  local sni="${6:-$DEFAULT_SNI}"
  local client_name="${7:-$DEFAULT_CLIENT_NAME}"
  local params
  params="encryption=none"
  params+="&flow=xtls-rprx-vision"
  params+="&security=reality"
  params+="&sni=${sni}"
  params+="&fp=chrome"
  params+="&pbk=${public_key}"
  params+="&sid=${short_id}"
  params+="&type=tcp"
  echo "vless://${uuid}@${ip}:${port}?${params}#${client_name}"
}

#
# Outputs number of clients in config on stdout.
#
# @description
#   Reads .inbounds[0].settings.clients | length from XRAY_CONFIG_PATH. Call only when config exists and is Reality.
#
# @returns client count on stdout
#
get_client_count() {
  jq -r '.inbounds[0].settings.clients | length' "${XRAY_CONFIG_PATH}"
}

#
# Outputs client at 0-based index as "uuid|short_id|client_name" on stdout.
#
# @description
#   Reads uuid, shortId, and email (defaulting to DEFAULT_CLIENT_NAME if empty) for client at index $1.
#
# @param $1 0-based client index
# @returns "uuid|short_id|client_name" on stdout
#
get_client_at_index() {
  local i="$1"
  local uuid sid client_name
  uuid="$(jq -r --argjson i "$i" '.inbounds[0].settings.clients[$i].id' "${XRAY_CONFIG_PATH}")"
  sid="$(jq -r --argjson i "$i" '.inbounds[0].streamSettings.realitySettings.shortIds[$i]' "${XRAY_CONFIG_PATH}")"
  client_name="$(jq -r --argjson i "$i" '.inbounds[0].settings.clients[$i].email // empty' "${XRAY_CONFIG_PATH}")"
  client_name="${client_name:-$DEFAULT_CLIENT_NAME}"
  echo "${uuid}|${sid}|${client_name}"
}

#
# Overwrites CLIENT_LINKS_FILE with links for all clients from current config.
#
# @description
#   Reads clients and shortIds from XRAY_CONFIG_PATH, verifies counts match, then writes a new CLIENT_LINKS_FILE
#   with one vless link per client. Exits 1 on count mismatch.
#
rewrite_links_file() {
  local clients_count shortids_count count public_key server_ip sni port
  clients_count="$(get_client_count)"
  shortids_count="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds | length' "${XRAY_CONFIG_PATH}")"
  if [[ "${clients_count}" != "${shortids_count}" ]]; then
    log_error "Config corruption detected: clients (${clients_count}) and shortIds (${shortids_count}) count mismatch. Fix config.json manually."
    exit 1
  fi
  count="${clients_count}"
  IFS="|" read -r sni port < <(get_sni_and_port)
  public_key="$(cat "${SERVER_PUBLIC_KEY_FILE}")"
  server_ip="$(get_server_ip)"

  mkdir -p "$(dirname "${CLIENT_LINKS_FILE}")"
  {
    echo "==== $(date -Iseconds) (${count} clients) ===="
    local i uuid sid client_name
    for (( i = 0; i < count; i++ )); do
      IFS="|" read -r uuid sid client_name < <(get_client_at_index "$i")
      format_link "$uuid" "$sid" "$public_key" "$server_ip" "$port" "$sni" "$client_name"
    done
  } > "${CLIENT_LINKS_FILE}"

  log_info "Clients file updated: ${CLIENT_LINKS_FILE} (${count} clients)."
}

#
# Restarts xray service and verifies it is active.
#
# @description
#   Runs systemctl daemon-reload, enable, restart; sleeps 1s; exits 1 if xray is not active.
#
restart_xray() {
  log_info "Restarting and enabling Xray service..."
  systemctl daemon-reload || true
  systemctl enable xray >/dev/null 2>&1 || true
  systemctl restart xray

  sleep 1
  if ! systemctl is-active --quiet xray; then
    log_error "Xray service failed to start. Check logs: journalctl -u xray -e"
    exit 1
  fi
}

#
# Restarts xray then rewrites CLIENT_LINKS_FILE to match config.
#
# @description
#   Calls restart_xray then rewrite_links_file. Use after port or SNI change.
#
restart_xray_then_rewrite_links() {
  restart_xray
  rewrite_links_file
}

#
# Appends one client link to CLIENT_LINKS_FILE and prints it.
#
# @description
#   Resolves server IP, builds vless link with format_link, appends to CLIENT_LINKS_FILE with timestamp,
#   then prints the link to stdout. Messages to stderr.
#
# @param $1 uuid - client UUID
# @param $2 short_id - short id
# @param $3 public_key - server public key
# @param $4 port - listen port
# @param $5 sni - server name
# @param $6 client_name - optional; defaults to DEFAULT_CLIENT_NAME
#
append_link() {
  local uuid="$1"
  local short_id="$2"
  local public_key="$3"
  local port="$4"
  local sni="$5"
  local client_name="${6:-$DEFAULT_CLIENT_NAME}"
  local server_ip link

  log_info "Building VLESS Reality client link..."
  server_ip="$(get_server_ip)"
  link="$(format_link "$uuid" "$short_id" "$public_key" "$server_ip" "$port" "$sni" "$client_name")"
  mkdir -p "$(dirname "${CLIENT_LINKS_FILE}")"
  {
    echo "==== $(date -Iseconds) ===="
    echo "${link}"
    echo
  } >> "${CLIENT_LINKS_FILE}"
  log_info "Client link saved to file: ${CLIENT_LINKS_FILE}"
  echo "Link:"
  print_green "${link}"
}
