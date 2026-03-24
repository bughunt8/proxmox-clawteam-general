#!/usr/bin/env bash
# install/bootstrap.sh
#
# Entry point when invoked by community-scripts build_container via lxc-attach.
# Downloads the full install tree and runs the orchestrator.
#
# community-scripts exports FUNCTIONS_FILE_PATH into the container environment;
# we pass it through to the orchestrator so the community-scripts hooks
# (setting_up_container, network_check, update_os, etc.) run exactly once.

set -Eeo pipefail

REPO_RAW_URL="https://raw.githubusercontent.com/bughunt8/proxmox-clawteam-general/main"
INSTALL_ROOT="/tmp/clawteam-install"

# Download the full install tree
dl() {
  mkdir -p "$(dirname "${INSTALL_ROOT}/$1")"
  curl -fsSL "${REPO_RAW_URL}/install/$1" -o "${INSTALL_ROOT}/$1"
  chmod 755 "${INSTALL_ROOT}/$1"
}

dl "clawteam-install.sh"
dl "lib/common.sh"
dl "modules/01-system-deps.sh"
dl "modules/02-nodejs.sh"
dl "modules/03-openclaw.sh"
dl "modules/04-clawteam.sh"
dl "modules/05-workspace.sh"
dl "modules/06-systemd.sh"
dl "modules/07-motd.sh"
dl "modules/08-nanobot.sh"

# Run the orchestrator — FUNCTIONS_FILE_PATH is already exported by build_container
exec bash "${INSTALL_ROOT}/clawteam-install.sh"
