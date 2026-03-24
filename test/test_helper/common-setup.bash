#!/usr/bin/env bash
# test/test_helper/common-setup.bash
#
# Sourced by every .bats file's setup() function.
# Loads all bats helper libraries and anchors PROJECT_ROOT.

_common_setup() {
  # Anchor to the project root from the test file's location
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." >/dev/null 2>&1 && pwd)"
  export PROJECT_ROOT

  # Load bats helper libraries
  load "${PROJECT_ROOT}/test/test_helper/bats-support/load"
  load "${PROJECT_ROOT}/test/test_helper/bats-assert/load"
  load "${PROJECT_ROOT}/test/test_helper/bats-file/load"

  # Stub directory — prepend to PATH so our stubs shadow real commands
  STUBS_DIR="${BATS_TEST_TMPDIR}/stubs"
  mkdir -p "${STUBS_DIR}"
  export PATH="${STUBS_DIR}:${PATH}"

  # Point FUNCTIONS_FILE_PATH at the local stub so the install script's
  #   source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
  # resolves to our no-op shim instead of the real community-scripts URL.
  export FUNCTIONS_FILE_PATH
  FUNCTIONS_FILE_PATH="$(cat "${PROJECT_ROOT}/test/test_helper/stub-functions.bash")"
}

# ── Stub helpers ──────────────────────────────────────────────────────────────

# create_stub CMD [STDOUT [EXIT_CODE]]
#   Writes a tiny executable into $STUBS_DIR that:
#     • logs every invocation to ${STUBS_DIR}/${cmd}.log
#     • prints STDOUT (optional)
#     • exits with EXIT_CODE (default 0)
create_stub() {
  local cmd="$1"
  local stdout="${2:-}"
  local exit_code="${3:-0}"
  cat >"${STUBS_DIR}/${cmd}" <<STUBEOF
#!/usr/bin/env bash
# Auto-generated stub: ${cmd}
echo "${cmd} \$*" >> "${STUBS_DIR}/${cmd}.log"
${stdout:+printf '%s\n' "${stdout}"}
exit ${exit_code}
STUBEOF
  chmod +x "${STUBS_DIR}/${cmd}"
}

# assert_stub_called CMD
#   Fails if CMD was never invoked.
assert_stub_called() {
  local cmd="$1"
  assert_file_exists "${STUBS_DIR}/${cmd}.log"
}

# assert_stub_called_with CMD PATTERN
#   Fails if no invocation of CMD contained PATTERN (grep -qF).
assert_stub_called_with() {
  local cmd="$1"
  local pattern="$2"
  assert_file_exists "${STUBS_DIR}/${cmd}.log"
  grep -qF "${pattern}" "${STUBS_DIR}/${cmd}.log" \
    || fail "Expected stub '${cmd}' to be called with '${pattern}', but it was not.\nActual calls:\n$(cat "${STUBS_DIR}/${cmd}.log" 2>/dev/null || echo '<no log>')"
}

# refute_stub_called CMD
#   Fails if CMD WAS invoked (useful for negative assertions).
refute_stub_called() {
  local cmd="$1"
  if [[ -f "${STUBS_DIR}/${cmd}.log" ]]; then
    fail "Expected stub '${cmd}' NOT to be called, but it was.\nActual calls:\n$(cat "${STUBS_DIR}/${cmd}.log")"
  fi
}

# refute_stub_called_with CMD PATTERN
#   Fails if any invocation of CMD contained PATTERN.
refute_stub_called_with() {
  local cmd="$1"
  local pattern="$2"
  if [[ -f "${STUBS_DIR}/${cmd}.log" ]] && grep -qF "${pattern}" "${STUBS_DIR}/${cmd}.log"; then
    fail "Expected stub '${cmd}' NOT to be called with '${pattern}', but it was.\nActual calls:\n$(cat "${STUBS_DIR}/${cmd}.log")"
  fi
}
