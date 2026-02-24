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
# shellcheck source=../lib/config.sh
source "${SCRIPT_ROOT}/lib/config.sh"
# shellcheck source=../lib/uninstall.sh
source "${SCRIPT_ROOT}/lib/uninstall.sh"

#
# Prints the main menu banner and option list to stdout.
#
# @description
#   Outputs "VLESS Reality Server Manager" header and numbered options 1-7 and 0) Exit. No logic, display only.
#
print_menu() {
  echo "==============================="
  echo "  VLESS Reality Server Manager"
  echo "==============================="
  echo ""
  echo "1) Install"
  echo "2) Add client"
  echo "3) Remove client"
  echo "4) Show clients"
  echo "5) Change port"
  echo "6) Change SNI"
  echo "7) Uninstall server"
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
# Returns 0 if XRAY_CONFIG_PATH exists; otherwise logs warning, waits for Enter, and continues the enclosing loop.
#
# @description
#   Must be called from within run_menu's while loop. If config is missing, logs, waits for Enter, then continue (next menu iteration).
#
check_config() {
  if config_exists; then
    return 0
  fi
  log_warn "No config. Install first."
  prompt_to_continue
  continue
}

#
# Main loop: displays menu, reads option, dispatches to install/add/remove/show/port/sni/uninstall or exit.
#
# @description
#   Loops until user selects 0. Validates option as integer 0-7; on invalid input logs warning and re-prompts.
#   Options 3 (Remove client) and 7 (Uninstall) require confirmation (Type YES / Type DELETE) before calling remove_client or uninstall_server.
#   After each action except 0, prompts "Press Enter to continue" then redraws menu.
#
run_menu() {
  while true; do
    print_menu
    read -r -p "Select option: " option || true
    option="${option//[[:space:]]/}"
    if [[ ! "${option}" =~ ^[0-9]+$ ]] || [[ "${option}" -lt 0 ]] || [[ "${option}" -gt 7 ]]; then
      log_warn "Invalid option. Enter a number 0-7."
      prompt_to_continue
      continue
    fi

    case "${option}" in
      0)
        log_info "Bye."
        exit 0
        ;;
      1)
        install_server
        prompt_to_continue
        ;;
      2)
        check_config
        add_client
        prompt_to_continue
        ;;
      3)
        check_config
        remove_client
        prompt_to_continue
        ;;
      4)
        check_config
        show_clients
        prompt_to_continue
        ;;
      5)
        check_config
        change_port
        prompt_to_continue
        ;;
      6)
        check_config
        change_sni
        prompt_to_continue
        ;;
      7)
        uninstall_server
        prompt_to_continue
        ;;
    esac
  done
}

run_menu
