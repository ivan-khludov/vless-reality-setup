# Xray service control (start/stop/status/logs). Sourced by bin/vless-manager.sh. Depends on log.

#
# Starts the Xray systemd service.
#
# @description
#   Runs systemctl start xray. On failure logs a short message suggesting to check server status (option 9).
#
start_server() {
  if ! systemctl start xray; then
    log_warn "Failed to start Xray. Try option 9 (Server status) to see details."
    return 1
  fi
  log_info "Xray started."
}

#
# Stops the Xray systemd service.
#
# @description
#   Runs systemctl stop xray.
#
stop_server() {
  systemctl stop xray
  log_info "Xray stopped."
}

#
# Shows the Xray systemd service status.
#
# @description
#   Runs systemctl status xray; output goes to terminal.
#
show_server_status() {
  systemctl status xray
}

#
# Shows live Xray logs (follow mode).
#
# @description
#   Prints a short message, then runs journalctl -u xray -f. Blocks until user presses Ctrl+C.
#
show_xray_logs() {
  log_info "Press Ctrl+C to exit logs."
  journalctl -u xray -f || true
}
