# Uninstall Xray and remove config. Depends on common, log.
# Sourced by bin/vless-manager.sh.

readonly XRAY_SYSTEMD_UNIT="/etc/systemd/system/xray.service"
readonly XRAY_BINARY="/usr/local/bin/xray"
readonly XRAY_CONFIG_DIR="/usr/local/etc/xray"

#
# Interactive: prompts "Type DELETE" to confirm, then stops Xray, removes unit, binary, and config dir.
#
# @description
#   Requires root. Prompts for "DELETE"; if not matched, logs cancellation and returns 1. Otherwise runs systemctl stop/disable,
#   removes XRAY_SYSTEMD_UNIT, XRAY_BINARY, XRAY_CONFIG_DIR. Does not remove FILES_DIR. Does not touch SSH or firewall.
#
uninstall_server() {
  require_root

  if ! confirm_with "Type DELETE to uninstall the server: " "DELETE" "Uninstall cancelled."; then
    return 1
  fi

  log_info "Stopping and disabling Xray service..."
  systemctl stop xray 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true

  if [[ -f "${XRAY_SYSTEMD_UNIT}" ]]; then
    log_info "Removing systemd unit: ${XRAY_SYSTEMD_UNIT}"
    rm -f "${XRAY_SYSTEMD_UNIT}"
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

  log_info "Uninstall complete. Data under ${FILES_DIR} was left intact (keys and client links)."
}
