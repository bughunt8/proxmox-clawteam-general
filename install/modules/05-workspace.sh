#!/usr/bin/env bash
# install/modules/05-workspace.sh
#
# Configure git identity, initialise the default workspace, and bootstrap
# the initial 'openclaw-team' ClawTeam team.
#
# Run standalone:
#   bash install/modules/05-workspace.sh

set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

WORKSPACE_ROOT="${WORKSPACE_ROOT:-/root/workspace}"
WORKSPACE_NAME="${WORKSPACE_NAME:-openclaw-workspace}"
TEAM_NAME="${TEAM_NAME:-openclaw-team}"
WORKSPACE_DIR="${WORKSPACE_ROOT}/${WORKSPACE_NAME}"

# ── git identity ──────────────────────────────────────────────────────────────
if ! git config --global user.email &>/dev/null || \
   [[ -z "$(git config --global user.email 2>/dev/null)" ]]; then
  msg_info "Configuring git identity"
  git config --global user.email "clawteam@localhost"
  git config --global user.name  "ClawTeam"
  msg_ok "Configured git identity"
else
  msg_ok "git identity already configured — skipping."
fi

# ── workspace directory ───────────────────────────────────────────────────────
if [[ ! -d "${WORKSPACE_DIR}/.git" ]]; then
  msg_info "Initialising workspace at ${WORKSPACE_DIR}"
  mkdir -p "${WORKSPACE_ROOT}"
  git -C "${WORKSPACE_ROOT}" init -q "${WORKSPACE_NAME}"
  msg_ok "Initialised git workspace"
else
  msg_ok "Workspace already exists — skipping git init."
fi

# ── bootstrap default team ────────────────────────────────────────────────────
if module_done "05-workspace-team"; then
  msg_ok "Default team '${TEAM_NAME}' already bootstrapped — skipping."
  return 0 2>/dev/null || exit 0
fi

msg_info "Creating default team '${TEAM_NAME}'"
# spawn-team flags: -d description, -n leader name
# Must run from within the workspace directory
if (cd "${WORKSPACE_DIR}" && clawteam team spawn-team "${TEAM_NAME}" \
      -d "OpenClaw AI agent swarm on Proxmox LXC" \
      -n leader); then
  msg_ok "Created default team '${TEAM_NAME}'"
  mark_done "05-workspace-team"
else
  msg_warn "Team creation skipped (team may already exist or clawteam not yet configured)"
fi
