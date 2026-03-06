# Uninstall Xray and remove config. Depends on common, log. Uses firewall.sh (is_ufw_active, ufw_disable) when sourced from vless-manager.sh.
# Sourced by bin/vless-manager.sh.


#
# Interactive: prompts "Type DELETE" to confirm, then stops Xray, disables firewall if on, removes unit, binary, config dir; asks about FILES_DIR and ufw purge.
#
# @description
#   Requires root. Prompts for "DELETE"; if not matched, logs cancellation and returns 1. Otherwise runs systemctl stop/disable and reset-failed,
#   disables ufw if active, removes XRAY_SYSTEMD_UNIT, XRAY_BINARY, XRAY_CONFIG_DIR. Asks whether to remove FILES_DIR (keys, backups, client links); default Y.
#   Then asks whether to purge ufw (firewall); default N. Ends with "Uninstall complete." and a note that curl, openssl, jq, uuid-runtime were not removed. Does not touch SSH.
#
uninstall_server() {
  require_root

  if ! confirm_with "Type DELETE to uninstall the server: " "DELETE" "Uninstall cancelled."; then
    return 1
  fi

  log_info "Stopping and disabling Xray service..."
  systemctl stop xray 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true
  systemctl reset-failed xray 2>/dev/null || true

  log_info "Stopping and disabling health endpoint service..."
  systemctl stop vless-health 2>/dev/null || true
  systemctl disable vless-health 2>/dev/null || true
  systemctl reset-failed vless-health 2>/dev/null || true

  if is_ufw_active; then
    ufw_disable
  fi

  if [[ -f "${XRAY_SYSTEMD_UNIT}" ]]; then
    log_info "Removing systemd unit: ${XRAY_SYSTEMD_UNIT}"
    rm -f "${XRAY_SYSTEMD_UNIT}"
  fi
  if [[ -f "${HEALTH_SYSTEMD_UNIT}" ]]; then
    log_info "Removing systemd unit: ${HEALTH_SYSTEMD_UNIT}"
    rm -f "${HEALTH_SYSTEMD_UNIT}"
  fi
  systemctl daemon-reload 2>/dev/null || true

  if [[ -f "${XRAY_BINARY}" ]]; then
    log_info "Removing Xray binary: ${XRAY_BINARY}"
    rm -f "${XRAY_BINARY}"
  fi

  if [[ -d "${XRAY_CONFIG_DIR}" ]]; then
    log_info "Removing config directory: ${XRAY_CONFIG_DIR}"
    rm -rf "${XRAY_CONFIG_DIR}"
  fi

  if [[ -f "${HEALTH_SCRIPT_PATH}" ]]; then
    log_info "Removing health endpoint script: ${HEALTH_SCRIPT_PATH}"
    rm -f "${HEALTH_SCRIPT_PATH}"
  fi
  if [[ -d "$(dirname "${HEALTH_SCRIPT_PATH}")" ]]; then
    rmdir "$(dirname "${HEALTH_SCRIPT_PATH}")" 2>/dev/null || true
  fi

  if command -v apt-get &>/dev/null && dpkg -l socat &>/dev/null; then
    log_info "Removing socat (was used for health endpoint)..."
    apt-get remove -y socat >/dev/null 2>&1 || true
  fi

  if [[ -d "${FILES_DIR}" ]]; then
    local answer_files
    read -r -p "Remove ALL client links, backups, keys (${FILES_DIR})? [Y/n]: " answer_files || true
    answer_files="${answer_files:-Y}"
    answer_files="${answer_files//[[:cntrl:]]/}"
    answer_files="${answer_files//[[:space:]]/}"
    if [[ -z "${answer_files}" || "${answer_files^^}" == "Y" ]]; then
      rm -rf "${FILES_DIR}"
      log_info "Removed client data directory."
    else
      log_info "Preserved: ${FILES_DIR}"
    fi
  fi

  local answer_ufw
  read -r -p "Remove ufw (firewall) if it was installed by this script? [y/N]: " answer_ufw || true
  answer_ufw="${answer_ufw:-N}"
  answer_ufw="${answer_ufw//[[:cntrl:]]/}"
  answer_ufw="${answer_ufw//[[:space:]]/}"
  if [[ "${answer_ufw^^}" == "Y" ]]; then
    if command -v apt-get &>/dev/null; then
      apt-get purge -y ufw >/dev/null 2>&1 || true
      apt-get autoremove -y >/dev/null 2>&1 || true
      apt-get autoclean >/dev/null 2>&1 || true
      log_info "ufw removed (and unused dependencies cleaned)."
    fi
  fi

  log_info "Uninstall complete."
  log_info "Note: socat was removed. curl, openssl, jq, uuid-runtime were not removed (common system tools)."
}
