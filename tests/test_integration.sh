#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════
# gitpkg integration tests
# ═══════════════════════════════════════════════════════════
# Exercises the full lifecycle: install → update → remove.
# Catches variable-scope regressions such as the workdir/srcdir
# bug in _update_standalone_package (line 494).
#
# Requirements: root, bwrap, git, make
# Usage:        sudo bash tests/test_integration.sh

# ── Preflight ──────────────────────────────────────────────

[[ $EUID -eq 0 ]] || { echo "SKIP: requires root"; exit 0; }
for dep in bwrap git make find sha256sum; do
    command -v "$dep" &>/dev/null || { echo "SKIP: ${dep} not found"; exit 0; }
done

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Bootstrap gitpkg from source tree if not installed ─────

_SELF_INSTALLED=0
_STUB_INSTALLED=0

if ! command -v gitpkg &>/dev/null; then
    printf ':: Installing gitpkg from source tree...\n'
    install -Dm755 "${SCRIPT_DIR}/gitpkg"         /usr/bin/gitpkg
    install -Dm644 "${SCRIPT_DIR}/lib/common.sh"  /usr/lib/gitpkg/common.sh
    install -Dm644 "${SCRIPT_DIR}/lib/sandbox.sh" /usr/lib/gitpkg/sandbox.sh
    install -Dm644 "${SCRIPT_DIR}/lib/package.sh" /usr/lib/gitpkg/package.sh
    if ! command -v verify-lib &>/dev/null; then
        cat > /usr/bin/verify-lib << 'VERIFYLIB'
#!/bin/sh
# gitpkg-test-stub
echo "$1"
VERIFYLIB
        chmod 755 /usr/bin/verify-lib
        _STUB_INSTALLED=1
    fi
    mkdir -p /etc/gitpkg /var/lib/gitpkg /var/cache/gitpkg
    _SELF_INSTALLED=1
fi

# ── Test state ─────────────────────────────────────────────

TMP=$(mktemp -d /tmp/gitpkg-inttest.XXXXXX)
PKG="gitpkg-inttest-${$}-${RANDOM}"
REMOTE="${TMP}/remote"
WORK="${TMP}/work"

cleanup() {
    set +e
    rm -rf "/var/lib/gitpkg/${PKG}"
    rm -rf "/var/cache/gitpkg/${PKG}"
    rm -f "/usr/bin/${PKG}"
    rm -f /var/lock/gitpkg.lock
    rm -rf "$TMP"
    if [[ $_SELF_INSTALLED -eq 1 ]]; then
        rm -f /usr/bin/gitpkg
        rm -rf /usr/lib/gitpkg
        [[ $_STUB_INSTALLED -eq 1 ]] && rm -f /usr/bin/verify-lib
    fi
}
trap cleanup EXIT

printf '\n════════════════════════════════════════════════\n'
printf ' gitpkg integration tests\n'
printf ' package: %s\n' "$PKG"
printf '════════════════════════════════════════════════\n'

# ── Helpers ────────────────────────────────────────────────

_commit() {
    GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
    GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test \
        git -C "$WORK" add -A &>/dev/null
    GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
    GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test \
        git -C "$WORK" commit -m "$1" &>/dev/null
}

# ── Create local bare remote + working clone ──────────────

git -c init.defaultBranch=main init --bare "$REMOTE" &>/dev/null
git clone "$REMOTE" "$WORK" &>/dev/null
BRANCH=main

# ── v1: Makefile + binary + depends ───────────────────────

printf 'PREFIX = /usr\ninstall:\n\tinstall -Dm755 mybin $(DESTDIR)$(PREFIX)/bin/%s\n' \
    "$PKG" > "${WORK}/Makefile"
printf '#!/bin/sh\necho v1\n' > "${WORK}/mybin"
chmod +x "${WORK}/mybin"
printf 'system:coreutils\n' > "${WORK}/depends"

_commit "v1"
git -C "$WORK" push origin "$BRANCH" &>/dev/null
V1=$(git -C "$WORK" rev-parse HEAD)

# ══════════════════════════════════════════════════════════
# Simulate an installed v1 package
# (mirrors what 'gitpkg install' leaves behind)
# ══════════════════════════════════════════════════════════

printf '\n── Setup: simulating installed v1 ─────────────\n'

git clone "$REMOTE" "/var/cache/gitpkg/${PKG}" &>/dev/null
mkdir -p "/var/lib/gitpkg/${PKG}"
printf '%s\n' "$V1" > "/var/lib/gitpkg/${PKG}/commit"
printf 'usr/bin/%s\n' "$PKG" > "/var/lib/gitpkg/${PKG}/files"
install -Dm755 "${WORK}/mybin" "/usr/bin/${PKG}"

[[ -f "/usr/bin/${PKG}" ]]          && ok "v1 binary deployed" || fail "v1 binary missing"
[[ "$("/usr/bin/${PKG}")" == "v1" ]] && ok "v1 outputs correctly" || fail "v1 output wrong"

# ══════════════════════════════════════════════════════════
# Test 1 — standalone update
#
# This is the primary regression test.  The bug was:
#   [[ -f "${workdir}/backup" ]]   # workdir: unbound variable
# Fixed to:
#   [[ -f "${srcdir}/backup" ]]
#
# We push v2 with updated depends + a new backup file
# and verify the update succeeds AND metadata is synced.
# ══════════════════════════════════════════════════════════

printf '\n── Test 1: standalone update ──────────────────\n'

printf '#!/bin/sh\necho v2\n' > "${WORK}/mybin"
printf 'system:coreutils\nsystem:findutils\n' > "${WORK}/depends"
printf '/etc/%s.conf\n' "$PKG" > "${WORK}/backup"

_commit "v2"
git -C "$WORK" push &>/dev/null
V2=$(git -C "$WORK" rev-parse HEAD)

if output=$(gitpkg update "$PKG" --nosig --skip-inspect --nodeps 2>&1); then
    ok "update exited 0"
else
    fail "update crashed (rc=$?): $(echo "$output" | tail -1)"
fi

stored=$(tr -cd 'a-f0-9' < "/var/lib/gitpkg/${PKG}/commit")
[[ "$stored" == "$V2" ]] \
    && ok "commit advanced to v2" \
    || fail "commit mismatch: want ${V2:0:12}, got ${stored:0:12}"

if [[ -f "/usr/bin/${PKG}" ]]; then
    out=$("/usr/bin/${PKG}" 2>&1 || true)
    [[ "$out" == "v2" ]] && ok "binary outputs v2" || fail "binary still v1: ${out}"
else
    fail "binary missing after update"
fi

# Metadata sync (the exact code path that was broken)
[[ -f "/var/lib/gitpkg/${PKG}/depends" ]] \
    && ok "depends synced to dbdir" \
    || fail "depends NOT synced — workdir bug"

if [[ -f "/var/lib/gitpkg/${PKG}/depends" ]]; then
    grep -q findutils "/var/lib/gitpkg/${PKG}/depends" \
        && ok "depends contains v2 entries" \
        || fail "depends has stale v1 content"
fi

[[ -f "/var/lib/gitpkg/${PKG}/backup" ]] \
    && ok "backup list synced to dbdir" \
    || fail "backup list NOT synced — workdir bug"

# ══════════════════════════════════════════════════════════
# Test 2 — update when already up to date
# ══════════════════════════════════════════════════════════

printf '\n── Test 2: update (already up to date) ────────\n'

output=$(gitpkg update "$PKG" --nosig --skip-inspect 2>&1)
echo "$output" | grep -qi "up to date" \
    && ok "reports up to date" \
    || fail "expected 'up to date': ${output}"

# ══════════════════════════════════════════════════════════
# Test 3 — dry-run update (nothing should change)
# ══════════════════════════════════════════════════════════

printf '\n── Test 3: update --dry-run ───────────────────\n'

printf '#!/bin/sh\necho v3\n' > "${WORK}/mybin"
_commit "v3"
git -C "$WORK" push &>/dev/null
V3=$(git -C "$WORK" rev-parse HEAD)

output=$(gitpkg update "$PKG" --nosig --skip-inspect --nodeps -n 2>&1)
echo "$output" | grep -qi "would update" \
    && ok "dry-run shows 'would update'" \
    || fail "dry-run message wrong: ${output}"

stored=$(tr -cd 'a-f0-9' < "/var/lib/gitpkg/${PKG}/commit")
[[ "$stored" == "$V2" ]] \
    && ok "commit unchanged after dry-run" \
    || fail "dry-run modified commit"

out=$("/usr/bin/${PKG}" 2>&1 || true)
[[ "$out" == "v2" ]] \
    && ok "binary unchanged after dry-run" \
    || fail "dry-run modified binary: ${out}"

# ══════════════════════════════════════════════════════════
# Test 4 — real update to v3
# ══════════════════════════════════════════════════════════

printf '\n── Test 4: real update to v3 ──────────────────\n'

if gitpkg update "$PKG" --nosig --skip-inspect --nodeps &>/dev/null; then
    ok "v3 update exited 0"
else
    fail "v3 update failed"
fi

if [[ -f "/usr/bin/${PKG}" ]]; then
    out=$("/usr/bin/${PKG}" 2>&1 || true)
    [[ "$out" == "v3" ]] && ok "binary outputs v3" || fail "binary not v3: ${out}"
else
    fail "binary missing after v3 update"
fi

# ══════════════════════════════════════════════════════════
# Test 5 — update with source cache missing (re-clone)
# ══════════════════════════════════════════════════════════

printf '\n── Test 5: update after srcdir deleted ────────\n'

rm -rf "/var/cache/gitpkg/${PKG}"

# Record the remote URL so gitpkg can re-clone
printf '%s\n' "file://${REMOTE}" > "/var/lib/gitpkg/${PKG}/urls"

printf '#!/bin/sh\necho v4\n' > "${WORK}/mybin"
_commit "v4"
git -C "$WORK" push &>/dev/null

if gitpkg update "$PKG" --nosig --skip-inspect --nodeps &>/dev/null; then
    ok "re-clone + update exited 0"
else
    fail "re-clone + update failed"
fi

if [[ -f "/usr/bin/${PKG}" ]]; then
    out=$("/usr/bin/${PKG}" 2>&1 || true)
    [[ "$out" == "v4" ]] && ok "binary outputs v4" || fail "binary not v4: ${out}"
else
    fail "binary missing after re-clone update"
fi

# ══════════════════════════════════════════════════════════
# Test 6 — remove
# ══════════════════════════════════════════════════════════

printf '\n── Test 6: remove ─────────────────────────────\n'

if gitpkg remove "$PKG" -y --nodeps &>/dev/null; then
    ok "remove exited 0"
else
    fail "remove failed"
fi

[[ ! -f "/usr/bin/${PKG}" ]]        && ok "binary removed"  || fail "binary still exists"
[[ ! -d "/var/lib/gitpkg/${PKG}" ]] && ok "db entry removed" || fail "db entry remains"

# ══════════════════════════════════════════════════════════
# Results
# ══════════════════════════════════════════════════════════

printf '\n════════════════════════════════════════════════\n'
printf ' Results: %d passed, %d failed\n' "$PASS" "$FAIL"
printf '════════════════════════════════════════════════\n'
[[ $FAIL -eq 0 ]]
