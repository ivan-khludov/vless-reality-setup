#
# Validates that value is a UUID v4 format (8-4-4-4-12 hex).
#
# @description
#   Checks pattern xxxxxxxx-xxxx-4xxx-[89ab]xxx-xxxxxxxxxxxx. Exits 0 if valid, 1 if invalid.
#
# @param $1 value - string to validate as UUID
# @returns exit 0 if valid UUID v4, 1 otherwise
#
validate_uuid() {
  local value="${1//[[:space:]]/}"
  if [[ -z "${value}" ]]; then
    return 1
  fi
  if [[ "${value}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then
    return 0
  fi
  return 1
}

# Input validation helpers. No dependency on common.
# Sourced by bin/vless-manager.sh. Used by lib/config.sh and lib/clients.sh.

#
# Validates that value is a port number in 1..65535; echoes value on success.
#
# @description
#   If value is numeric and in range 1-65535, echoes it to stdout and exits 0. Otherwise exits 1.
#   Caller can use: port=$(validate_port "$input") or validate_port "$input" || exit 1.
#
# @param $1 value - string to validate as port
# @returns port number on stdout when valid; exit 0 if valid, 1 if invalid
#
validate_port() {
  local value="${1//[[:space:]]/}"
  if [[ -z "${value}" ]]; then
    return 1
  fi
  if [[ "${value}" =~ ^[0-9]+$ ]] && [[ "${value}" -ge 1 ]] && [[ "${value}" -le 65535 ]]; then
    echo "${value}"
    return 0
  fi
  return 1
}

#
# Validates that value is a non-empty domain (not an IP address).
#
# @description
#   Rejects empty, pure numeric, or IPv4-like patterns. Accepts hostnames with letters/digits/hyphens/dots.
#   Exits 0 if valid, 1 if invalid.
#
# @param $1 value - string to validate as SNI/domain
# @returns exit 0 if valid domain, 1 otherwise
#
validate_sni() {
  local value="${1//[[:space:]]/}"
  if [[ -z "${value}" ]]; then
    return 1
  fi
  # Reject IPv4
  if [[ "${value}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    return 1
  fi
  # Reject if it looks like numeric-only
  if [[ "${value}" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  # Basic domain: letters, digits, hyphens, dots
  if [[ "${value}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    return 0
  fi
  return 1
}