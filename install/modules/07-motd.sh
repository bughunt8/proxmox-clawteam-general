#!/usr/bin/env bash
# install/modules/07-motd.sh
#
# Write the MOTD (Message of the Day) helper script.
#
# Run standalone:
#   bash install/modules/07-motd.sh

set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

MOTD_FILE="/etc/update-motd.d/99-clawteam"

if module_done "07-motd" && [[ -x "${MOTD_FILE}" ]]; then
  msg_ok "MOTD already written — skipping."
  return 0 2>/dev/null || exit 0
fi

msg_info "Writing MOTD helper"

cat >"${MOTD_FILE}" <<'EOF'
#!/bin/bash
echo ""
echo "  ClawTeam (OpenClaw) — Agent Swarm on Proxmox LXC"
echo "  ================================================="
echo "  Workspace:   /root/workspace/openclaw-workspace"
echo "  Board:       clawteam board attach openclaw-team"
echo "  Web UI:      clawteam board serve --port 8080"
echo "  Spawn agent: clawteam spawn tmux openclaw --team openclaw-team --agent-name <name> --task \"<task>\""
echo "  Update:      bash ct/clawteam.sh --update <vmid>   (from Proxmox host)"
echo ""
EOF

chmod +x "${MOTD_FILE}"
msg_ok "Wrote MOTD"

mark_done "07-motd"
