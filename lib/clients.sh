# Client management: add, remove, list. Depends on common, log.
# Sourced by bin/vless-manager.sh. Uses backup_config (from common) before add/remove.

#
# Entry point: adds one VLESS Reality client and appends link to CLIENT_LINKS_FILE.
#
# @description
#   Requires root and existing Reality config. Checks SERVER_PUBLIC_KEY_FILE exists. Backs up config, generates uuid and short_id,
#   prompts for client name, merges new client and shortId via jq into temp file, runs test_config, applies config, restarts xray,
#   builds and appends client link. Logs done message.
#
add_client() {
  if [[ ! -f "${SERVER_PUBLIC_KEY_FILE}" ]]; then
    log_error "Public key not found: ${SERVER_PUBLIC_KEY_FILE}. Run install first."
    exit 1
  fi

  backup_config

  local public_key uuid short_id client_name tmp_config sni port
  public_key="$(cat "${SERVER_PUBLIC_KEY_FILE}")"
  uuid="$(uuidgen)"
  short_id="$(openssl rand -hex 4)"

  read -r -p "Client name (default: ${DEFAULT_CLIENT_NAME}): " client_name || true
  client_name="${client_name:-$DEFAULT_CLIENT_NAME}"

  log_info "New UUID: ${uuid}"
  log_info "New Short ID: ${short_id}"

  tmp_config="$(mktemp)"
  jq --arg uuid "${uuid}" --arg sid "${short_id}" --arg email "${client_name}" \
    -f "${SCRIPT_ROOT}/lib/jq/add-client.jq" "${XRAY_CONFIG_PATH}" > "${tmp_config}"
  safe_apply_config "${tmp_config}"
  sni="$(get_current_sni)"
  port="$(get_current_port)"
  append_link "$uuid" "$short_id" "$public_key" "$port" "$sni" "$client_name"
  restart_xray

  log_info "Done. New client added, link appended to ${CLIENT_LINKS_FILE}."
}

#
# Interactive flow: shows clients, prompts for 1-based number, confirms with YES, then removes and rewrites links.
#
# @description
#   Requires root and Reality config. Shows client list, reads client number, validates range, prompts "Type YES to remove client N",
#   then backs up config, removes client and shortId via jq, test_config, apply, restart_xray_then_rewrite_links. On invalid input or
#   cancelled confirmation returns without removing; otherwise logs done.
#
remove_client() {
  show_clients
  echo ""
  read -r -p "Client number to remove (1-based): " n || true
  n="${n//[[:space:]]/}"
  if [[ ! "${n}" =~ ^[0-9]+$ ]] || [[ "${n}" -lt 1 ]]; then
    log_warn "Invalid client number."
    return 1
  fi

  local count
  count="$(get_client_count)"
  if [[ "${n}" -gt "${count}" ]]; then
    log_warn "Client number ${n} is out of range (1..${count})."
    return 1
  fi

  if ! confirm_with "Type YES to remove client ${n}: " "YES" "Removal cancelled."; then
    return 1
  fi

  backup_config

  local i=$(( n - 1 ))
  local tmp_config
  tmp_config="$(mktemp)"
  jq --argjson i "$i" -f "${SCRIPT_ROOT}/lib/jq/remove-client.jq" "${XRAY_CONFIG_PATH}" > "${tmp_config}"
  safe_apply_config "${tmp_config}"

  restart_xray_then_rewrite_links

  log_info "Done. Client ${n} removed. Clients file updated."
}

#
# Prints a numbered list of clients (uuid, shortId, and VLESS link) to stdout.
#
# @description
#   Called via run_protected (root + Reality config). Uses emit_clients_list to stdout.
#
show_clients() {
  emit_clients_list "stdout"
}
