#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPT_ROOT

# Source libs in dependency order (log first so common can use it; then common; validation; install; clients; config; uninstall)
# shellcheck source=../lib/log.sh
source "${SCRIPT_ROOT}/lib/log.sh"
# shellcheck source=../lib/common.sh
source "${SCRIPT_ROOT}/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${SCRIPT_ROOT}/lib/validation.sh"
# shellcheck source=../lib/install.sh
source "${SCRIPT_ROOT}/lib/install.sh"
# shellcheck source=../lib/clients.sh
source "${SCRIPT_ROOT}/lib/clients.sh"
# shellcheck source=../lib/firewall.sh
source "${SCRIPT_ROOT}/lib/firewall.sh"
# shellcheck source=../lib/config.sh
source "${SCRIPT_ROOT}/lib/config.sh"
# shellcheck source=../lib/service.sh
source "${SCRIPT_ROOT}/lib/service.sh"
# shellcheck source=../lib/uninstall.sh
source "${SCRIPT_ROOT}/lib/uninstall.sh"

#
# Menu dispatch table.
#
# @description
#   To add a new option, add it to MENU with value:
#     "action:needs_config:run_protected:label_no_config:label_with_config:label_condition_fn"
#   where:
#     - action: function name to call
#     - needs_config: "true"/"false" (whether XRAY_CONFIG_PATH must exist)
#     - run_protected: "true"/"false" (whether to call via run_protected)
#     - label_no_config: label to show when condition_fn is false or empty
#     - label_with_config: optional alternate label when condition_fn returns success
#     - label_condition_fn: optional function name that decides which label to use
#
declare -rA MENU=(
  ["1"]="install_or_uninstall:false:false:1) Install:1) Uninstall:config_exists"
  ["2"]="add_client:true:true:2) Add client:::"
  ["3"]="remove_client:true:true:3) Remove client:::"
  ["4"]="show_clients:true:true:4) Show clients:::"
  ["5"]="change_port:true:true:5) Change port:::"
  ["6"]="change_sni:true:true:6) Change SNI:::"
  ["7"]="start_server:true:true:7) Start server:::"
  ["8"]="stop_server:true:true:8) Stop server:::"
  ["9"]="show_server_status:true:true:9) Server status:::"
  ["10"]="show_xray_logs:true:true:10) Xray logs:::"
  ["11"]="restore_from_backup:false:false:11) Restore clients from backup:::"
  ["12"]="toggle_firewall:false:false:12) Turn on Firewall:12) Turn off Firewall:is_ufw_active"
)

menu_label() {
  local i=$1
  local action needs_config run_protected label_no_cfg label_cfg cond_fn

  IFS=':' read -r action needs_config run_protected label_no_cfg label_cfg cond_fn <<<"${MENU[$i]}"

  if [[ -n "${cond_fn}" ]] && "${cond_fn}"; then
    if [[ -n "${label_cfg}" ]]; then
      echo "${label_cfg}"
    else
      echo "${label_no_cfg}"
    fi
  else
    echo "${label_no_cfg}"
  fi
}

#
# Prints the main menu banner and option list to stdout.
#
# @description
#   Outputs "VLESS Reality Server Manager" header. Before install (no config): only 1) Install and 0) Exit.
#   After install: options 1-12 and 0; option 1 label is Uninstall, option 12 label depends on firewall status
#   (Turn on / Turn off Firewall). Labels are driven by the MENU table.
#
print_menu() {
  echo "==============================="
  echo "  VLESS Reality Server Manager"
  echo "==============================="
  echo ""
  if config_exists; then
    local i
    for i in $(seq 1 "${#MENU[@]}"); do
      echo "$(menu_label "${i}")"
    done
  else
    echo "$(menu_label 1)"
  fi
  echo "0) Exit"
  echo ""
}

#
# Prints a blank line and waits for Enter when stdin is a TTY; no-op otherwise.
#
# @description
#   Use after an action so the user can read the output before the menu redraws. Skips wait when not interactive (e.g. piped input).
#
prompt_to_continue() {
  echo ""
  if [[ -t 0 ]]; then
    read -r -p "Press Enter to continue..." _ || true
  fi
}

#
# Returns 0 if XRAY_CONFIG_PATH exists; otherwise logs warning and waits for Enter.
#
# @description
#   Use from within run_menu's while loop. If config is missing, logs and waits for Enter, then return 1 so the caller can continue the loop.
#
check_config() {
  if config_exists; then
    return 0
  fi
  log_warn "No config. Install first."
  prompt_to_continue
  return 1
}

install_or_uninstall() {
  if config_exists; then
    uninstall_server
  else
    install_server
  fi
}

run_action() {
  local opt=$1
  local action needs_config run_protected

  IFS=':' read -r action needs_config run_protected _ _ _ <<<"${MENU[$opt]}"

  if [[ "${needs_config}" == "true" ]]; then
    check_config || return
  fi

  if [[ "${run_protected}" == "true" ]]; then
    run_protected "${action}"
  else
    "${action}"
  fi

  prompt_to_continue
}

get_max_option() {
  if config_exists; then
    echo "${#MENU[@]}"
  else
    echo 1
  fi
}

validate_option() {
  local option=$1
  local max_option=$2

  if [[ ! "${option}" =~ ^[0-9]+$ ]] || [[ "${option}" -lt 0 ]] || [[ "${option}" -gt "${max_option}" ]]; then
    log_warn "Invalid option. Enter 0-${max_option}."
    return 1
  fi

  return 0
}

#
# Main loop: displays menu, reads option, dispatches via MENU.
#
# @description
#   Loops until user selects 0. Before install only 0 and 1 are accepted; after install options 0-12. On invalid input logs warning and re-prompts.
#   Option 1 runs Install or Uninstall depending on whether config exists (Uninstall requires confirmation: Type DELETE). Option 12 toggles firewall (Turn on / Turn off).
#   After each action except 0, prompts "Press Enter to continue" then redraws menu.
#
run_menu() {
  while true; do
    print_menu
    read -r -p "Select option: " option || true
    option="${option//[[:space:]]/}"

    local max_option
    max_option="$(get_max_option)"

    if ! validate_option "${option}" "${max_option}"; then
      prompt_to_continue
      continue
    fi

    if [[ "${option}" == "0" ]]; then
      log_info "Bye."
      exit 0
    fi

    run_action "${option}"
  done
}

run_menu
