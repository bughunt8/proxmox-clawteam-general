#!/usr/bin/env bats
# test/ct/clawteam.bats
#
# TDD tests for ct/clawteam.sh (the Proxmox host-side LXC creation script)
#
# Because the host script sources a remote build.func URL, these tests focus
# on the logic that IS testable in isolation:
#   • Variable defaults are correctly declared
#   • update_script() behaves correctly
#   • ShellCheck passes
#
# Full end-to-end container creation requires a live Proxmox environment and
# is intentionally out of scope for unit tests.
#
# Run:
#   ./test/bats/bin/bats test/ct/clawteam.bats

bats_require_minimum_version 1.5.0

# ---------------------------------------------------------------------------
# Shared setup
# ---------------------------------------------------------------------------

setup() {
  load "$(dirname "$BATS_TEST_FILENAME")/../test_helper/common-setup.bash"
  _common_setup

  HOST_SCRIPT="${PROJECT_ROOT}/ct/clawteam.sh"
}

# ===========================================================================
# 1 — Variable defaults
#     Source only the variable declarations by extracting them with bash -c
#     in a subshell so we can inspect values without running the full script.
# ===========================================================================

# Helper: source just the var_* lines from the host script in a subshell
# and print the value of a named variable.
_get_var() {
  local varname="$1"
  bash -c "
    $(grep -E '^(APP=|var_[a-z_]+)' "${HOST_SCRIPT}")
    echo \"\${${varname}}\"
  "
}

@test "APP is set to ClawTeam" {
  run _get_var "APP"
  assert_success
  assert_output "ClawTeam"
}

@test "default CPU count is 4" {
  run _get_var "var_cpu"
  assert_success
  assert_output "4"
}

@test "default RAM is 4096 MB" {
  run _get_var "var_ram"
  assert_success
  assert_output "4096"
}

@test "default disk is 10 GB" {
  run _get_var "var_disk"
  assert_success
  assert_output "10"
}

@test "default OS is debian" {
  run _get_var "var_os"
  assert_success
  assert_output "debian"
}

@test "default OS version is 13 (Debian Trixie)" {
  run _get_var "var_version"
  assert_success
  assert_output "13"
}

@test "container is unprivileged by default" {
  run _get_var "var_unprivileged"
  assert_success
  assert_output "1"
}

@test "default tags include 'ai'" {
  result="$(_get_var "var_tags")"
  [[ "${result}" == *"ai"* ]] || fail "var_tags '${result}' does not contain 'ai'"
}

@test "default tags include 'clawteam'" {
  result="$(_get_var "var_tags")"
  [[ "${result}" == *"clawteam"* ]] || fail "var_tags '${result}' does not contain 'clawteam'"
}

@test "var_cpu can be overridden via environment" {
  run bash -c "var_cpu=8; $(grep '^var_cpu=' "${HOST_SCRIPT}"); echo \${var_cpu}"
  assert_success
  assert_output "8"
}

# ===========================================================================
# 2 — update_script() function
#     Extract and source the function definition in isolation, then invoke it
#     with mocked dependencies.
# ===========================================================================

# Extract just the update_script function body from the host script
_source_update_script() {
  # Source the stub-functions shim (provides msg_info, msg_ok, msg_error, etc.)
  # then source the host script in a mode where it will NOT execute start/build.
  # We do this by redefining the tail functions as no-ops before sourcing.
  # The 'source <(curl ...)' on line 2 must be neutralised: we provide a local
  # override of 'source' via a wrapper script.
  local tmpscript="${BATS_TEST_TMPDIR}/update-test.sh"
  cat >"${tmpscript}" <<'WRAPPER'
#!/usr/bin/env bash
# Shim that replaces the first 'source <(curl ...)' with a no-op
FUNCTIONS_FILE_PATH_INJECTED="PLACEHOLDER_REPLACED_BY_SETUP"
source_orig="$(command -v source 2>/dev/null || true)"

# Prevent the remote source line from executing by redefining curl to cat /dev/null
curl() { cat /dev/null; }
export -f curl

# Load shim functions instead
WRAPPER
  echo "${FUNCTIONS_FILE_PATH}" >>"${tmpscript}"
  echo "" >>"${tmpscript}"
  # Append the update_script function from the host script
  awk '/^function update_script/,/^}/' "${HOST_SCRIPT}" >>"${tmpscript}"
  echo "" >>"${tmpscript}"
  echo "update_script" >>"${tmpscript}"
  bash "${tmpscript}"
}

@test "update_script fails with error when /opt/clawteam is missing" {
  # Make sure /opt/clawteam does not exist in the test environment
  rm -rf /opt/clawteam 2>/dev/null || true

  # Build a minimal script that defines update_script with shim functions
  # and invokes it
  local tmpscript="${BATS_TEST_TMPDIR}/update-no-install.sh"
  cat >"${tmpscript}" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
$(cat "${PROJECT_ROOT}/test/test_helper/stub-functions.bash")
# Provide STD for npm stub
STD=""
$(awk '/^function update_script/,/^}/' "${HOST_SCRIPT}")
update_script
SCRIPT

  run bash "${tmpscript}"
  assert_failure
}

@test "update_script calls pip upgrade for clawteam when installed" {
  # Create a fake venv under the temp dir so no root is needed
  local fake_venv="${BATS_TEST_TMPDIR}/opt/clawteam/.venv"
  mkdir -p "${fake_venv}/bin"

  # Stub venv pip — records calls to a log
  local pip_log="${STUBS_DIR}/venv-pip-upgrade.log"
  cat >"${fake_venv}/bin/pip" <<VPIPEOF
#!/usr/bin/env bash
echo "venv-pip \$*" >> "${pip_log}"
exit 0
VPIPEOF
  chmod +x "${fake_venv}/bin/pip"

  create_stub npm "" 0

  # Rewrite update_script's hardcoded /opt/clawteam path via sed so it uses
  # the temp venv and the temp /opt check
  local tmpscript="${BATS_TEST_TMPDIR}/update-ok.sh"
  {
    echo "#!/usr/bin/env bash"
    cat "${PROJECT_ROOT}/test/test_helper/stub-functions.bash"
    echo "STD=\"\""
    echo "export PATH=\"${STUBS_DIR}:\${PATH}\""
    # Extract update_script, redirect hardcoded paths to temp dirs
    awk '/^function update_script/,/^}/' "${HOST_SCRIPT}" \
      | sed "s|/opt/clawteam|${BATS_TEST_TMPDIR}/opt/clawteam|g"
    echo "update_script"
  } >"${tmpscript}"

  run bash "${tmpscript}"
  assert_success
  # Verify venv pip was called with --upgrade clawteam
  assert_file_exists "${pip_log}"
  grep -qF "upgrade" "${pip_log}"
}

@test "update_script calls npm install -g openclaw@latest (not npm update)" {
  # Create a fake venv under temp dir so no root is needed
  local fake_venv="${BATS_TEST_TMPDIR}/opt/clawteam/.venv"
  mkdir -p "${fake_venv}/bin"
  cat >"${fake_venv}/bin/pip" <<'VPIPEOF'
#!/usr/bin/env bash
exit 0
VPIPEOF
  chmod +x "${fake_venv}/bin/pip"

  create_stub npm "" 0

  local tmpscript="${BATS_TEST_TMPDIR}/update-npm.sh"
  {
    echo "#!/usr/bin/env bash"
    cat "${PROJECT_ROOT}/test/test_helper/stub-functions.bash"
    echo "STD=\"\""
    echo "export PATH=\"${STUBS_DIR}:\${PATH}\""
    awk '/^function update_script/,/^}/' "${HOST_SCRIPT}" \
      | sed "s|/opt/clawteam|${BATS_TEST_TMPDIR}/opt/clawteam|g"
    echo "update_script"
  } >"${tmpscript}"

  run bash "${tmpscript}"
  assert_success
  assert_stub_called_with npm "install -g openclaw@latest"
  refute_stub_called_with npm "update"
}

# ===========================================================================
# 3 — Static analysis (ShellCheck)
# ===========================================================================

@test "host script passes ShellCheck" {
  if ! command -v shellcheck &>/dev/null; then
    skip "shellcheck not installed"
  fi
  # SC1090: can't follow dynamic source <(curl ...) — expected
  # SC2034: APP/var_* appear unused inside the file (used by sourced build.func)
  run shellcheck \
    --exclude=SC1090,SC2034 \
    "${HOST_SCRIPT}"
  assert_success
}

# ===========================================================================
# 4 — Script structure: required calls in correct order
# ===========================================================================

@test "host script calls variables before header_info" {
  # In the source file, 'variables' must appear before 'header_info'
  local variables_line header_line
  variables_line=$(grep -n '^variables$' "${HOST_SCRIPT}" | head -1 | cut -d: -f1)
  header_line=$(grep -n '^header_info' "${HOST_SCRIPT}" | head -1 | cut -d: -f1)
  [[ -n "${variables_line}" ]] || fail "'variables' call not found in ${HOST_SCRIPT}"
  [[ -n "${header_line}" ]]   || fail "'header_info' call not found in ${HOST_SCRIPT}"
  [[ "${variables_line}" -lt "${header_line}" ]] \
    || fail "'variables' (line ${variables_line}) must precede 'header_info' (line ${header_line})"
}

@test "host script calls start, build_container, description in order" {
  local start_line build_line desc_line
  start_line=$(grep -n '^start$' "${HOST_SCRIPT}" | head -1 | cut -d: -f1)
  build_line=$(grep -n '^build_container$' "${HOST_SCRIPT}" | head -1 | cut -d: -f1)
  desc_line=$(grep -n '^description$' "${HOST_SCRIPT}" | head -1 | cut -d: -f1)
  [[ -n "${start_line}" ]] || fail "'start' call not found"
  [[ -n "${build_line}" ]] || fail "'build_container' call not found"
  [[ -n "${desc_line}" ]]  || fail "'description' call not found"
  [[ "${start_line}" -lt "${build_line}" ]] \
    || fail "'start' must precede 'build_container'"
  [[ "${build_line}" -lt "${desc_line}" ]] \
    || fail "'build_container' must precede 'description'"
}

@test "host script does not use bare 'npm update' for openclaw" {
  # update_script must use 'npm install -g' not 'npm update' to ensure the
  # latest version is always fetched
  if grep -qE '^[[:space:]]*npm update' "${HOST_SCRIPT}"; then
    fail "Found 'npm update' in ${HOST_SCRIPT}; use 'npm install -g openclaw@latest' instead"
  fi
}

@test "host script guards IP echo behind non-empty IP check" {
  # Bare 'echo .../\${IP}:8080' without a guard would silently produce a
  # broken URL if IP is unset.  Confirm there is a guard.
  if grep -qE 'echo.*\$\{IP\}' "${HOST_SCRIPT}"; then
    if ! grep -qE '\[\[.*\$\{?IP\}?.*\]\]' "${HOST_SCRIPT}"; then
      fail "Unguarded \${IP} interpolation found in echo statement in ${HOST_SCRIPT}"
    fi
  fi
}
