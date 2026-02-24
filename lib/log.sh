# Logging helpers for user-facing messages. No dependency on common.
# Sourced by bin/vless-manager.sh after common.sh.

#
# Writes an informational message to stderr with prefix.
#
# @description
#   Outputs "INFO: $msg" to stderr. Use for normal progress or result messages.
#
# @param $1 msg - message string
#
log_info() {
  echo "INFO: $*" >&2
}

#
# Writes a warning message to stderr with prefix.
#
# @description
#   Outputs "WARN: $msg" to stderr. Use for non-fatal issues or invalid input.
#
# @param $1 msg - message string
#
log_warn() {
  echo "WARN: $*" >&2
}

#
# Writes an error message to stderr with prefix.
#
# @description
#   Outputs "ERROR: $msg" to stderr. Use for fatal errors before exiting.
#
# @param $1 msg - message string
#
log_error() {
  echo "ERROR: $*" >&2
}
