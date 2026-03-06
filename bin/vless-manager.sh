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
# Prints the main menu banner and option list to stdout.
#
# @description
#   Outputs "VLESS Reality Server Manager" header. Before install (no config): only 1) Install and 0) Exit. After install: options 1-12 and 0; option 1 label is Uninstall, option 12 label depends on firewall status (Turn on / Turn off Firewall).
#
print_menu() {
  echo "==============================="
  echo "  VLESS Reality Server Manager"
  echo "==============================="
  echo ""
  if config_exists; then
    echo "1) Uninstall"
    echo "2) Add client"
    echo "3) Remove client"
    echo "4) Show clients"
    echo "5) Change port"
    echo "6) Change SNI"
    echo "7) Start server"
    echo "8) Stop server"
    echo "9) Server status"
    echo "10) Xray logs"
    echo "11) Restore clients from backup"
    if is_ufw_active; then
      echo "12) Turn off Firewall"
    else
      echo "12) Turn on Firewall"
    fi
  else
    echo "1) Install"
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
# Main loop: displays menu, reads option, dispatches to install/uninstall/add/remove/show/port/sni/firewall or exit.
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
    local max_option=12
    config_exists || max_option=1
    if [[ ! "${option}" =~ ^[0-9]+$ ]] || [[ "${option}" -lt 0 ]] || [[ "${option}" -gt "${max_option}" ]]; then
      if [[ "${max_option}" -eq 1 ]]; then
        log_warn "Invalid option. Enter 0 or 1."
      else
        log_warn "Invalid option. Enter a number 0-12."
      fi
      prompt_to_continue
      continue
    fi

    case "${option}" in
      0)
        log_info "Bye."
        exit 0
        ;;
      1)
        if config_exists; then
          uninstall_server
        else
          install_server
        fi
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
        check_config
        start_server
        prompt_to_continue
        ;;
      8)
        check_config
        stop_server
        prompt_to_continue
        ;;
      9)
        check_config
        show_server_status
        prompt_to_continue
        ;;
      10)
        check_config
        show_xray_logs
        prompt_to_continue
        ;;
      11)
        restore_from_backup
        prompt_to_continue
        ;;
      12)
        toggle_firewall
        prompt_to_continue
        ;;
    esac
  done
}

run_menu
