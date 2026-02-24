# Install Xray and create initial VLESS Reality config. Depends on common, log.
# Sourced by bin/vless-manager.sh. No backup on first install (no existing config).

readonly XRAY_INSTALL_SCRIPT_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

#
# Detects Ubuntu and logs a warning if not Ubuntu.
#
# @description
#   Sources /etc/os-release and checks ID. Logs warning to stderr if not Ubuntu (script tested on Ubuntu 24.04).
#
detect_ubuntu() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      log_warn "Not Ubuntu detected. Script was tested on Ubuntu 24.04."
    fi
  else
    log_warn "Could not detect OS (no /etc/os-release)."
  fi
}

#
# Installs apt dependencies: curl, openssl, uuid-runtime, jq.
#
# @description
#   Runs apt-get update and apt-get install. Requires root.
#
install_dependencies() {
  log_info "Installing dependencies (curl, openssl, uuid-runtime, jq)..."
  apt-get update -qq -y
  apt-get install -qq -y curl openssl uuid-runtime jq
}

#
# Installs Xray via official XTLS install script if not already present.
#
# @description
#   Skips if xray binary exists at /usr/local/bin/xray. Otherwise downloads and runs install-release.sh.
#
install_xray() {
  if command -v xray >/dev/null 2>&1 && [[ -x /usr/local/bin/xray ]]; then
    log_info "Xray is already installed, skipping installation."
    return
  fi

  log_info "Installing Xray via official script..."
  local script_path
  script_path="$(mktemp)"
  curl -LsS "${XRAY_INSTALL_SCRIPT_URL}" -o "${script_path}"
  bash "${script_path}" install -u root
  rm -f "${script_path}"
}

#
# Generates UUID, X25519 keys, and short id for VLESS Reality.
#
# @description
#   Runs uuidgen, xray x25519, and openssl rand. Outputs uuid|private_key|public_key|short_id on stdout; messages to stderr. Exits 1 if key generation fails.
#
# @returns "uuid|private_key|public_key|short_id" on stdout
#
generate_keys() {
  log_info "Generating UUID, X25519 keys and short id..."
  local uuid private public short key_output
  uuid="$(uuidgen)"
  key_output="$(cd /tmp && /usr/local/bin/xray x25519 2>&1)" || true
  private="$(echo "${key_output}" | grep -i 'PrivateKey' | sed -n 's/.*:[[:space:]]*//p' | tr -d '\r')" || true
  public="$(echo "${key_output}" | grep -i 'Password' | sed -n 's/.*:[[:space:]]*//p' | tr -d '\r')" || true
  if [[ -z "${private}" || -z "${public}" ]]; then
    log_error "Failed to generate X25519 keys. xray x25519 output:"
    echo "${key_output}" >&2
    exit 1
  fi
  short="$(openssl rand -hex 4)"
  log_info "UUID: ${uuid}"
  log_info "Public key: ${public}"
  log_info "Short ID: ${short}"
  echo "${uuid}|${private}|${public}|${short}"
}

#
# Creates initial Xray VLESS Reality config and writes public key file.
#
# @description
#   Writes config to XRAY_CONFIG_PATH with one client and one shortId; saves public key to SERVER_PUBLIC_KEY_FILE. Uses jq -n to build JSON.
#
# @param $1 uuid - client UUID
# @param $2 private_key - server private key (Reality)
# @param $3 port - listen port (number)
# @param $4 dest - Reality dest (e.g. sni:443)
# @param $5 sni - server name
# @param $6 short_id - short id
# @param $7 public_key - server public key (saved to SERVER_PUBLIC_KEY_FILE)
# @param $8 client_name - first client name
#
write_config() {
  local uuid="$1"
  local private="$2"
  local port="$3"
  local dest="$4"
  local sni="$5"
  local short_id="$6"
  local public_key="$7"
  local client_name="$8"

  log_info "Creating Xray config (VLESS+Reality) at ${XRAY_CONFIG_PATH}..."
  mkdir -p "$(dirname "${XRAY_CONFIG_PATH}")" || { log_error "Cannot create config directory."; exit 1; }

  local tmp_config jq_stderr
  tmp_config="$(mktemp)" || { log_error "mktemp failed."; exit 1; }
  jq_stderr="$(mktemp)" || { log_error "mktemp (jq stderr) failed."; rm -f "${tmp_config}"; exit 1; }
  if ! jq -n \
    --arg uuid "${uuid}" \
    --arg private "${private}" \
    --argjson port "${port}" \
    --arg dest "${dest}" \
    --arg sni "${sni}" \
    --arg short_id "${short_id}" \
    --arg client_name "${client_name}" \
    '{
      log: { loglevel: "warning" },
      inbounds: [{
        port: $port,
        protocol: "vless",
        settings: {
          clients: [{ id: $uuid, flow: "xtls-rprx-vision", email: $client_name }],
          decryption: "none"
        },
        streamSettings: {
          network: "tcp",
          security: "reality",
          realitySettings: {
            show: false,
            dest: $dest,
            xver: 0,
            serverNames: [$sni],
            privateKey: $private,
            shortIds: [$short_id]
          }
        }
      }],
      outbounds: [
        { protocol: "freedom", tag: "direct" },
        { protocol: "blackhole", tag: "blocked" }
      ]
    }' > "${tmp_config}" 2> "${jq_stderr}"; then
    log_error "Failed to generate config (jq failed)."
    [[ -s "${jq_stderr}" ]] && { echo "jq stderr:" >&2; cat "${jq_stderr}" >&2; }
    rm -f "${tmp_config}" "${jq_stderr}"
    exit 1
  fi
  rm -f "${jq_stderr}"
  mv "${tmp_config}" "${XRAY_CONFIG_PATH}" || { log_error "Cannot move config to ${XRAY_CONFIG_PATH} (file in use or read-only?)."; exit 1; }
  make_config_readable

  mkdir -p "$(dirname "${SERVER_PUBLIC_KEY_FILE}")" || { log_error "Cannot create files directory."; exit 1; }
  echo "${public_key}" > "${SERVER_PUBLIC_KEY_FILE}" || { log_error "Cannot write public key file."; exit 1; }
  chmod 600 "${SERVER_PUBLIC_KEY_FILE}" || { log_error "Cannot chmod public key file."; exit 1; }
}

#
# Entry point: installs Xray, creates config, starts service, and prints first client link.
#
# @description
#   Requires root. Prompts for SNI (default DEFAULT_SNI), port (parse_port), client name. Validates SNI with validate_sni; uses parse_port for port.
#   Installs dependencies and Xray, generates keys, writes config, runs test_config, restarts xray, builds client link. Logs "Done. Xray with VLESS+Reality is running on port ...".
#
install_server() {
  require_root
  detect_ubuntu

  local input_sni input_port sni port dest_for_config
  read -r -p "SNI (default: ${DEFAULT_SNI}): " input_sni || true
  input_sni="${input_sni//[[:space:]]/}"
  if [[ -z "${input_sni}" ]]; then
    sni="${DEFAULT_SNI}"
  else
    if validate_sni "${input_sni}"; then
      sni="${input_sni}"
    else
      log_warn "Invalid SNI, using default: ${DEFAULT_SNI}"
      sni="${DEFAULT_SNI}"
    fi
  fi

  read -r -p "Listen port for VLESS (default: ${DEFAULT_PORT}): " input_port || true
  port="$(parse_port "${DEFAULT_PORT}" "${input_port}")"
  dest_for_config="${sni}:443"

  local client_name
  read -r -p "Client name (default: ${DEFAULT_CLIENT_NAME}): " client_name || true
  client_name="${client_name:-$DEFAULT_CLIENT_NAME}"

  install_dependencies
  install_xray

  local uuid_value private_key public_key short_id
  IFS="|" read -r uuid_value private_key public_key short_id < <(generate_keys)
  write_config "$uuid_value" "$private_key" "$port" "$dest_for_config" "$sni" "$short_id" "$public_key" "$client_name"

  log_info "Validating Xray config..."
  test_config "${XRAY_CONFIG_PATH}"
  append_link "$uuid_value" "$short_id" "$public_key" "$port" "$sni" "$client_name"
  restart_xray

  log_info "Done. Xray with VLESS+Reality is running on port ${port}."
}
