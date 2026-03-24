#!/usr/bin/env bash
# install/modules/08-nanobot.sh
#
# Install nanobot (https://github.com/HKUDS/nanobot) — an ultra-lightweight
# personal AI assistant that acts as the default worker agent inside a
# ClawTeam swarm.
#
# nanobot is the agent binary that ClawTeam spawns when you run:
#   clawteam spawn --team <team> --agent-name <name> --task "<task>"
#
# PyPI package : nanobot-ai
# Binary name  : nanobot
# Requires     : Python >= 3.11, Node.js (for WhatsApp bridge only)
#
# Run standalone:
#   bash install/modules/08-nanobot.sh

set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

NANOBOT_VENV="${NANOBOT_VENV:-/opt/nanobot/.venv}"
NANOBOT_BIN="/usr/local/bin/nanobot"
NANOBOT_CONFIG_DIR="${NANOBOT_CONFIG_DIR:-/root/.nanobot}"

if module_done "08-nanobot" && [[ -x "${NANOBOT_BIN}" ]]; then
  msg_ok "nanobot already installed — skipping."
  return 0 2>/dev/null || exit 0
fi

# ── Python 3.11+ is required by nanobot-ai ───────────────────────────────────
# Debian 13 (Trixie) ships python3.11 as the default python3; verify it.
python3_ver=$(python3 -c 'import sys; print(sys.version_info[:2])' 2>/dev/null || echo "(0, 0)")
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)' 2>/dev/null; then
  msg_warn "Python 3.11+ required for nanobot-ai (found ${python3_ver})"
  msg_info "Installing python3.11 explicitly..."
  $STD apt-get install -y python3.11 python3.11-venv
  PYTHON_BIN="python3.11"
else
  PYTHON_BIN="python3"
fi

# ── Create dedicated virtualenv ───────────────────────────────────────────────
msg_info "Installing nanobot"
mkdir -p "$(dirname "${NANOBOT_VENV}")"
"${PYTHON_BIN}" -m venv "${NANOBOT_VENV}"
"${NANOBOT_VENV}/bin/pip" install --quiet --upgrade pip

# Install nanobot-ai — the PyPI package that provides the `nanobot` binary
"${NANOBOT_VENV}/bin/pip" install --quiet nanobot-ai
msg_ok "Installed nanobot-ai"

# ── Symlink nanobot binary into system PATH ───────────────────────────────────
ln -sf "${NANOBOT_VENV}/bin/nanobot" "${NANOBOT_BIN}"

NANOBOT_VERSION=$("${NANOBOT_VENV}/bin/pip" show nanobot-ai 2>/dev/null \
  | awk '/^Version:/{print $2}') || NANOBOT_VERSION="unknown"
msg_ok "nanobot ${NANOBOT_VERSION} available at ${NANOBOT_BIN}"

# ── Bootstrap a minimal config so nanobot is runnable without interaction ─────
# nanobot onboard creates ~/.nanobot/config.json with sensible defaults.
# We run it non-interactively; users can customise the config afterwards
# (add API keys, choose a model/provider, enable channels, etc.).
if [[ ! -f "${NANOBOT_CONFIG_DIR}/config.json" ]]; then
  msg_info "Initialising nanobot config at ${NANOBOT_CONFIG_DIR}"
  # --no-wizard skips interactive prompts; the config is minimal but valid.
  # Errors here are non-fatal — the user can run 'nanobot onboard' themselves.
  "${NANOBOT_BIN}" onboard 2>/dev/null \
    || msg_warn "nanobot onboard skipped (run 'nanobot onboard' inside the container to configure)"
else
  msg_ok "nanobot config already exists — skipping onboard."
fi

mark_done "08-nanobot"
