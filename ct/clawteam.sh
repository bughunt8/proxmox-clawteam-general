#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: bughunt8
# License: MIT | https://github.com/bughunt8/proxmox-clawteam-general/raw/main/LICENSE
# Source: https://github.com/HKUDS/ClawTeam | OpenClaw: https://github.com/openclaw/openclaw
#
# USAGE
#   On the Proxmox VE host shell:
#
#   # Via community-scripts (interactive wizard):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/bughunt8/proxmox-clawteam-general/main/ct/clawteam.sh)"
#
#   # Standalone (no internet dependency beyond template download):
#   STANDALONE=1 bash ct/clawteam.sh
#
#   # Standalone with overrides:
#   CT_ID=110 CT_RAM=8192 CT_DISK=20 STANDALONE=1 bash ct/clawteam.sh
#
#   # Update an existing container (community-scripts re-run):
#   bash -c "$(curl -fsSL .../ct/clawteam.sh)" -- --update <vmid>

# Note: do NOT set -u here — build.func's verb_ip6() references $SSH_CLIENT
# which is unset in non-SSH environments; setting -u before sourcing build.func
# causes a fatal "SSH_CLIENT: unbound variable" error.
# In standalone mode _pct_standalone() sets its own error handling explicitly.
set -Eeo pipefail

# ── Application metadata ──────────────────────────────────────────────────────

APP="ClawTeam"
REPO_RAW_URL="https://raw.githubusercontent.com/bughunt8/proxmox-clawteam-general/main"
INSTALL_SCRIPT_URL="${REPO_RAW_URL}/install/clawteam-install.sh"

# ── Default LXC configuration ─────────────────────────────────────────────────
# All defaults can be overridden via environment variables when running
# in STANDALONE mode (e.g. CT_RAM=8192 bash ct/clawteam.sh).
# In community-scripts mode these map to the var_* convention.

var_tags="${var_tags:-ai;agents;clawteam}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

# Standalone-mode overrides (CT_* env vars take precedence)
CT_ID="${CT_ID:-}"
CT_HOSTNAME="${CT_HOSTNAME:-clawteam}"
CT_CORES="${CT_CORES:-${var_cpu}}"
CT_RAM="${CT_RAM:-${var_ram}}"
CT_SWAP="${CT_SWAP:-${var_ram}}"
CT_DISK="${CT_DISK:-${var_disk}}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
CT_STORAGE="${CT_STORAGE:-local-lvm}"
CT_TMPL_STORAGE="${CT_TMPL_STORAGE:-local}"
CT_UNPRIVILEGED="${CT_UNPRIVILEGED:-${var_unprivileged}}"
CT_ONBOOT="${CT_ONBOOT:-1}"

# Debian 13 (Trixie) template name on pveam
DEBIAN_TMPL_PATTERN="debian-13-standard"

# ── Detect execution mode ─────────────────────────────────────────────────────
# STANDALONE=1  → pure pct/pveam path, no community-scripts dependency
# (default)     → source build.func and use the community-scripts wizard

STANDALONE="${STANDALONE:-0}"

# ─────────────────────────────────────────────────────────────────────────────
# SHARED HELPERS
# These work in both modes and are always defined before any community-scripts
# functions are sourced so they can be safely overridden by build.func.
# ─────────────────────────────────────────────────────────────────────────────

_info()  { echo "  [INFO]  $*"; }
_ok()    { echo "  [ OK ]  $*"; }
_warn()  { echo "  [WARN]  $*" >&2; }
_error() { echo "  [ERR ]  $*" >&2; }
_die()   { _error "$*"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
# STANDALONE MODE — pure pct / pveam implementation
# Requires: Proxmox VE host with pct, pveam, pvesh available.
# ─────────────────────────────────────────────────────────────────────────────

_pct_standalone() {
  # Standalone path owns its environment — enable full strict mode here
  set -u

  # Verify we are running on a Proxmox VE host
  if ! command -v pct &>/dev/null; then
    _die "pct not found. This script must run on a Proxmox VE host."
  fi
  if ! command -v pveam &>/dev/null; then
    _die "pveam not found. This script must run on a Proxmox VE host."
  fi

  # ── Resolve container ID ───────────────────────────────────────────────────
  if [[ -z "${CT_ID}" ]]; then
    # Find the next available VMID above 100
    CT_ID=$(pvesh get /cluster/nextid 2>/dev/null || echo "")
    if [[ -z "${CT_ID}" ]]; then
      # Fallback: find lowest unused ID starting from 100
      CT_ID=100
      while pct status "${CT_ID}" &>/dev/null; do
        (( CT_ID++ ))
      done
    fi
  fi
  _info "Container ID: ${CT_ID}"

  # ── Ensure Debian 13 template is downloaded ────────────────────────────────
  _info "Checking for Debian 13 template on ${CT_TMPL_STORAGE}..."
  local tmpl_name tmpl_vol
  # Prefer an already-downloaded template
  tmpl_name=$(pveam list "${CT_TMPL_STORAGE}" 2>/dev/null \
    | awk -F'[: ]' '{print $2}' \
    | grep "${DEBIAN_TMPL_PATTERN}" \
    | sort -rV | head -1)

  if [[ -z "${tmpl_name}" ]]; then
    _info "No local Debian 13 template found — fetching catalog..."
    pveam update
    tmpl_name=$(pveam available --section system 2>/dev/null \
      | awk '{print $2}' \
      | grep "${DEBIAN_TMPL_PATTERN}" \
      | sort -rV | head -1)
    [[ -n "${tmpl_name}" ]] \
      || _die "Could not find a ${DEBIAN_TMPL_PATTERN} template in pveam catalog."
    _info "Downloading template: ${tmpl_name}"
    pveam download "${CT_TMPL_STORAGE}" "${tmpl_name}" \
      || _die "Template download failed."
    _ok "Downloaded ${tmpl_name}"
  else
    _ok "Using existing template: ${tmpl_name}"
  fi
  tmpl_vol="${CT_TMPL_STORAGE}:vztmpl/${tmpl_name}"

  # ── Create the LXC container ───────────────────────────────────────────────
  _info "Creating LXC container ${CT_ID} (${CT_HOSTNAME})..."
  pct create "${CT_ID}" "${tmpl_vol}" \
    --hostname   "${CT_HOSTNAME}" \
    --cores      "${CT_CORES}" \
    --memory     "${CT_RAM}" \
    --swap       "${CT_SWAP}" \
    --rootfs     "${CT_STORAGE}:${CT_DISK}" \
    --net0       "name=eth0,bridge=${CT_BRIDGE},ip=dhcp,type=veth" \
    --unprivileged "${CT_UNPRIVILEGED}" \
    --features   "nesting=1" \
    --onboot     "${CT_ONBOOT}" \
    --tags       "${var_tags}" \
    --start      1
  _ok "Container ${CT_ID} created and started."

  # ── Wait for network to be ready ──────────────────────────────────────────
  _info "Waiting for container network..."
  local retries=20
  local ct_ip=""
  while [[ $retries -gt 0 && -z "${ct_ip}" ]]; do
    ct_ip=$(pct exec "${CT_ID}" -- hostname -I 2>/dev/null | awk '{print $1}' || true)
    [[ -z "${ct_ip}" ]] && { sleep 2; (( retries-- )); }
  done
  if [[ -n "${ct_ip}" ]]; then
    _ok "Container IP: ${ct_ip}"
  else
    _warn "Could not determine container IP — continuing anyway."
  fi

  # ── Push and run the install script inside the container ──────────────────
  _pct_run_install "${CT_ID}"

  # ── Final summary ─────────────────────────────────────────────────────────
  _print_summary "${CT_ID}" "${ct_ip:-<check: pct exec ${CT_ID} -- hostname -I>}"
}

# _pct_run_install CTID
#   Delivers the full install tree into the container and executes the
#   orchestrator.  Works in two modes:
#
#   Local (development): the repo is checked out alongside ct/clawteam.sh.
#     All files under install/ are pushed with pct push.
#
#   Remote (production curl invocation): files are downloaded from GitHub
#     directly inside the container using a single bootstrap command.
#
_pct_run_install() {
  local ctid="$1"
  local install_root="/tmp/clawteam-install"
  local local_install_dir
  local_install_dir="$(dirname "${BASH_SOURCE[0]}")/../install"

  if [[ -d "${local_install_dir}" ]]; then
    # ── Local mode: push every file preserving directory structure ──────────
    _info "Pushing local install tree into container ${ctid}..."
    local f
    while IFS= read -r -d '' f; do
      local rel="${f#"${local_install_dir}/"}"
      local dest="${install_root}/${rel}"
      pct exec "${ctid}" -- mkdir -p "$(dirname "${dest}")"
      pct push "${ctid}" "${f}" "${dest}" --perms 0755 --user root
    done < <(find "${local_install_dir}" -type f -print0)
  else
    # ── Remote mode: bootstrap the full tree inside the container ───────────
    _info "Downloading install tree into container ${ctid}..."
    pct exec "${ctid}" -- bash -c "
      set -e
      BASE='${REPO_RAW_URL}'
      ROOT='${install_root}'
      dl() { mkdir -p \"\$(dirname \"\${ROOT}/\$1\")\"; curl -fsSL \"\${BASE}/install/\$1\" -o \"\${ROOT}/\$1\"; chmod 755 \"\${ROOT}/\$1\"; }
      dl 'clawteam-install.sh'
      dl 'lib/common.sh'
      dl 'modules/01-system-deps.sh'
      dl 'modules/02-nodejs.sh'
      dl 'modules/03-openclaw.sh'
      dl 'modules/04-clawteam.sh'
      dl 'modules/05-workspace.sh'
      dl 'modules/06-systemd.sh'
      dl 'modules/07-motd.sh'
    "
  fi

  _info "Running install script inside container ${ctid}..."
  pct exec "${ctid}" -- bash "${install_root}/clawteam-install.sh"
  _ok "Install script completed inside container ${ctid}."
}

# _pct_update CTID
#   Update ClawTeam and OpenClaw inside an existing container via pct exec.
_pct_update() {
  local ctid="$1"

  # Verify the container exists and has ClawTeam installed
  pct status "${ctid}" &>/dev/null \
    || _die "Container ${ctid} not found."
  pct exec "${ctid}" -- test -d /opt/clawteam \
    || _die "No ClawTeam installation found in container ${ctid}."

  _info "Starting container ${ctid} if not running..."
  if [[ "$(pct status "${ctid}" | awk '{print $2}')" != "running" ]]; then
    pct start "${ctid}"
    sleep 3
  fi

  _info "Updating ClawTeam in container ${ctid}..."
  pct exec "${ctid}" -- \
    /opt/clawteam/.venv/bin/pip install --quiet --upgrade clawteam
  _ok "Updated ClawTeam"

  _info "Updating OpenClaw in container ${ctid}..."
  pct exec "${ctid}" -- npm install -g openclaw@latest
  _ok "Updated OpenClaw"

  _ok "Container ${ctid} updated successfully."
}

_print_summary() {
  local ctid="$1"
  local ip="$2"
  echo ""
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║   ${APP} — LXC Container Ready                    ║"
  echo "  ╠══════════════════════════════════════════════════════╣"
  printf "  ║   Container ID : %-35s║\n" "${ctid}"
  printf "  ║   IP Address   : %-35s║\n" "${ip}"
  printf "  ║   Hostname     : %-35s║\n" "${CT_HOSTNAME}"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo "  ║   Enter the container:                               ║"
  printf "  ║     pct enter %-38s║\n" "${ctid}"
  echo "  ║   Attach to swarm board:                             ║"
  echo "  ║     clawteam board attach openclaw-team              ║"
  echo "  ║   Web dashboard:                                     ║"
  printf "  ║     http://%-41s║\n" "${ip}:8080"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMUNITY-SCRIPTS MODE — uses build.func wizard + delegates to pct helpers
# ─────────────────────────────────────────────────────────────────────────────

_community_scripts_mode() {
  # core.func's ssh_check() reads $SSH_CLIENT to detect SSH sessions.
  # The silent()/$STD wrapper inside core.func restores set -Eeuo pipefail
  # after every command, so $SSH_CLIENT must be bound before build.func is
  # sourced — otherwise any code path that runs under set -u will fatal.
  SSH_CLIENT="${SSH_CLIENT:-}"
  export SSH_CLIENT

  # Source the community-scripts build framework
  # shellcheck disable=SC1090
  source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

  # variables must run before header_info so APP/NSAPP are resolved
  variables
  header_info "$APP"
  color
  catch_errors

  # Patch build_container to fetch OUR bootstrap script instead of the
  # community-scripts install URL (which doesn't exist for this repo).
  # bootstrap.sh downloads the full install tree and runs the orchestrator.
  local _bc_src
  _bc_src="$(declare -f build_container)"
  eval "${_bc_src//"https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/\${var_install}.sh"/"${REPO_RAW_URL}/install/bootstrap.sh"}"

  # ── update_script: called when re-running against an existing container ────
  function update_script() {
    header_info
    check_container_storage
    check_container_resources
    if [[ ! -d /opt/clawteam ]]; then
      msg_error "No ${APP} Installation Found!"
      exit 1
    fi

    msg_info "Updating ClawTeam"
    /opt/clawteam/.venv/bin/pip install --quiet --upgrade clawteam
    msg_ok "Updated ClawTeam"

    msg_info "Updating OpenClaw"
    # Use install -g (idempotent) not npm update
    $STD npm install -g openclaw@latest
    msg_ok "Updated OpenClaw"

    msg_ok "Updated Successfully"
    exit 0
  }

  start
  build_container
  description

  msg_ok "Completed Successfully!\n"
  echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
  echo -e "${INFO}${YW} Enter the container:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}pct enter ${CTID}${CL}"
  echo -e "${INFO}${YW} Attach to swarm board inside the LXC:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}clawteam board attach openclaw-team${CL}"
  if [[ -n "${IP:-}" ]]; then
    echo -e "${INFO}${YW} Web dashboard (auto-started on port 8080):${CL}"
    echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

# Parse --update <vmid> flag (standalone update path)
if [[ "${1:-}" == "--update" ]]; then
  [[ -n "${2:-}" ]] || _die "Usage: $0 --update <vmid>"
  _pct_update "$2"
  exit 0
fi

if [[ "${STANDALONE}" == "1" ]]; then
  _pct_standalone
else
  _community_scripts_mode
fi
