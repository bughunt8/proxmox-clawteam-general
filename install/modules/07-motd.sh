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
echo "  ClawTeam + nanobot — AI Agent Swarm on Proxmox LXC"
echo "  ===================================================="
echo "  Workspace:   /root/workspace/openclaw-workspace"
echo ""
echo "  Quick start:"
echo "    clawteam team spawn-team my-team -d \"My swarm\" -n leader"
echo "    clawteam spawn --team my-team --agent-name alice --task \"<task>\""
echo "    clawteam spawn --team my-team --agent-name bob   --task \"<task>\""
echo ""
echo "  nanobot config:  ~/.nanobot/config.json  (add API key + model)"
echo "  nanobot onboard: nanobot onboard --wizard"
echo ""
echo "  Board:    clawteam board attach openclaw-team"
echo "  Web UI:   clawteam board serve --port 8080  (http://$(hostname -I | awk '{print $1}'):8080)"
echo "  Update:   bash ct/clawteam.sh --update <vmid>  (from Proxmox host)"
echo ""
EOF

chmod +x "${MOTD_FILE}"
msg_ok "Wrote MOTD"

mark_done "07-motd"
