#!/usr/bin/env bash
# install/modules/02-nodejs.sh
#
# Install Node.js 22 via the community-scripts setup_nodejs helper when
# available, otherwise via the NodeSource setup script directly.
#
# Run standalone:
#   bash install/modules/02-nodejs.sh

set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[-1]}")/../lib/common.sh"

if module_done "02-nodejs"; then
  msg_ok "Node.js already installed — skipping."
  return 0 2>/dev/null || exit 0
fi

NODE_MAJOR="${NODE_MAJOR:-22}"

if declare -f setup_nodejs &>/dev/null; then
  # community-scripts helper path
  msg_info "Installing Node.js ${NODE_MAJOR} via setup_nodejs"
  NODE_VERSION="${NODE_MAJOR}" setup_nodejs
else
  # Standalone path: use the official NodeSource setup script
  msg_info "Installing Node.js ${NODE_MAJOR} via NodeSource"
  $STD curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  $STD apt-get install -y nodejs
fi

node_ver=$(node --version 2>/dev/null || echo "unknown")
msg_ok "Installed Node.js ${node_ver}"

mark_done "02-nodejs"
