#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: bughunt8
# License: MIT | https://github.com/bughunt8/proxmox-clawteam-general/raw/main/LICENSE
# Source: https://github.com/HKUDS/ClawTeam | OpenClaw: https://github.com/openclaw/openclaw

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  git \
  tmux \
  python3 \
  python3-pip \
  python3-venv \
  build-essential \
  libzmq3-dev
msg_ok "Installed Dependencies"

NODE_VERSION="22" setup_nodejs

msg_info "Installing OpenClaw"
$STD npm install -g openclaw@latest
msg_ok "Installed OpenClaw"

msg_info "Installing ClawTeam"
mkdir -p /opt/clawteam
python3 -m venv /opt/clawteam/.venv
/opt/clawteam/.venv/bin/pip install --quiet --upgrade pip
/opt/clawteam/.venv/bin/pip install --quiet clawteam
# Optional P2P (ZeroMQ) transport — requires libzmq3-dev
if /opt/clawteam/.venv/bin/pip install --quiet "clawteam[p2p]" 2>/dev/null; then
  msg_ok "Installed ClawTeam P2P (ZeroMQ) transport"
else
  msg_warn "ClawTeam P2P transport skipped (pyzmq build failed)"
fi
# Symlink clawteam into system PATH
ln -sf /opt/clawteam/.venv/bin/clawteam /usr/local/bin/clawteam
CLAWTEAM_VERSION=$(pip show clawteam 2>/dev/null | awk '/^Version:/{print $2}') || CLAWTEAM_VERSION="unknown"
msg_ok "Installed ClawTeam ${CLAWTEAM_VERSION}"

msg_info "Configuring git identity for workspace"
# ClawTeam's team initialisation commits to git; a git user identity is required
git config --global user.email "clawteam@localhost"
git config --global user.name "ClawTeam"
msg_ok "Configured git identity"

msg_info "Creating ClawTeam default workspace"
mkdir -p /root/workspace/openclaw-workspace
git -C /root/workspace init -q openclaw-workspace
msg_ok "Initialised git workspace"

msg_info "Creating default team (openclaw-team)"
# spawn-team flags: positional <team-name>, -d/--description, -n <leader-name>
# Note: --agent-name belongs to 'clawteam spawn', not 'clawteam team spawn-team'
if clawteam team spawn-team openclaw-team \
    -d "OpenClaw AI agent swarm on Proxmox LXC" \
    -n leader; then
  msg_ok "Created default team 'openclaw-team'"
else
  msg_warn "Default team creation skipped (team may already exist or clawteam not yet configured)"
fi

msg_info "Creating ClawTeam systemd service"
cat <<'EOF' >/etc/systemd/system/clawteam-board.service
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
msg_ok "Created ClawTeam systemd service"

msg_info "Writing MOTD helper"
cat <<'EOF' >/etc/update-motd.d/99-clawteam
#!/bin/bash
echo ""
echo "  ClawTeam (OpenClaw) — Agent Swarm on Proxmox LXC"
echo "  ================================================="
echo "  Workspace:   /root/workspace/openclaw-workspace"
echo "  Board:       clawteam board attach openclaw-team"
echo "  Web UI:      clawteam board serve --port 8080"
echo "  Spawn agent: clawteam spawn tmux openclaw --team openclaw-team --agent-name <name> --task \"<task>\""
echo ""
EOF
chmod +x /etc/update-motd.d/99-clawteam
msg_ok "Wrote MOTD"

motd_ssh
customize
cleanup_lxc
