# Config changes: port and SNI. Depends on common, log, validation.
# Sourced by bin/vless-manager.sh. Uses backup_config and test_config (from common) before apply.

#
# Entry point: changes listen port, restarts xray, and rewrites client links file.
#
# @description
#   Requires root and Reality config. Backs up config, loads current port, prompts for new port (default current),
#   validates with parse_port, writes new config to temp via jq, test_config, apply_config_from_temp,
#   restart_xray_then_rewrite_links. Logs done message.
#
change_port() {
  run_protected true

  backup_config

  local current_port input_port new_port tmp_config
  current_port="$(get_current_port)"

  read -r -p "Listen port for VLESS (current: ${current_port}): " input_port || true
  new_port="$(parse_port "${current_port}" "${input_port}")"

  if [[ "${new_port}" == "${current_port}" ]]; then
    log_info "Port not changed."
    return 0
  fi

  tmp_config="$(mktemp)"
  jq --argjson port "${new_port}" '.inbounds[0].port = $port' "${XRAY_CONFIG_PATH}" > "${tmp_config}"
  safe_apply_config "${tmp_config}"

  if is_ufw_active; then
    update_ufw_vless_port "${current_port}" "${new_port}"
  fi

  restart_xray_then_rewrite_links

  log_info "Port changed: ${current_port} → ${new_port}"
}

#
# Entry point: changes SNI and dest, restarts xray, and rewrites client links file.
#
# @description
#   Requires root and Reality config. Backs up config, loads current SNI and dest (keeps dest port), prompts for new SNI (default current),
#   validates with validate_sni (or uses current if invalid), writes serverNames[0] and dest via jq to temp, test_config, apply,
#   restart_xray_then_rewrite_links. Logs done message.
#
change_sni() {
  run_protected true

  backup_config

  local current_sni current_dest dest_port new_sni new_dest tmp_config
  current_sni="$(get_current_sni)"
  current_dest="$(jq -r '.inbounds[0].streamSettings.realitySettings.dest' "${XRAY_CONFIG_PATH}")"
  if [[ "${current_dest}" == *:* ]]; then
    dest_port="${current_dest##*:}"
  else
    dest_port="443"
  fi

  read -r -p "SNI (current: ${current_sni}): " new_sni || true
  new_sni="${new_sni:-$current_sni}"
  new_sni="${new_sni//[[:space:]]/}"
  if [[ -z "${new_sni}" ]]; then
    new_sni="${current_sni}"
  else
    if ! validate_sni "${new_sni}"; then
      log_warn "Invalid SNI format, using current: ${current_sni}"
      new_sni="${current_sni}"
    fi
  fi

  new_dest="${new_sni}:${dest_port}"

  if [[ "${new_sni}" == "${current_sni}" ]]; then
    log_info "SNI not changed."
    return 0
  fi

  tmp_config="$(mktemp)"
  jq --arg sni "${new_sni}" --arg dest "${new_dest}" \
    -f "${SCRIPT_ROOT}/lib/jq/change-sni.jq" "${XRAY_CONFIG_PATH}" > "${tmp_config}"
  safe_apply_config "${tmp_config}"

  restart_xray_then_rewrite_links

  log_info "SNI changed to ${new_sni}, Xray restarted, clients file updated."
}
