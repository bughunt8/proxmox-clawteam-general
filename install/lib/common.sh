#!/usr/bin/env bash
# install/lib/common.sh
#
# Shared helpers for all install modules.
# Works in two contexts:
#
#   1. community-scripts (inside LXC, FUNCTIONS_FILE_PATH is set)
#      msg_info / msg_ok / msg_warn / msg_error are already defined by the
#      sourced build.func shim; this file's definitions are skipped.
#
#   2. standalone (run directly as root inside a Debian container/VM)
#      Provides minimal ANSI-coloured equivalents.
#
# Source this file at the top of every module:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# ── Guard: only define helpers if not already provided by community-scripts ──

if ! declare -f msg_info &>/dev/null; then
  # Minimal ANSI colours
  _YW='\033[33m'   # yellow
  _GN='\033[32m'   # green
  _RD='\033[31m'   # red
  _CL='\033[0m'    # reset

  msg_info()  { echo -e "  ${_YW}⟳${_CL}  $*"; }
  msg_ok()    { echo -e "  ${_GN}✓${_CL}  $*"; }
  msg_warn()  { echo -e "  ${_YW}⚠${_CL}  $*" >&2; }
  msg_error() { echo -e "  ${_RD}✗${_CL}  $*" >&2; }
fi

# STD: community-scripts sets this to suppress output in quiet mode.
# In standalone mode it is empty (commands produce normal output).
STD="${STD:-}"

# ── Idempotency helpers ───────────────────────────────────────────────────────

# already_installed CMD
#   Returns 0 if CMD exists on PATH, 1 otherwise.
#   Used to skip steps that have already been completed.
already_installed() {
  command -v "$1" &>/dev/null
}

# dir_exists PATH
#   Returns 0 if the directory exists.
dir_exists() {
  [[ -d "$1" ]]
}

# module_done MARKER
#   Returns 0 if the module's idempotency marker file exists.
module_done() {
  [[ -f "/var/lib/clawteam/done/$1" ]]
}

# mark_done MARKER
#   Creates the idempotency marker for the current module.
mark_done() {
  mkdir -p /var/lib/clawteam/done
  touch "/var/lib/clawteam/done/$1"
}
