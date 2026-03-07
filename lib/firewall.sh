# Firewall (ufw) helpers: toggle on/off, sync VLESS port. Depends on common, log.
# Sourced by bin/vless-manager.sh. Used by config.sh (update_ufw_vless_port) and menu option 12.

readonly SSH_PORT=22

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
# Enables ufw with SSH and VLESS port allowed. Returns 1 if allow fails.
#
# @param $1 vless_port - VLESS listen port from config
#
ufw_enable_with_rules() {
  local vless_port="$1"
  if ! ufw_allow_ssh_and_vless_port "${vless_port}"; then
    return 1
  fi
  if ! ufw --force enable >/dev/null 2>&1; then
    log_warn "ufw enable failed (non-fatal)."
  fi
  log_info "Firewall enabled. Rules: ${SSH_PORT}/tcp (SSH), ${vless_port}/tcp (VLESS), ${HEALTH_PORT}/tcp (health)."
  echo ""
  ufw status | grep -E "${SSH_PORT}|${vless_port}|${HEALTH_PORT}" || ufw status
}

#
# Disables ufw.
#
ufw_disable() {
  if ! ufw disable >/dev/null 2>&1; then
    log_warn "ufw disable failed (non-fatal)."
  fi
  log_info "Firewall disabled."
}

#
# Toggle firewall: turn off if active, turn on with SSH + current VLESS port if inactive.
# For "turn on" requires Reality config (to read port).
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
  if ! ufw --force delete allow "${old_port}/tcp" >/dev/null 2>&1; then
    log_warn "ufw delete allow ${old_port}/tcp failed (non-fatal)."
  fi
  if ! ufw allow "${new_port}/tcp" >/dev/null 2>&1; then
    log_error "Failed to allow new port ${new_port} in firewall."
    return 1
  fi
  log_info "Firewall updated: ${old_port}/tcp → ${new_port}/tcp"
  echo ""
  ufw status | grep -E "${SSH_PORT}|${new_port}" || ufw status
}
