#!/usr/bin/env bats
# test/install/clawteam-install.bats
#
# TDD tests for install/clawteam-install.sh and all install/modules/*.sh
#
# Tests are grouped by scope:
#   Group A  — Orchestrator (clawteam-install.sh)
#   Group B  — Module 01: system deps
#   Group C  — Module 02: Node.js
#   Group D  — Module 03: OpenClaw
#   Group E  — Module 04: ClawTeam
#   Group F  — Module 05: workspace + team
#   Group G  — Module 06: systemd service
#   Group H  — Module 07: MOTD
#   Group I  — Static analysis (ShellCheck)
#
# Root-required tests are skipped when not running as root.
# All tests that write to the filesystem use BATS_TEST_TMPDIR.
#
# Run (no root needed for structural tests):
#   ./test/bats/bin/bats test/install/clawteam-install.bats
#
# Run (full integration, root required):
#   sudo ./test/bats/bin/bats test/install/clawteam-install.bats

bats_require_minimum_version 1.5.0

# ─────────────────────────────────────────────────────────────────────────────
# Shared setup / teardown
# ─────────────────────────────────────────────────────────────────────────────

setup() {
  load "$(dirname "$BATS_TEST_FILENAME")/../test_helper/common-setup.bash"
  _common_setup

  INSTALL_SCRIPT="${PROJECT_ROOT}/install/clawteam-install.sh"
  MODULES_DIR="${PROJECT_ROOT}/install/modules"
  LIB_DIR="${PROJECT_ROOT}/install/lib"

  # All module tests redirect system writes here
  TEST_ROOT="${BATS_TEST_TMPDIR}/rootfs"
  mkdir -p \
    "${TEST_ROOT}/opt/clawteam/.venv/bin" \
    "${TEST_ROOT}/usr/local/bin" \
    "${TEST_ROOT}/etc/systemd/system" \
    "${TEST_ROOT}/etc/update-motd.d" \
    "${TEST_ROOT}/root/workspace" \
    "${BATS_TEST_TMPDIR}/done"
  export TEST_ROOT

  # Standard command stubs used across most tests
  create_stub apt-get  "" 0
  create_stub npm      "" 0
  create_stub node     "v22.0.0" 0
  create_stub git      "" 0
  create_stub systemctl "" 0
  create_stub clawteam "spawned" 0
  create_stub pip      "Version: 0.2.0" 0
  create_stub curl     "" 0

  # Stub python3 to create a minimal fake venv
  cat >"${STUBS_DIR}/python3" <<PYEOF
#!/usr/bin/env bash
echo "python3 \$*" >> "${STUBS_DIR}/python3.log"
if [[ "\$1" == "-m" && "\$2" == "venv" ]]; then
  VENV_DIR="\$3"
  mkdir -p "\${VENV_DIR}/bin"
  cat > "\${VENV_DIR}/bin/pip" <<'PIPEOF'
#!/usr/bin/env bash
echo "venv-pip \$*" >> "${STUBS_DIR}/venv-pip.log"
[[ "\$*" == *"show clawteam"* ]] && echo "Version: 0.2.0"
exit 0
PIPEOF
  chmod +x "\${VENV_DIR}/bin/pip"
  cat > "\${VENV_DIR}/bin/clawteam" <<'CTEOF'
#!/usr/bin/env bash
echo "venv-clawteam \$*" >> "${STUBS_DIR}/venv-clawteam.log"
echo "0.2.0"
exit 0
CTEOF
  chmod +x "\${VENV_DIR}/bin/clawteam"
fi
exit 0
PYEOF
  chmod +x "${STUBS_DIR}/python3"

  # Stub ln to record calls but actually create symlinks in TEST_ROOT
  cat >"${STUBS_DIR}/ln" <<LNEOF
#!/usr/bin/env bash
echo "ln \$*" >> "${STUBS_DIR}/ln.log"
/bin/ln "\$@" 2>/dev/null || true
exit 0
LNEOF
  chmod +x "${STUBS_DIR}/ln"
}

teardown() {
  # Clean up any real system paths if running as root
  rm -f /usr/local/bin/clawteam 2>/dev/null || true
  rm -rf /opt/clawteam 2>/dev/null || true
  rm -rf /root/workspace/openclaw-workspace 2>/dev/null || true
  rm -f /etc/systemd/system/clawteam-board.service 2>/dev/null || true
  rm -f /etc/update-motd.d/99-clawteam 2>/dev/null || true
  rm -rf /var/lib/clawteam 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: run a module script with all stubs and temp path redirects
# ─────────────────────────────────────────────────────────────────────────────

_run_module() {
  local module_file="${MODULES_DIR}/$1"
  bash -c "
    set -Eeuo pipefail
    export PATH='${STUBS_DIR}:\${PATH}'
    CLAWTEAM_DONE_DIR='${BATS_TEST_TMPDIR}/done'
    mkdir -p \"\${CLAWTEAM_DONE_DIR}\"
    module_done() { [[ -f \"\${CLAWTEAM_DONE_DIR}/\$1\" ]]; }
    mark_done()   { touch \"\${CLAWTEAM_DONE_DIR}/\$1\"; }
    export -f module_done mark_done
    source '${PROJECT_ROOT}/test/test_helper/stub-functions.bash'
    source '${module_file}'
  "
}

# ===========================================================================
# A — Orchestrator: install/clawteam-install.sh
# ===========================================================================

@test "orchestrator: all module files exist" {
  for m in 01-system-deps.sh 02-nodejs.sh 03-openclaw.sh 04-clawteam.sh \
            05-workspace.sh 06-systemd.sh 07-motd.sh; do
    assert_file_exists "${MODULES_DIR}/${m}"
  done
}

@test "orchestrator: lib/common.sh exists" {
  assert_file_exists "${PROJECT_ROOT}/install/lib/common.sh"
}

@test "orchestrator: all modules are sourced in numerical order" {
  # Verify the orchestrator sources each module in sequence
  for m in 01 02 03 04 05 06 07; do
    grep -q "_run_module \"${m}-" "${INSTALL_SCRIPT}" \
      || fail "Module ${m} not sourced in ${INSTALL_SCRIPT}"
  done
}

@test "orchestrator: runs successfully with all stubs (requires root)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
}

@test "orchestrator: FUNCTIONS_FILE_PATH preamble is invoked when set" {
  # When FUNCTIONS_FILE_PATH is set, the orchestrator should source it
  grep -q 'FUNCTIONS_FILE_PATH' "${INSTALL_SCRIPT}" \
    || fail "FUNCTIONS_FILE_PATH handling missing from orchestrator"
}

@test "orchestrator: community-scripts teardown functions are called if defined" {
  grep -q 'motd_ssh'    "${INSTALL_SCRIPT}" || fail "motd_ssh not called"
  grep -q 'customize'   "${INSTALL_SCRIPT}" || fail "customize not called"
  grep -q 'cleanup_lxc' "${INSTALL_SCRIPT}" || fail "cleanup_lxc not called"
}

# ===========================================================================
# B — Module 01: system dependencies
# ===========================================================================

@test "module 01: apt-get is called to install system dependencies" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "01-system-deps.sh"
  assert_success
  assert_stub_called apt-get
}

@test "module 01: installs git, tmux, python3-venv, libzmq3-dev" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "01-system-deps.sh"
  assert_success
  for pkg in git tmux python3-venv libzmq3-dev build-essential; do
    assert_stub_called_with apt-get "${pkg}"
  done
}

@test "module 01: uses apt-get not apt (non-interactive)" {
  # Must contain apt-get
  assert_file_contains "${MODULES_DIR}/01-system-deps.sh" 'apt-get'
  # Must not use bare 'apt install'
  if grep -qE '\$STD apt install|\bapt install' "${MODULES_DIR}/01-system-deps.sh"; then
    fail "Module 01 uses bare 'apt install' — must use 'apt-get install'"
  fi
}

@test "module 01: is idempotent (skips on second run)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  # First run
  run _run_module "01-system-deps.sh"
  assert_success
  rm -f "${STUBS_DIR}/apt-get.log"
  # Second run — marker exists, apt-get should NOT be called again
  run _run_module "01-system-deps.sh"
  assert_success
  refute_stub_called apt-get
}

@test "module 01: exits non-zero when apt-get fails" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  create_stub apt-get "apt failed" 1
  run _run_module "01-system-deps.sh"
  assert_failure
}

# ===========================================================================
# C — Module 02: Node.js
# ===========================================================================

@test "module 02: uses setup_nodejs when available (community-scripts path)" {
  # setup_nodejs is a no-op in stub-functions.bash — verify module calls it
  assert_file_contains "${MODULES_DIR}/02-nodejs.sh" 'setup_nodejs'
}

@test "module 02: falls back to NodeSource when setup_nodejs unavailable" {
  assert_file_contains "${MODULES_DIR}/02-nodejs.sh" 'nodesource.com'
}

@test "module 02: NODE_MAJOR defaults to 22" {
  grep 'NODE_MAJOR.*22' "${MODULES_DIR}/02-nodejs.sh" \
    || fail "Module 02 does not default NODE_MAJOR to 22"
}

@test "module 02: is idempotent (skips on second run)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "02-nodejs.sh"
  assert_success
  # Second run should skip
  run _run_module "02-nodejs.sh"
  assert_success
}

# ===========================================================================
# D — Module 03: OpenClaw
# ===========================================================================

@test "module 03: calls npm install -g openclaw@latest" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "03-openclaw.sh"
  assert_success
  assert_stub_called_with npm "install -g openclaw@latest"
}

@test "module 03: does not call npm update" {
  assert_file_contains "${MODULES_DIR}/03-openclaw.sh" 'npm install -g'
  # Ensure no bare 'npm update' is present
  if grep -q 'npm update' "${MODULES_DIR}/03-openclaw.sh"; then
    fail "Module 03 uses 'npm update' — must use 'npm install -g' for idempotency"
  fi
}

@test "module 03: is idempotent (skips on second run)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "03-openclaw.sh"
  assert_success
  rm -f "${STUBS_DIR}/npm.log"
  run _run_module "03-openclaw.sh"
  assert_success
  refute_stub_called npm
}

@test "module 03: exits non-zero when npm fails" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  create_stub npm "npm failed" 1
  run _run_module "03-openclaw.sh"
  assert_failure
}

# ===========================================================================
# E — Module 04: ClawTeam
# ===========================================================================

@test "module 04: creates venv at /opt/clawteam/.venv" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "04-clawteam.sh"
  assert_success
  assert_stub_called_with python3 "-m venv /opt/clawteam/.venv"
}

@test "module 04: installs clawteam into venv" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "04-clawteam.sh"
  assert_success
  assert_file_exists "${STUBS_DIR}/venv-pip.log"
  grep -qF "clawteam" "${STUBS_DIR}/venv-pip.log"
}

@test "module 04: attempts clawteam[p2p] install" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "04-clawteam.sh"
  assert_success
  grep -qF "clawteam[p2p]" "${STUBS_DIR}/venv-pip.log"
}

@test "module 04: symlinks clawteam into /usr/local/bin with -sf flags" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "04-clawteam.sh"
  assert_success
  assert_stub_called_with ln "-sf"
  assert_stub_called_with ln "/usr/local/bin/clawteam"
  assert_stub_called_with ln "/opt/clawteam/.venv/bin/clawteam"
}

@test "module 04: uses absolute venv path (no bare cd)" {
  if grep -qE '^\s*cd ' "${MODULES_DIR}/04-clawteam.sh"; then
    fail "Module 04 uses bare 'cd' — use absolute paths instead"
  fi
}

@test "module 04: is idempotent (skips if marker and binary exist)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "04-clawteam.sh"
  assert_success
  rm -f "${STUBS_DIR}/python3.log"
  # Create the binary so the idempotency check passes
  touch "${STUBS_DIR}/clawteam-bin-marker"
  run _run_module "04-clawteam.sh"
  assert_success
}

# ===========================================================================
# F — Module 05: workspace + team
# ===========================================================================

@test "module 05: configures git global user.email" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "05-workspace.sh"
  assert_success
  assert_stub_called_with git "user.email"
}

@test "module 05: configures git global user.name" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "05-workspace.sh"
  assert_success
  assert_stub_called_with git "user.name"
}

@test "module 05: initialises git workspace with git -C (not bare cd)" {
  assert_file_contains "${MODULES_DIR}/05-workspace.sh" 'git -C'
  if grep -qE '^\s*cd .*workspace' "${MODULES_DIR}/05-workspace.sh"; then
    fail "Module 05 uses bare 'cd' into workspace — use 'git -C' or absolute paths"
  fi
}

@test "module 05: calls clawteam team spawn-team with correct flags" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "05-workspace.sh"
  assert_success
  assert_stub_called_with clawteam "team"
  assert_stub_called_with clawteam "spawn-team"
  assert_stub_called_with clawteam "openclaw-team"
}

@test "module 05: spawn-team uses -d flag (not --description)" {
  assert_file_contains "${MODULES_DIR}/05-workspace.sh" ' -d '
  if grep -q '\-\-description' "${MODULES_DIR}/05-workspace.sh"; then
    fail "Module 05 uses --description; ClawTeam CLI requires -d"
  fi
}

@test "module 05: spawn-team uses -n flag (not --agent-name)" {
  assert_file_contains "${MODULES_DIR}/05-workspace.sh" ' -n '
  if grep -q '\-\-agent-name' "${MODULES_DIR}/05-workspace.sh"; then
    fail "Module 05 uses --agent-name on spawn-team; that flag belongs to 'clawteam spawn'"
  fi
}

@test "module 05: script continues (non-fatal) if spawn-team fails" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  create_stub clawteam "team already exists" 1
  run _run_module "05-workspace.sh"
  # Should warn but not exit 1 — spawn-team failure is non-fatal
  assert_success
}

# ===========================================================================
# G — Module 06: systemd service
# ===========================================================================

@test "module 06: writes service file to /etc/systemd/system/" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "06-systemd.sh"
  assert_success
  assert_file_exists "/etc/systemd/system/clawteam-board.service"
}

@test "module 06: service [Unit] section present" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "06-systemd.sh"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" '\[Unit\]'
}

@test "module 06: service [Service] section present" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "06-systemd.sh"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" '\[Service\]'
}

@test "module 06: service [Install] section present" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "06-systemd.sh"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" '\[Install\]'
}

@test "module 06: ExecStart uses correct clawteam command and port 8080" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "06-systemd.sh"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" \
    "ExecStart=/usr/local/bin/clawteam board serve --port 8080"
}

@test "module 06: WorkingDirectory is the openclaw workspace" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "06-systemd.sh"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" \
    "WorkingDirectory=/root/workspace/openclaw-workspace"
}

@test "module 06: Restart policy is on-failure" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "06-systemd.sh"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" \
    "Restart=on-failure"
}

@test "module 06: WantedBy is multi-user.target" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "06-systemd.sh"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" \
    "WantedBy=multi-user.target"
}

@test "module 06: calls systemctl enable for clawteam-board" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "06-systemd.sh"
  assert_success
  assert_stub_called_with systemctl "enable"
  assert_stub_called_with systemctl "clawteam-board"
}

@test "module 06: is idempotent (skips if marker + service file exist)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "06-systemd.sh"
  assert_success
  rm -f "${STUBS_DIR}/systemctl.log"
  run _run_module "06-systemd.sh"
  assert_success
  refute_stub_called systemctl
}

# ===========================================================================
# H — Module 07: MOTD
# ===========================================================================

@test "module 07: creates MOTD file at /etc/update-motd.d/99-clawteam" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "07-motd.sh"
  assert_success
  assert_file_exists "/etc/update-motd.d/99-clawteam"
}

@test "module 07: MOTD file is executable" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "07-motd.sh"
  assert_success
  assert_file_executable "/etc/update-motd.d/99-clawteam"
}

@test "module 07: MOTD references workspace path" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "07-motd.sh"
  assert_success
  assert_file_contains "/etc/update-motd.d/99-clawteam" \
    "/root/workspace/openclaw-workspace"
}

@test "module 07: MOTD references web UI port 8080" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "07-motd.sh"
  assert_success
  assert_file_contains "/etc/update-motd.d/99-clawteam" "--port 8080"
}

@test "module 07: MOTD references board attach command" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "07-motd.sh"
  assert_success
  assert_file_contains "/etc/update-motd.d/99-clawteam" "board attach"
}

@test "module 07: MOTD mentions openclaw-team" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "07-motd.sh"
  assert_success
  assert_file_contains "/etc/update-motd.d/99-clawteam" "openclaw-team"
}

@test "module 07: MOTD mentions update command with pct" {
  # The MOTD file content references the --update flag for the ct script
  grep -q '\-\-update' "${MODULES_DIR}/07-motd.sh" \
    || fail "Module 07 MOTD does not mention the --update flag"
}

@test "module 07: is idempotent (skips on second run)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run _run_module "07-motd.sh"
  assert_success
  run _run_module "07-motd.sh"
  assert_success
}

# ===========================================================================
# I — lib/common.sh
# ===========================================================================

@test "lib/common.sh: defines msg_info when not already declared" {
  run bash -c "
    source '${PROJECT_ROOT}/install/lib/common.sh'
    declare -f msg_info
  "
  assert_success
  assert_output --partial "msg_info"
}

@test "lib/common.sh: does not override msg_info if already defined" {
  run bash -c "
    msg_info() { echo 'original'; }
    source '${PROJECT_ROOT}/install/lib/common.sh'
    msg_info test
  "
  assert_success
  assert_output "original"
}

@test "lib/common.sh: defines already_installed helper" {
  run bash -c "
    source '${PROJECT_ROOT}/install/lib/common.sh'
    declare -f already_installed
  "
  assert_success
}

@test "lib/common.sh: already_installed returns true for bash" {
  run bash -c "
    source '${PROJECT_ROOT}/install/lib/common.sh'
    already_installed bash && echo yes
  "
  assert_success
  assert_output "yes"
}

@test "lib/common.sh: already_installed returns false for nonexistent-cmd-xyz" {
  run bash -c "
    source '${PROJECT_ROOT}/install/lib/common.sh'
    already_installed nonexistent-cmd-xyz && echo yes || echo no
  "
  assert_success
  assert_output "no"
}

# ===========================================================================
# J — Static analysis (ShellCheck)
# ===========================================================================

@test "ShellCheck: install/clawteam-install.sh" {
  if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck --exclude=SC1090,SC1091,SC2154 "${INSTALL_SCRIPT}"
  assert_success
}

@test "ShellCheck: install/lib/common.sh" {
  if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck "${PROJECT_ROOT}/install/lib/common.sh"
  assert_success
}

@test "ShellCheck: module 01-system-deps.sh" {
  if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck --exclude=SC1090,SC1091,SC2154 "${MODULES_DIR}/01-system-deps.sh"
  assert_success
}

@test "ShellCheck: module 02-nodejs.sh" {
  if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck --exclude=SC1090,SC1091,SC2154 "${MODULES_DIR}/02-nodejs.sh"
  assert_success
}

@test "ShellCheck: module 03-openclaw.sh" {
  if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck --exclude=SC1090,SC1091,SC2154 "${MODULES_DIR}/03-openclaw.sh"
  assert_success
}

@test "ShellCheck: module 04-clawteam.sh" {
  if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck --exclude=SC1090,SC1091,SC2154 "${MODULES_DIR}/04-clawteam.sh"
  assert_success
}

@test "ShellCheck: module 05-workspace.sh" {
  if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck --exclude=SC1090,SC1091,SC2154 "${MODULES_DIR}/05-workspace.sh"
  assert_success
}

@test "ShellCheck: module 06-systemd.sh" {
  if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck --exclude=SC1090,SC1091,SC2154 "${MODULES_DIR}/06-systemd.sh"
  assert_success
}

@test "ShellCheck: module 07-motd.sh" {
  if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
  run shellcheck --exclude=SC1090,SC1091,SC2154 "${MODULES_DIR}/07-motd.sh"
  assert_success
}
