#!/usr/bin/env bash
# install/modules/01-system-deps.sh
#
# Install system-level package dependencies.
#
# Run standalone:
#   bash install/modules/01-system-deps.sh
#
# Sourced by install/clawteam-install.sh (community-scripts or standalone).

set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

if module_done "01-system-deps"; then
  msg_ok "System dependencies already installed — skipping."
  return 0 2>/dev/null || exit 0
fi

msg_info "Installing system dependencies"
$STD apt-get install -y \
  curl \
  git \
  tmux \
  python3 \
  python3-pip \
  python3-venv \
  build-essential \
  libzmq3-dev
msg_ok "Installed system dependencies"

mark_done "01-system-deps"
