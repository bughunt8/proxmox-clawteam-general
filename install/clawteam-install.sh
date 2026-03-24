#!/usr/bin/env bash
# install/clawteam-install.sh
#
# Copyright (c) 2021-2026 community-scripts ORG
# Author: bughunt8
# License: MIT | https://github.com/bughunt8/proxmox-clawteam-general/raw/main/LICENSE
# Source: https://github.com/HKUDS/ClawTeam | OpenClaw: https://github.com/openclaw/openclaw
#
# Orchestrator — sources each install module in order.
#
# USAGE
#   Inside LXC (community-scripts, FUNCTIONS_FILE_PATH injected by host):
#     source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"   # already done by build.func
#     bash /tmp/clawteam-install.sh
#
#   Standalone (run directly as root inside a Debian 13 container):
#     bash install/clawteam-install.sh
#
#   Single module only (e.g. re-run just the systemd step):
#     bash install/modules/06-systemd.sh

# Note: do NOT set -u here — the community-scripts verb_ip6() function
# references $SSH_CLIENT which may be unset in non-SSH environments.
# catch_errors() (called below after verb_ip6) installs set -Eeuo pipefail.
# In standalone mode each module sets its own error handling.

# ── Locate the modules directory relative to this script ─────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"

# ── community-scripts preamble ────────────────────────────────────────────────
# When injected by build.func, FUNCTIONS_FILE_PATH is set; source it.
# In standalone mode the variable is empty and this block is skipped.
if [[ -n "${FUNCTIONS_FILE_PATH:-}" ]]; then
  # shellcheck disable=SC1090
  source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
  color
  verb_ip6
  catch_errors
  setting_up_container
  network_check
  update_os
fi

# ── Load shared helpers (defines msg_info/ok/warn/error if not yet defined) ───
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

# ── Run each module in order ──────────────────────────────────────────────────
# Modules are designed to be idempotent: they check a marker file and skip
# gracefully if they have already run.  Re-running this script is safe.

_run_module() {
  local module="$1"
  local path="${MODULES_DIR}/${module}"
  if [[ ! -f "${path}" ]]; then
    msg_error "Module not found: ${path}"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "${path}"
}

# Node.js must be set up via the community-scripts helper when available;
# the module handles both paths internally.
_run_module "01-system-deps.sh"
_run_module "02-nodejs.sh"
_run_module "03-openclaw.sh"
_run_module "04-clawteam.sh"
_run_module "05-workspace.sh"
_run_module "06-systemd.sh"
_run_module "07-motd.sh"

# ── community-scripts teardown (no-op when stubs are loaded) ─────────────────
if declare -f motd_ssh &>/dev/null;   then motd_ssh;   fi
if declare -f customize &>/dev/null;  then customize;  fi
if declare -f cleanup_lxc &>/dev/null; then cleanup_lxc; fi
