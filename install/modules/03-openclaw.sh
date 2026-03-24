#!/usr/bin/env bash
# install/modules/03-openclaw.sh
#
# Install OpenClaw globally via npm.
#
# Run standalone:
#   bash install/modules/03-openclaw.sh

set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[-1]}")/../lib/common.sh"

if module_done "03-openclaw"; then
  msg_ok "OpenClaw already installed — skipping."
  return 0 2>/dev/null || exit 0
fi

msg_info "Installing OpenClaw"
# npm install -g is idempotent: installs or upgrades to the latest version
$STD npm install -g openclaw@latest
msg_ok "Installed OpenClaw"

mark_done "03-openclaw"
