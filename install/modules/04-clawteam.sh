#!/usr/bin/env bash
# install/modules/04-clawteam.sh
#
# Create a Python virtualenv and install ClawTeam (+ optional P2P transport).
# Symlinks the clawteam binary into /usr/local/bin.
#
# Run standalone:
#   bash install/modules/04-clawteam.sh

set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

CLAWTEAM_VENV="${CLAWTEAM_VENV:-/opt/clawteam/.venv}"
CLAWTEAM_BIN="/usr/local/bin/clawteam"

if module_done "04-clawteam" && [[ -x "${CLAWTEAM_BIN}" ]]; then
  msg_ok "ClawTeam already installed — skipping."
  return 0 2>/dev/null || exit 0
fi

msg_info "Installing ClawTeam"
mkdir -p "$(dirname "${CLAWTEAM_VENV}")"
python3 -m venv "${CLAWTEAM_VENV}"
"${CLAWTEAM_VENV}/bin/pip" install --quiet --upgrade pip
"${CLAWTEAM_VENV}/bin/pip" install --quiet clawteam

# Optional P2P (ZeroMQ) transport — requires libzmq3-dev
if "${CLAWTEAM_VENV}/bin/pip" install --quiet "clawteam[p2p]" 2>/dev/null; then
  msg_ok "Installed ClawTeam P2P (ZeroMQ) transport"
else
  msg_warn "ClawTeam P2P transport skipped (pyzmq build failed — libzmq3-dev missing?)"
fi

# Symlink clawteam into system PATH
ln -sf "${CLAWTEAM_VENV}/bin/clawteam" "${CLAWTEAM_BIN}"

CLAWTEAM_VERSION=$(pip show clawteam 2>/dev/null | awk '/^Version:/{print $2}') \
  || CLAWTEAM_VERSION="unknown"
msg_ok "Installed ClawTeam ${CLAWTEAM_VERSION}"

mark_done "04-clawteam"
