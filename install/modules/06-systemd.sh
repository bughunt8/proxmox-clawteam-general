#!/usr/bin/env bash
# install/modules/06-systemd.sh
#
# Install and enable the clawteam-board systemd service (Web dashboard).
#
# Run standalone:
#   bash install/modules/06-systemd.sh

set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[-1]}")/../lib/common.sh"

SERVICE_FILE="/etc/systemd/system/clawteam-board.service"
WORKSPACE_DIR="${WORKSPACE_ROOT:-/root/workspace/openclaw-workspace}"

if module_done "06-systemd" && [[ -f "${SERVICE_FILE}" ]]; then
  msg_ok "clawteam-board service already installed — skipping."
  return 0 2>/dev/null || exit 0
fi

msg_info "Installing clawteam-board systemd service"

cat >"${SERVICE_FILE}" <<'EOF'
[Unit]
Description=ClawTeam Web Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/workspace/openclaw-workspace
ExecStart=/usr/local/bin/clawteam board serve --port 8080
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q clawteam-board
msg_ok "Installed and enabled clawteam-board service"

mark_done "06-systemd"
