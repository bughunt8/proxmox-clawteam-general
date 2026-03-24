#!/usr/bin/env bash
# test/test_helper/stub-functions.bash
#
# Minimal shim for the community-scripts ProxmoxVE FUNCTIONS_FILE_PATH helpers.
# The install script does:
#   source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
# In tests, FUNCTIONS_FILE_PATH is set to the content of this file so that
# community-scripts helpers resolve to no-ops, allowing isolated unit testing.
#
# Also sourced by module tests to pre-populate the helper environment without
# needing a real community-scripts build.func.

# Colour / formatting variables (community-scripts defines these via color())
YW=""
GN=""
RD=""
BL=""
CL=""
DGN=""
BGN=""
CREATING=""
INFO=""
TAB=""
GATEWAY=""
CTID=""
IP=""

# $STD is empty in verbose mode; the install script prefixes commands with it.
# An empty value means the command runs normally (output passes through).
STD=""

# ── Core lifecycle functions ──────────────────────────────────────────────────

color()               { true; }
verb_ip6()            { true; }
catch_errors()        { true; }
setting_up_container(){ true; }
network_check()       { true; }
update_os()           { true; }
motd_ssh()            { true; }
customize()           { true; }
cleanup_lxc()         { true; }

# Node.js installer helper (community-scripts)
setup_nodejs()        { true; }

# ── Messaging helpers ─────────────────────────────────────────────────────────
# Output to fd 3 so bats captures it in --verbose output without affecting
# the test's $output (which captures stdout of `run`).

msg_info() {
  echo "[INFO]  $*" >&3 2>/dev/null || true
}

msg_ok() {
  echo "[ OK ]  $*" >&3 2>/dev/null || true
}

msg_error() {
  echo "[ERR ]  $*" >&3 2>/dev/null || true
}

msg_warn() {
  echo "[WARN]  $*" >&3 2>/dev/null || true
}

# ── Host-side helpers (used only by ct/clawteam.sh community-scripts mode) ───

variables()               { true; }
header_info()             { true; }
start()                   { true; }
build_container()         { true; }
description()             { true; }
check_container_storage() { true; }
check_container_resources(){ true; }
