# Firewall (ufw) helpers: toggle on/off, sync VLESS port. Depends on common, log.
# Sourced by bin/vless-manager.sh. Used by config.sh (update_ufw_vless_port) and menu option 12.

readonly SSH_PORT=22
readonly EXTRA_UFW_RULES_FILE="${FILES_DIR}/ufw-extra-rules.txt"

#
# Validates extra ufw rule format: "<port>/<proto>" where proto is tcp or udp.
# Also forbids reserved ports: SSH, health, and current VLESS port.
#
# @param $1 rule - string like "80/tcp"
# @param $2 vless_port - current VLESS port (number)
# @returns 0 if valid; 1 otherwise (prints a specific error via log_error)
#
validate_extra_ufw_rule_or_log() {
  local rule_raw="$1"
  local vless_port="$2"
  local rule="${rule_raw//[[:space:]]/}"

  if [[ -z "${rule}" ]]; then
    log_error "Empty rule. Expected format: 80/tcp or 53/udp."
    return 1
  fi

  if [[ ! "${rule}" =~ ^([0-9]{1,5})/(tcp|udp)$ ]]; then
    log_error "Invalid rule format: '${rule_raw}'. Expected: 80/tcp or 53/udp."
    return 1
  fi

  local port proto
  port="${BASH_REMATCH[1]}"
  proto="${BASH_REMATCH[2]}"

  if [[ "${port}" -lt 1 ]] || [[ "${port}" -gt 65535 ]]; then
    log_error "Invalid port in rule '${rule_raw}': ${port} (must be 1-65535)."
    return 1
  fi

  if [[ "${port}" -eq "${SSH_PORT}" ]]; then
    log_error "Refusing to manage extra rule '${rule}': SSH port ${SSH_PORT} is reserved."
    return 1
  fi
  if [[ "${port}" -eq "${HEALTH_PORT}" ]]; then
    log_error "Refusing to manage extra rule '${rule}': health port ${HEALTH_PORT} is reserved."
    return 1
  fi
  if [[ "${port}" -eq "${vless_port}" ]]; then
    log_error "Refusing to manage extra rule '${rule}': VPN port ${vless_port} is reserved."
    return 1
  fi

  # shellcheck disable=SC2034
  local _unused_proto="${proto}"
  return 0
}

#
# Loads extra rules from EXTRA_UFW_RULES_FILE into array on stdout (one per line).
# Skips empty lines and comments.
#
list_extra_ufw_rules() {
  [[ -f "${EXTRA_UFW_RULES_FILE}" ]] || return 0
  # Strip leading/trailing whitespace, drop empty and comments.
  sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//' \
      -e '/^$/d' \
      -e '/^#/d' \
      "${EXTRA_UFW_RULES_FILE}"
}

_write_extra_ufw_rules_file() {
  local rules=("$@")
  mkdir -p "$(dirname "${EXTRA_UFW_RULES_FILE}")"
  : > "${EXTRA_UFW_RULES_FILE}"
  local r
  for r in "${rules[@]}"; do
    [[ -n "${r}" ]] && echo "${r}" >> "${EXTRA_UFW_RULES_FILE}"
  done
}

apply_extra_ufw_rules_if_any() {
  local vless_port="$1"
  local rules=()
  mapfile -t rules < <(list_extra_ufw_rules || true)
  if [[ ${#rules[@]} -eq 0 ]]; then
    return 0
  fi

  local rule
  for rule in "${rules[@]}"; do
    if ! validate_extra_ufw_rule_or_log "${rule}" "${vless_port}"; then
      log_warn "Skipping invalid extra firewall rule from file: ${rule}"
      continue
    fi
    if ! ufw allow "${rule}" >/dev/null 2>&1; then
      log_warn "Failed to apply extra firewall rule '${rule}' (non-fatal)."
    fi
  done
}

extra_ufw_rules_list() {
  local vless_port
  vless_port="$(get_current_port)"
  echo "Extra firewall rules file: ${EXTRA_UFW_RULES_FILE}"
  echo "Format: 80/tcp or 53/udp"
  echo "Reserved (cannot be managed here): ${SSH_PORT}/tcp (SSH), ${vless_port}/tcp (VPN), ${HEALTH_PORT}/tcp (health)"
  echo ""

  local rules=()
  mapfile -t rules < <(list_extra_ufw_rules || true)
  if [[ ${#rules[@]} -eq 0 ]]; then
    echo "(no extra rules)"
    return 0
  fi

  local i
  for i in "${!rules[@]}"; do
    echo "  $(( i + 1 ))) ${rules[i]}"
  done
}

extra_ufw_rules_add() {
  local vless_port
  vless_port="$(get_current_port)"

  echo "Add extra firewall rule."
  echo "Expected format: 80/tcp or 53/udp"
  echo ""

  local input
  read -r -p "Rule to add: " input || true
  input="${input//[[:space:]]/}"
  if ! validate_extra_ufw_rule_or_log "${input}" "${vless_port}"; then
    return 1
  fi

  local existing=()
  mapfile -t existing < <(list_extra_ufw_rules || true)
  local r
  for r in "${existing[@]}"; do
    if [[ "${r}" == "${input}" ]]; then
      log_warn "Rule already exists: ${input}"
      return 0
    fi
  done

  if is_ufw_active; then
    if ! ufw allow "${input}" >/dev/null 2>&1; then
      log_error "Failed to apply firewall rule via ufw: ${input}"
      return 1
    fi
    log_info "Applied firewall rule: ${input}"
  fi

  existing+=( "${input}" )
  _write_extra_ufw_rules_file "${existing[@]}"
  log_info "Saved extra firewall rule: ${input}"
}

extra_ufw_rules_remove() {
  local vless_port
  vless_port="$(get_current_port)"

  local rules=()
  mapfile -t rules < <(list_extra_ufw_rules || true)
  if [[ ${#rules[@]} -eq 0 ]]; then
    log_warn "No extra rules to remove."
    return 1
  fi

  echo "Extra firewall rules:"
  local i
  for i in "${!rules[@]}"; do
    echo "  $(( i + 1 ))) ${rules[i]}"
  done
  echo ""

  local n
  read -r -p "Rule number to remove (1-${#rules[@]}): " n || true
  n="${n//[[:space:]]/}"
  if [[ ! "${n}" =~ ^[0-9]+$ ]] || [[ "${n}" -lt 1 ]] || [[ "${n}" -gt "${#rules[@]}" ]]; then
    log_warn "Invalid rule number."
    return 1
  fi

  local rule_to_remove="${rules[n-1]}"
  if ! validate_extra_ufw_rule_or_log "${rule_to_remove}" "${vless_port}"; then
    log_warn "Rule entry is invalid, removing from file only: ${rule_to_remove}"
  fi

  if is_ufw_active; then
    if ! ufw --force delete allow "${rule_to_remove}" >/dev/null 2>&1; then
      log_warn "ufw delete allow ${rule_to_remove} failed (non-fatal)."
    else
      log_info "Removed firewall rule from ufw: ${rule_to_remove}"
    fi
  fi

  local new_rules=()
  for i in "${!rules[@]}"; do
    if [[ "${i}" -ne "$(( n - 1 ))" ]]; then
      new_rules+=( "${rules[i]}" )
    fi
  done
  _write_extra_ufw_rules_file "${new_rules[@]}"
  log_info "Removed extra firewall rule: ${rule_to_remove}"
}

manage_extra_firewall_rules() {
  require_reality_config
  while true; do
    echo "==============================="
    echo "  Extra Firewall rules (ufw)"
    echo "==============================="
    echo ""
    echo "1) List"
    echo "2) Add"
    echo "3) Remove"
    echo "0) Back"
    echo ""

    local option
    read -r -p "Select option: " option || true
    option="${option//[[:space:]]/}"
    case "${option}" in
      1) extra_ufw_rules_list || true ;;
      2) extra_ufw_rules_add || true ;;
      3) extra_ufw_rules_remove || true ;;
      0) return 0 ;;
      *) log_warn "Invalid option. Enter 0-3." ;;
    esac

    # For 0) Back we return immediately above. For other options, pause so the user can read output.
    echo ""
    if [[ -t 0 ]]; then
      read -r -p "Press Enter to continue..." _ || true
    fi
  done
}

#
# Returns 0 if ufw is installed and active; 1 otherwise.
#
# @description
#   Checks command ufw exists and ufw status contains "Status: active".
#
is_ufw_active() {
  command -v ufw &>/dev/null || return 1
  ufw status 2>/dev/null | grep -q 'Status: active'
}

#
# Adds ufw allow rules for SSH, VLESS port, and health port (idempotent). Returns 1 if any allow fails.
#
# @param $1 port - VLESS listen port (number)
#
ufw_allow_ssh_and_vless_port() {
  local port="$1"
  if ! ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1; then
    log_error "Failed to add allow rule for port ${SSH_PORT}"
    return 1
  fi
  if ! ufw allow "${port}/tcp" >/dev/null 2>&1; then
    log_error "Failed to add allow rule for port ${port}"
    return 1
  fi
  if ! ufw allow "${HEALTH_PORT}/tcp" >/dev/null 2>&1; then
    log_error "Failed to add allow rule for health port ${HEALTH_PORT}"
    return 1
  fi
}

#
# Enables ufw with SSH, VLESS port, and health port allowed. Returns 1 if allow fails.
#
# @param $1 vless_port - VLESS listen port from config
#
ufw_enable_with_rules() {
  local vless_port="$1"
  if ! ufw_allow_ssh_and_vless_port "${vless_port}"; then
    return 1
  fi
  apply_extra_ufw_rules_if_any "${vless_port}"
  if ! ufw --force enable >/dev/null 2>&1; then
    log_warn "ufw enable failed (non-fatal)."
  fi
  log_info "Firewall enabled. Rules: ${SSH_PORT}/tcp (SSH), ${vless_port}/tcp (VLESS), ${HEALTH_PORT}/tcp (health) + extra rules (if any)."
  echo ""
  _ufw_print_status_with_extra_rules "${vless_port}"
}

#
# Disables ufw (non-fatal on ufw errors).
#
ufw_disable() {
  if ! ufw disable >/dev/null 2>&1; then
    log_warn "ufw disable failed (non-fatal)."
  fi
  log_info "Firewall disabled."
}

#
# Prints ufw status filtered by the given grep pattern for ports; falls back to full status if no matches.
#
# @param $1 pattern - grep -E pattern for ufw status (ports or other fields)
#
_ufw_print_status_for_ports() {
  local pattern="$1"
  ufw status | grep -E "${pattern}" || ufw status
}

_ufw_print_status_with_extra_rules() {
  local vless_port="$1"
  local pattern_ports=("${SSH_PORT}" "${vless_port}" "${HEALTH_PORT}")

  local rules=()
  mapfile -t rules < <(list_extra_ufw_rules || true)
  local rule port
  for rule in "${rules[@]}"; do
    rule="${rule//[[:space:]]/}"
    if [[ "${rule}" =~ ^([0-9]{1,5})/(tcp|udp)$ ]]; then
      port="${BASH_REMATCH[1]}"
      if [[ "${port}" -ne "${SSH_PORT}" ]] && [[ "${port}" -ne "${HEALTH_PORT}" ]] && [[ "${port}" -ne "${vless_port}" ]]; then
        pattern_ports+=( "${port}" )
      fi
    fi
  done

  local IFS='|'
  _ufw_print_status_for_ports "${pattern_ports[*]}"
}

#
# Toggle firewall: turn off if active, turn on with SSH + current VLESS port and health port if inactive.
# For \"turn on\" requires Reality config (to read port).
#
toggle_firewall() {
  if is_ufw_active; then
    ufw_disable
    return 0
  fi
  require_reality_config
  local sni_port
  sni_port="$(get_current_port)"
  if [[ ! "${sni_port}" =~ ^[0-9]+$ ]] || [[ "${sni_port}" -lt 1 ]] || [[ "${sni_port}" -gt 65535 ]]; then
    log_error "Invalid VLESS port from config: ${sni_port}"
    return 1
  fi
  ufw_enable_with_rules "${sni_port}"
}

#
# Internal: updates ufw rule for VLESS port when ufw is active.
#
# @param $1 old_port - previous VLESS port
# @param $2 new_port - new VLESS port
#
_ufw_update_vless_port_rule() {
  local old_port="$1"
  local new_port="$2"

  if ! ufw --force delete allow "${old_port}/tcp" >/dev/null 2>&1; then
    log_warn "ufw delete allow ${old_port}/tcp failed (non-fatal)."
  fi
  if ! ufw allow "${new_port}/tcp" >/dev/null 2>&1; then
    log_error "Failed to allow new port ${new_port} in firewall."
    return 1
  fi
  log_info "Firewall updated: ${old_port}/tcp → ${new_port}/tcp"
  echo ""
  _ufw_print_status_with_extra_rules "${new_port}"
}

#
# Updates ufw: remove rule for old VLESS port, add rule for new port. No-op if ufw not active.
#
# @param $1 old_port - previous VLESS port
# @param $2 new_port - new VLESS port
#
update_ufw_vless_port() {
  local old_port="$1"
  local new_port="$2"

  if ! is_ufw_active; then
    return 0
  fi

  _ufw_update_vless_port_rule "${old_port}" "${new_port}"
}
