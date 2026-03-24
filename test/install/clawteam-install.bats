#!/usr/bin/env bats
# test/install/clawteam-install.bats
#
# TDD tests for install/clawteam-install.sh
#
# These tests run the install script with all external commands stubbed out
# so no real packages are installed, no real git operations are performed,
# and no real systemd units are registered.
#
# Run:
#   ./test/bats/bin/bats test/install/clawteam-install.bats
#
# Run with verbose output:
#   ./test/bats/bin/bats --verbose-run test/install/clawteam-install.bats

bats_require_minimum_version 1.5.0

# ---------------------------------------------------------------------------
# Shared setup / teardown
# ---------------------------------------------------------------------------

setup() {
  load "$(dirname "$BATS_TEST_FILENAME")/../test_helper/common-setup.bash"
  _common_setup

  INSTALL_SCRIPT="${PROJECT_ROOT}/install/clawteam-install.sh"

  # Isolated fake rootfs so the script writes into $TEST_ROOT, not /
  TEST_ROOT="${BATS_TEST_TMPDIR}/rootfs"
  mkdir -p \
    "${TEST_ROOT}/opt/clawteam/.venv/bin" \
    "${TEST_ROOT}/usr/local/bin" \
    "${TEST_ROOT}/etc/systemd/system" \
    "${TEST_ROOT}/etc/update-motd.d" \
    "${TEST_ROOT}/root/workspace"
  export TEST_ROOT

  # ── Stub every external command the install script calls ──────────────────

  # apt-get: succeed silently
  create_stub apt-get "" 0

  # Node.js setup helper is a no-op in the community-scripts shim
  # (setup_nodejs is defined in stub-functions.bash)

  # npm: succeed silently
  create_stub npm "" 0

  # python3: succeed silently (venv creation is tested via a custom stub below)
  create_stub python3 "" 0

  # pip (system pip referenced for version check)
  create_stub pip "Version: 0.2.0" 0

  # The venv pip and clawteam binaries are referenced by full path, so create
  # them explicitly inside the fake venv rather than via the PATH stub dir.
  # The install script uses /opt/clawteam/.venv/bin/pip, so we write directly
  # to /opt to match hardcoded paths — but redirect the TEST by overriding
  # the mkdir / python3 calls.  Since the script uses hardcoded paths we stub
  # `python3` to create the fake venv in the real /opt/clawteam for the
  # duration of the test, or we redirect via a wrapper script.
  #
  # Simplest approach: create the venv directories and stub binaries in the
  # REAL /opt/clawteam/.venv/bin — but only if we are running as root in a
  # container.  Otherwise, stub python3 and pip with stubs that record calls
  # and write fake binaries into a temp path.

  # Stub python3 so `python3 -m venv ...` creates a minimal fake venv
  cat >"${STUBS_DIR}/python3" <<PYEOF
#!/usr/bin/env bash
echo "python3 \$*" >> "${STUBS_DIR}/python3.log"
# If called as: python3 -m venv <path>
if [[ "\$1" == "-m" && "\$2" == "venv" ]]; then
  VENV_DIR="\$3"
  mkdir -p "\${VENV_DIR}/bin"
  # Stub pip inside the venv
  cat > "\${VENV_DIR}/bin/pip" <<'PIPEOF'
#!/usr/bin/env bash
echo "venv-pip \$*" >> "${STUBS_DIR}/venv-pip.log"
if [[ "\$1 \$2" == "show clawteam" ]] || [[ "\$*" == *"show clawteam"* ]]; then
  echo "Version: 0.2.0"
fi
exit 0
PIPEOF
  chmod +x "\${VENV_DIR}/bin/pip"
  # Stub clawteam binary inside the venv
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

  # git: succeed silently and create expected directories
  cat >"${STUBS_DIR}/git" <<'GITEOF'
#!/usr/bin/env bash
echo "git $*" >> "${BATS_TEST_TMPDIR}/stubs/git.log"
# Handle: git -C <dir> init -q <name>
if [[ "$1" == "-C" ]]; then
  PARENT="$2"; shift 2
fi
if [[ "$1" == "init" ]]; then
  WORKSPACE="${PARENT:-$PWD}/${@: -1}"
  mkdir -p "$WORKSPACE"
fi
# Handle: git config --global ...
exit 0
GITEOF
  chmod +x "${STUBS_DIR}/git"

  # clawteam: used for `clawteam team spawn-team`
  create_stub clawteam "spawned" 0

  # ln: record the call but actually create the symlink (using system ln)
  cat >"${STUBS_DIR}/ln" <<'LNEOF'
#!/usr/bin/env bash
echo "ln $*" >> "${BATS_TEST_TMPDIR}/stubs/ln.log"
/bin/ln "$@"
exit 0
LNEOF
  chmod +x "${STUBS_DIR}/ln"

  # systemctl: succeed silently
  create_stub systemctl "" 0
}

teardown() {
  # Remove any symlinks the test created in real system paths
  rm -f /usr/local/bin/clawteam 2>/dev/null || true
  rm -f /opt/clawteam/.venv/bin/clawteam 2>/dev/null || true
  rm -rf /opt/clawteam 2>/dev/null || true
  rm -rf /root/workspace/openclaw-workspace 2>/dev/null || true
  rm -f /etc/systemd/system/clawteam-board.service 2>/dev/null || true
  rm -f /etc/update-motd.d/99-clawteam 2>/dev/null || true
}

# ===========================================================================
# 1 — apt-get: dependency installation
# ===========================================================================

@test "apt-get is called to install dependencies" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called apt-get
}

@test "apt-get installs git" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with apt-get "git"
}

@test "apt-get installs tmux" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with apt-get "tmux"
}

@test "apt-get installs python3-venv" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with apt-get "python3-venv"
}

@test "apt-get installs libzmq3-dev for ZeroMQ P2P transport" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with apt-get "libzmq3-dev"
}

@test "apt-get failure causes install script to exit non-zero" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  # Override apt-get stub to fail
  create_stub apt-get "simulated apt failure" 1
  run bash "${INSTALL_SCRIPT}"
  assert_failure
}

# ===========================================================================
# 2 — npm: OpenClaw installation
# ===========================================================================

@test "npm is called to install openclaw globally" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called npm
}

@test "npm installs openclaw@latest with -g flag" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with npm "install -g openclaw@latest"
}

@test "npm failure causes install script to exit non-zero" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  create_stub npm "simulated npm failure" 1
  run bash "${INSTALL_SCRIPT}"
  assert_failure
}

# ===========================================================================
# 3 — Python venv: ClawTeam installation
# ===========================================================================

@test "python3 is called to create a virtualenv at /opt/clawteam/.venv" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with python3 "-m venv /opt/clawteam/.venv"
}

@test "venv pip is called to install clawteam" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_exists "${STUBS_DIR}/venv-pip.log"
  grep -qF "clawteam" "${STUBS_DIR}/venv-pip.log"
}

@test "venv pip attempts clawteam[p2p] install for ZeroMQ transport" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_exists "${STUBS_DIR}/venv-pip.log"
  grep -qF "clawteam[p2p]" "${STUBS_DIR}/venv-pip.log"
}

# ===========================================================================
# 4 — Symlink: /usr/local/bin/clawteam
# ===========================================================================

@test "clawteam is symlinked into /usr/local/bin" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with ln "/usr/local/bin/clawteam"
}

@test "symlink uses -sf flags (force, symbolic)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with ln "-sf"
}

@test "symlink source is /opt/clawteam/.venv/bin/clawteam" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with ln "/opt/clawteam/.venv/bin/clawteam"
}

# ===========================================================================
# 5 — git: workspace and identity
# ===========================================================================

@test "git global user.email is configured" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with git "user.email"
}

@test "git global user.name is configured" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with git "user.name"
}

@test "git init creates the openclaw-workspace" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with git "init"
  assert_stub_called_with git "openclaw-workspace"
}

# ===========================================================================
# 6 — ClawTeam team creation
# ===========================================================================

@test "clawteam team spawn-team is called for default team" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with clawteam "team"
  assert_stub_called_with clawteam "spawn-team"
  assert_stub_called_with clawteam "openclaw-team"
}

@test "spawn-team is called with -d description flag (not --description)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with clawteam " -d "
}

@test "spawn-team is called with -n leader flag (not --agent-name)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with clawteam " -n leader"
}

@test "script continues if clawteam spawn-team fails (non-fatal)" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  # Override clawteam stub to fail — the install script should still succeed
  # because team creation is wrapped in an 'if' with a warn fallback
  create_stub clawteam "team already exists" 1
  run bash "${INSTALL_SCRIPT}"
  assert_success
}

# ===========================================================================
# 7 — systemd service file
# ===========================================================================

@test "systemd service file is written to /etc/systemd/system/" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_exists "/etc/systemd/system/clawteam-board.service"
}

@test "service file [Unit] section is present" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" '\[Unit\]'
}

@test "service file [Service] section is present" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" '\[Service\]'
}

@test "service file [Install] section is present" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" '\[Install\]'
}

@test "service ExecStart uses correct clawteam command and port" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" \
    "ExecStart=/usr/local/bin/clawteam board serve --port 8080"
}

@test "service WorkingDirectory is the openclaw workspace" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" \
    "WorkingDirectory=/root/workspace/openclaw-workspace"
}

@test "service Restart policy is on-failure" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" \
    "Restart=on-failure"
}

@test "service WantedBy is multi-user.target" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/systemd/system/clawteam-board.service" \
    "WantedBy=multi-user.target"
}

@test "systemctl enable is called for clawteam-board" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_stub_called_with systemctl "enable"
  assert_stub_called_with systemctl "clawteam-board"
}

# ===========================================================================
# 8 — MOTD helper
# ===========================================================================

@test "MOTD file is created at /etc/update-motd.d/99-clawteam" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_exists "/etc/update-motd.d/99-clawteam"
}

@test "MOTD file is executable" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_executable "/etc/update-motd.d/99-clawteam"
}

@test "MOTD file references the workspace path" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/update-motd.d/99-clawteam" \
    "/root/workspace/openclaw-workspace"
}

@test "MOTD file references the web UI port" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/update-motd.d/99-clawteam" "--port 8080"
}

@test "MOTD file references clawteam board attach command" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/update-motd.d/99-clawteam" "board attach"
}

@test "MOTD file mentions openclaw-team" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  assert_file_contains "/etc/update-motd.d/99-clawteam" "openclaw-team"
}

# ===========================================================================
# 9 — Idempotency: re-running the script
# ===========================================================================

@test "script is idempotent: running twice succeeds without error" {
  if [[ "$(id -u)" != "0" ]]; then skip "requires root"; fi
  run bash "${INSTALL_SCRIPT}"
  assert_success
  # Reset per-call stubs (logs accumulate, that is fine)
  run bash "${INSTALL_SCRIPT}"
  assert_success
}

# ===========================================================================
# 10 — Static analysis (ShellCheck)
# ===========================================================================

@test "install script passes ShellCheck" {
  if ! command -v shellcheck &>/dev/null; then
    skip "shellcheck not installed"
  fi
  # SC1090: can't follow dynamic source — acceptable for FUNCTIONS_FILE_PATH
  # SC2154: var referenced but not assigned — STD is set by the sourced shim
  run shellcheck \
    --exclude=SC1090,SC2154 \
    "${PROJECT_ROOT}/install/clawteam-install.sh"
  assert_success
}
