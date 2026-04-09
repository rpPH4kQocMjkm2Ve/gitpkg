#!/usr/bin/env bash
# tests/test_harness.sh
#
# Shared test harness for gitpkg unit tests.
# Sourced by individual test files — NOT run directly.
#
# Provides:
#   - Assertion functions (ok, fail)
#   - Section headers
#   - Temporary TMPDIR_TEST with EXIT cleanup
#   - PROJECT_ROOT and SCRIPT_DIR variables
#   - Sources lib/common.sh and lib/sandbox.sh with _GITPKG_NO_INIT=1

set -uo pipefail
# Note: no -e. Tests must continue running when assertions fail
# so failures can be counted and reported by summary().

PASS=0
FAIL=0
TESTS=0

ok()   { PASS=$((PASS + 1)); TESTS=$((TESTS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); TESTS=$((TESTS + 1)); echo "  ✗ $1"; }

section() { echo ""; echo "── $1 ──"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source libraries for unit testing; skip auto-init (no config, no trap, no lock)
_GITPKG_NO_INIT=1
# shellcheck source=../lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=../lib/sandbox.sh
source "${PROJECT_ROOT}/lib/sandbox.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

MOCK_BIN="${TMPDIR_TEST}/mock_bin"
mkdir -p "$MOCK_BIN"

ORIG_PATH="$PATH"

# Write a mock script into an arbitrary directory.
# Does NOT track calls (gitpkg unit tests don't need call tracking).
make_mock_in() {
    local dir="$1" name="$2"; shift 2
    local body="${*:-exit 0}"
    mkdir -p "$dir"
    cat > "${dir}/${name}" <<ENDSCRIPT
#!/bin/bash
${body}
ENDSCRIPT
    chmod +x "${dir}/${name}"
}

# ── Summary ──────────────────────────────────────────────────

summary() {
    local name="${0##*/}"
    echo ""
    echo "════════════════════════════════════"
    echo " ${name}: ${PASS} passed, ${FAIL} failed (total: ${TESTS})"
    echo "════════════════════════════════════"
    [[ $FAIL -ne 0 ]] && exit 1
    exit 0
}
