#!/usr/bin/env bats
# test/ct/clawteam.bats
#
# TDD tests for ct/clawteam.sh (the Proxmox host-side LXC creation script)
#
# Tests cover:
#   Group A — Variable defaults
#   Group B — update_script() / --update path
#   Group C — _pct_standalone() pct/pveam integration
#   Group D — Script structure invariants
#   Group E — Static analysis (ShellCheck)
#
# Run:
#   ./test/bats/bin/bats test/ct/clawteam.bats

bats_require_minimum_version 1.5.0

setup() {
  load "$(dirname "$BATS_TEST_FILENAME")/../test_helper/common-setup.bash"
  _common_setup
  HOST_SCRIPT="${PROJECT_ROOT}/ct/clawteam.sh"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: extract the var_* defaults from the host script in a subshell
# ─────────────────────────────────────────────────────────────────────────────
_get_var() {
  local varname="$1"
  bash -c "
    $(grep -E '^(APP=|var_[a-z_]+|CT_[A-Z_]+=)' "${HOST_SCRIPT}" | head -30)
    echo \"\${${varname}}\"
  "
}

# ===========================================================================
# A — Variable defaults
# ===========================================================================

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

@test "CT_HOSTNAME defaults to clawteam" {
  run _get_var "CT_HOSTNAME"
  assert_success
  assert_output "clawteam"
}

@test "CT_BRIDGE defaults to vmbr0" {
  run _get_var "CT_BRIDGE"
  assert_success
  assert_output "vmbr0"
}

@test "CT_ONBOOT defaults to 1 (autostart)" {
  run _get_var "CT_ONBOOT"
  assert_success
  assert_output "1"
}

@test "STANDALONE defaults to 0 (community-scripts mode)" {
  # STANDALONE uses :- default — verify the default value in the file
  grep -q 'STANDALONE="${STANDALONE:-0}"' "${HOST_SCRIPT}" \
    || fail "STANDALONE default of 0 not found in ${HOST_SCRIPT}"
}

@test "var_cpu can be overridden via environment" {
  run bash -c "var_cpu=8; $(grep '^var_cpu=' "${HOST_SCRIPT}"); echo \${var_cpu}"
  assert_success
  assert_output "8"
}

@test "CT_RAM can be overridden via environment" {
  run bash -c "CT_RAM=8192; $(grep '^CT_RAM=' "${HOST_SCRIPT}"); echo \${CT_RAM}"
  assert_success
  assert_output "8192"
}

# ===========================================================================
# B — update_script() and --update path
# ===========================================================================

@test "--update flag exits non-zero when container has no ClawTeam" {
  # Create pct stub that reports the container as existing
  create_stub pct "running" 0
  # But test -d /opt/clawteam will fail (pct exec returns 1)
  cat >"${STUBS_DIR}/pct" <<PCTSTUB
#!/usr/bin/env bash
echo "pct \$*" >> "${STUBS_DIR}/pct.log"
# pct status -> success (container exists)
if [[ "\$1" == "status" ]]; then exit 0; fi
# pct exec ... test -d -> fail (no installation)
if [[ "\$1" == "exec" ]]; then exit 1; fi
exit 0
PCTSTUB
  chmod +x "${STUBS_DIR}/pct"

  run bash "${HOST_SCRIPT}" --update 100
  assert_failure
}

@test "--update flag requires a vmid argument" {
  run bash "${HOST_SCRIPT}" --update
  assert_failure
  assert_output --partial "Usage"
}

@test "--update calls pip upgrade for clawteam (static)" {
  # Verify _pct_update issues a pip --upgrade command for clawteam
  grep -q 'pip install.*--upgrade.*clawteam\|pip.*upgrade.*clawteam' "${HOST_SCRIPT}" \
    || fail "_pct_update does not contain 'pip install --upgrade clawteam'"
}

@test "--update calls npm install -g not npm update (static)" {
  # Verify _pct_update uses npm install -g, not npm update
  grep -q 'npm install -g openclaw@latest' "${HOST_SCRIPT}" \
    || fail "_pct_update does not use 'npm install -g openclaw@latest'"
  if grep -qE '^\s*npm update' "${HOST_SCRIPT}"; then
    fail "Found bare 'npm update' in ${HOST_SCRIPT} — must use 'npm install -g'"
  fi
}

# ===========================================================================
# C — pct / pveam integration (_pct_standalone)
# ===========================================================================

@test "_pct_standalone: exits non-zero when pct is not available (static)" {
  # Verify the script contains a guard that fails when pct is not on PATH
  grep -q 'command -v pct' "${HOST_SCRIPT}" \
    || fail "_pct_standalone does not check for pct availability"
  grep -q 'pct not found' "${HOST_SCRIPT}" \
    || fail "_pct_standalone does not emit a 'pct not found' error message"
}

@test "_pct_standalone: calls pveam update when no template is cached (static)" {
  # Verify the script contains logic to call pveam update
  assert_file_contains "${HOST_SCRIPT}" 'pveam update'
}

@test "_pct_standalone: calls pveam download to fetch missing template (static)" {
  assert_file_contains "${HOST_SCRIPT}" 'pveam download'
}

@test "_pct_standalone: calls pct create with all required flags (static)" {
  for flag in hostname cores memory swap rootfs net0 unprivileged features onboot tags start; do
    grep -q "\-\-${flag}" "${HOST_SCRIPT}" \
      || fail "pct create is missing '--${flag}' in ${HOST_SCRIPT}"
  done
}

@test "_pct_standalone: uses pvesh to get next container ID" {
  assert_file_contains "${HOST_SCRIPT}" 'pvesh get /cluster/nextid'
}

@test "_pct_standalone: waits for container network (retries loop)" {
  assert_file_contains "${HOST_SCRIPT}" 'hostname -I'
  assert_file_contains "${HOST_SCRIPT}" 'retries'
}

@test "_pct_standalone: pct create includes --unprivileged flag" {
  assert_file_contains "${HOST_SCRIPT}" '\-\-unprivileged'
}

@test "_pct_standalone: pct create includes --features nesting=1" {
  assert_file_contains "${HOST_SCRIPT}" 'nesting=1'
}

@test "_pct_standalone: pct create includes --onboot flag" {
  assert_file_contains "${HOST_SCRIPT}" '\-\-onboot'
}

@test "_pct_run_install: uses pct push to copy install script" {
  assert_file_contains "${HOST_SCRIPT}" 'pct push'
}

@test "_pct_run_install: uses pct exec to run install script" {
  assert_file_contains "${HOST_SCRIPT}" 'pct exec'
}

@test "_pct_run_install: sets perms 0755 when pushing script" {
  assert_file_contains "${HOST_SCRIPT}" '0755'
}

# ===========================================================================
# D — Script structure invariants
# ===========================================================================

@test "host script has STANDALONE mode guard" {
  assert_file_contains "${HOST_SCRIPT}" 'STANDALONE'
}

@test "host script defines both _pct_standalone and _community_scripts_mode" {
  grep -q '^_pct_standalone()' "${HOST_SCRIPT}" \
    || fail "_pct_standalone() function not found"
  grep -q '^_community_scripts_mode()' "${HOST_SCRIPT}" \
    || fail "_community_scripts_mode() function not found"
}

@test "community-scripts mode calls variables before header_info" {
  local variables_line header_line
  variables_line=$(grep -n '^\s*variables$' "${HOST_SCRIPT}" | head -1 | cut -d: -f1)
  header_line=$(grep -n '^\s*header_info' "${HOST_SCRIPT}" | head -1 | cut -d: -f1)
  [[ -n "${variables_line}" ]] || fail "'variables' call not found"
  [[ -n "${header_line}" ]]   || fail "'header_info' call not found"
  [[ "${variables_line}" -lt "${header_line}" ]] \
    || fail "'variables' (line ${variables_line}) must precede 'header_info' (line ${header_line})"
}

@test "community-scripts mode calls start, build_container, description" {
  for fn in start build_container description; do
    grep -q "^\s*${fn}$" "${HOST_SCRIPT}" \
      || fail "'${fn}' call not found in community-scripts mode"
  done
}

@test "host script does not use bare 'npm update'" {
  if grep -qE '^\s*npm update' "${HOST_SCRIPT}"; then
    fail "Found 'npm update' — use 'npm install -g openclaw@latest'"
  fi
}

@test "host script guards \${IP} behind non-empty check" {
  if grep -qE 'echo.*\$\{IP\}' "${HOST_SCRIPT}"; then
    grep -qE '\[\[.*\$\{?IP' "${HOST_SCRIPT}" \
      || fail "Unguarded \${IP} in echo — wrap in [[ -n \"\${IP:-}\" ]]"
  fi
}

@test "host script uses INSTALL_SCRIPT_URL for remote install" {
  assert_file_contains "${HOST_SCRIPT}" 'INSTALL_SCRIPT_URL'
}

# ===========================================================================
# E — Static analysis (ShellCheck)
# ===========================================================================

@test "host script passes ShellCheck" {
  if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
  # SC1090: dynamic source <(curl ...) — expected
  # SC2034: APP/var_* appear unused locally (consumed by sourced build.func)
  run shellcheck \
    --exclude=SC1090,SC2034 \
    "${HOST_SCRIPT}"
  assert_success
}
