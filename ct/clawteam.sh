#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: bughunt8
# License: MIT | https://github.com/bughunt8/proxmox-clawteam-general/raw/main/LICENSE
# Source: https://github.com/HKUDS/ClawTeam | OpenClaw: https://github.com/openclaw/openclaw

APP="ClawTeam"
var_tags="${var_tags:-ai;agents;clawteam}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/clawteam ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ClawTeam"
  /opt/clawteam/.venv/bin/pip install --quiet --upgrade clawteam
  msg_ok "Updated ClawTeam"

  msg_info "Updating OpenClaw"
  npm update -g openclaw 2>/dev/null
  msg_ok "Updated OpenClaw"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} To access the ClawTeam board inside the LXC, run:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}clawteam board attach <team-name>${CL}"
echo -e "${INFO}${YW} Web dashboard (if started):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
