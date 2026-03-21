#!/usr/bin/env bash
set -uo pipefail

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
source "${PROJECT_ROOT}/lib/common.sh"
source "${PROJECT_ROOT}/lib/sandbox.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ════════════════════════════════════════════════════════
# _validate_path
# ════════════════════════════════════════════════════════

section "_validate_path"

# valid
_validate_path "usr/bin/foo"         && ok "usr/bin/foo valid" || fail "usr/bin/foo rejected"
_validate_path "etc/gitpkg/conf"     && ok "etc/gitpkg/conf valid" || fail "etc/gitpkg/conf rejected"
_validate_path "usr/lib/x/y.so"      && ok "nested path valid" || fail "nested path rejected"
_validate_path "usr/share/licenses/gitpkg/LICENSE" && ok "deep path valid" || fail "deep path rejected"
_validate_path "usr/..hidden"        && ok "..hidden is valid filename" || fail "..hidden wrongly rejected"
_validate_path "usr/bin/foo..bar"    && ok "foo..bar is valid filename" || fail "foo..bar wrongly rejected"
_validate_path "usr/lib/lib..2.so"   && ok "lib..2.so is valid filename" || fail "lib..2.so wrongly rejected"

# rejected: absolute
_validate_path "/usr/bin/foo"        && fail "absolute /usr/bin/foo accepted" || ok "absolute /usr/bin/foo rejected"
_validate_path "/etc/passwd"         && fail "absolute /etc/passwd accepted" || ok "absolute /etc/passwd rejected"

# rejected: traversal
_validate_path "usr/../etc/passwd"   && fail "traversal accepted" || ok "traversal rejected"
_validate_path "../etc/passwd"       && fail "leading traversal accepted" || ok "leading traversal rejected"
_validate_path "usr/bin/../../x"     && fail "mid traversal accepted" || ok "mid traversal rejected"

# rejected: empty
_validate_path ""                    && fail "empty path accepted" || ok "empty path rejected"

# rejected: newline
_validate_path $'usr/bin/foo\nbar'   && fail "newline path accepted" || ok "newline path rejected"

# ════════════════════════════════════════════════════════
# _validate_filelist
# ════════════════════════════════════════════════════════

section "_validate_filelist"

# valid filelist
printf 'usr/bin/foo\nusr/lib/bar.so\n' > "${TMPDIR_TEST}/good.list"
_validate_filelist "${TMPDIR_TEST}/good.list" && ok "valid filelist accepted" || fail "valid filelist rejected"

# traversal
printf 'usr/bin/foo\nusr/../etc/shadow\n' > "${TMPDIR_TEST}/bad.list"
_validate_filelist "${TMPDIR_TEST}/bad.list" 2>/dev/null \
    && fail "traversal filelist accepted" || ok "traversal filelist rejected"

# absolute path
printf '/etc/passwd\n' > "${TMPDIR_TEST}/abs.list"
_validate_filelist "${TMPDIR_TEST}/abs.list" 2>/dev/null \
    && fail "absolute filelist accepted" || ok "absolute filelist rejected"

# empty lines skipped
printf '\nusr/bin/foo\n\n' > "${TMPDIR_TEST}/empty.list"
_validate_filelist "${TMPDIR_TEST}/empty.list" && ok "empty lines skipped" || fail "empty lines rejected"

# single valid entry
printf 'usr/bin/single\n' > "${TMPDIR_TEST}/single.list"
_validate_filelist "${TMPDIR_TEST}/single.list" && ok "single entry valid" || fail "single entry rejected"

# ════════════════════════════════════════════════════════
# _validate_symlinks
# ════════════════════════════════════════════════════════

section "_validate_symlinks"

STAGEDIR="${TMPDIR_TEST}/stage"
mkdir -p "${STAGEDIR}/usr/bin"

# safe symlink
ln -sf /usr/lib/libfoo.so "${STAGEDIR}/usr/bin/link1"
printf 'usr/bin/link1\n' > "${TMPDIR_TEST}/sym.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/sym.list" && ok "safe symlink accepted" || fail "safe symlink rejected"

# traversal symlink
ln -sf ../../etc/shadow "${STAGEDIR}/usr/bin/link2"
printf 'usr/bin/link2\n' > "${TMPDIR_TEST}/badsym.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/badsym.list" 2>/dev/null \
    && fail "traversal symlink accepted" || ok "traversal symlink rejected"

# regular file (not a symlink, should pass)
touch "${STAGEDIR}/usr/bin/regular"
printf 'usr/bin/regular\n' > "${TMPDIR_TEST}/reg.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/reg.list" && ok "regular file passes" || fail "regular file rejected"

# relative symlink with .. is rejected (correct behavior)
ln -sf ../lib/libbar.so "${STAGEDIR}/usr/bin/link3"
printf 'usr/bin/link3\n' > "${TMPDIR_TEST}/relsym.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/relsym.list" 2>/dev/null \
    && fail "relative with dotdot accepted" || ok "relative with dotdot rejected"

# relative symlink without .. is safe
ln -sf libfoo.so "${STAGEDIR}/usr/bin/link4"
printf 'usr/bin/link4\n' > "${TMPDIR_TEST}/relsafe.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/relsafe.list" && ok "relative no dotdot passes" || fail "relative no dotdot rejected"

# symlink to file with double dots in name (not traversal)
ln -sf libfoo..2.so "${STAGEDIR}/usr/bin/link5"
printf 'usr/bin/link5\n' > "${TMPDIR_TEST}/dotdotsym.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/dotdotsym.list" && ok "symlink to ..name is valid" || fail "symlink to ..name wrongly rejected"

# ════════════════════════════════════════════════════════
# is_protected_dir
# ════════════════════════════════════════════════════════

section "is_protected_dir"

is_protected_dir /usr             && ok "/usr protected" || fail "/usr not protected"
is_protected_dir /usr/bin         && ok "/usr/bin protected" || fail "/usr/bin not protected"
is_protected_dir /usr/lib         && ok "/usr/lib protected" || fail "/usr/lib not protected"
is_protected_dir /usr/share       && ok "/usr/share protected" || fail "/usr/share not protected"
is_protected_dir /usr/local       && ok "/usr/local protected" || fail "/usr/local not protected"
is_protected_dir /usr/local/bin   && ok "/usr/local/bin protected" || fail "/usr/local/bin not protected"
is_protected_dir /etc             && ok "/etc protected" || fail "/etc not protected"

is_protected_dir /opt             && fail "/opt falsely protected" || ok "/opt not protected"
is_protected_dir /opt/custom      && fail "/opt/custom falsely protected" || ok "/opt/custom not protected"
is_protected_dir /var/lib         && fail "/var/lib falsely protected" || ok "/var/lib not protected"
is_protected_dir /home            && fail "/home falsely protected" || ok "/home not protected"
is_protected_dir /tmp             && fail "/tmp falsely protected" || ok "/tmp not protected"

# ════════════════════════════════════════════════════════
# _dedup_urls
# ════════════════════════════════════════════════════════

section "_dedup_urls"

result=$(printf 'https://a.com\nhttps://b.com\nhttps://a.com\n' | _dedup_urls)
count=$(echo "$result" | wc -l)
[[ $count -eq 2 ]] && ok "dedup count=2" || fail "dedup count=$count expected 2"

# preserves order
first=$(echo "$result" | head -1)
[[ "$first" == "https://a.com" ]] && ok "order preserved" || fail "order not preserved"

# empty lines filtered
result=$(printf '\nhttps://a.com\n\n' | _dedup_urls)
count=$(echo "$result" | wc -l)
[[ $count -eq 1 ]] && ok "empty lines filtered" || fail "empty lines not filtered"

# all unique
result=$(printf 'https://a.com\nhttps://b.com\nhttps://c.com\n' | _dedup_urls)
count=$(echo "$result" | wc -l)
[[ $count -eq 3 ]] && ok "all unique preserved" || fail "unique URLs lost"

# single url
result=$(printf 'https://only.com\n' | _dedup_urls)
[[ "$result" == "https://only.com" ]] && ok "single URL" || fail "single URL failed"

# ════════════════════════════════════════════════════════
# _safe_read_commit
# ════════════════════════════════════════════════════════

section "_safe_read_commit"

# normal hex commit
echo "abc123def456" > "${TMPDIR_TEST}/commit"
result=$(_safe_read_commit "${TMPDIR_TEST}/commit")
[[ "$result" == "abc123def456" ]] && ok "normal hex commit" || fail "normal hex: $result"

# non-hex stripped
echo "abc123XYZ!@#def" > "${TMPDIR_TEST}/commit_dirty"
result=$(_safe_read_commit "${TMPDIR_TEST}/commit_dirty")
[[ "$result" == "abc123def" ]] && ok "dirty commit stripped" || fail "dirty: $result"

# missing file
result=$(_safe_read_commit "${TMPDIR_TEST}/nonexistent")
[[ "$result" == "unknown" ]] && ok "missing file returns unknown" || fail "missing: $result"

# empty file
: > "${TMPDIR_TEST}/empty_commit"
result=$(_safe_read_commit "${TMPDIR_TEST}/empty_commit")
[[ "$result" == "unknown" ]] && ok "empty file returns unknown" || fail "empty: $result"

# full 40-char sha
echo "a]a2b3c4d5e6f7890123456789abcdef01234567" > "${TMPDIR_TEST}/full_commit"
result=$(_safe_read_commit "${TMPDIR_TEST}/full_commit")
[[ ${#result} -le 64 ]] && ok "truncation ≤64 chars" || fail "truncation: ${#result}"

# ════════════════════════════════════════════════════════
# _strip_escape_sequences
# ════════════════════════════════════════════════════════

section "_strip_escape_sequences"

result=$(printf '\033[31mred\033[0m' | _strip_escape_sequences)
[[ "$result" == "red" ]] && ok "color stripped" || fail "color: $result"

result=$(printf 'plain text' | _strip_escape_sequences)
[[ "$result" == "plain text" ]] && ok "plain text unchanged" || fail "plain: $result"

result=$(printf '\033[1;32mbold green\033[0m' | _strip_escape_sequences)
[[ "$result" == "bold green" ]] && ok "bold stripped" || fail "bold: $result"

result=$(printf 'no escapes here' | _strip_escape_sequences)
[[ "$result" == "no escapes here" ]] && ok "no escapes unchanged" || fail "no escapes: $result"

# ════════════════════════════════════════════════════════
# _has_make_target (sandbox.sh)
# ════════════════════════════════════════════════════════

section "_has_make_target"

MAKEDIR="${TMPDIR_TEST}/makedir"
mkdir -p "$MAKEDIR"
cat > "${MAKEDIR}/Makefile" << 'EOF'
build:
	@echo building

install:
	@echo installing

clean:
	@echo cleaning
EOF

_has_make_target "$MAKEDIR" build   && ok "build target found" || fail "build target missing"
_has_make_target "$MAKEDIR" install && ok "install target found" || fail "install target missing"
_has_make_target "$MAKEDIR" clean   && ok "clean target found" || fail "clean target missing"
_has_make_target "$MAKEDIR" test    && fail "test target found (absent)" || ok "test target absent"
_has_make_target "$MAKEDIR" deploy  && fail "deploy target found (absent)" || ok "deploy target absent"

# target with spaces
cat > "${MAKEDIR}/Makefile" << 'EOF'
build :
	@echo building
EOF
_has_make_target "$MAKEDIR" build && ok "space before colon" || fail "space before colon rejected"

# Makefile with only install (common pattern)
cat > "${MAKEDIR}/Makefile" << 'EOF'
PREFIX = /usr
DESTDIR =

install:
	install -Dm755 foo $(DESTDIR)$(PREFIX)/bin/foo
EOF
_has_make_target "$MAKEDIR" install && ok "install-only Makefile" || fail "install-only Makefile rejected"
_has_make_target "$MAKEDIR" build   && fail "build found in install-only" || ok "build absent in install-only"

# ════════════════════════════════════════════════════════
# _is_system_managed
# ════════════════════════════════════════════════════════

section "_is_system_managed"

# bash should be system-managed on any distro
_is_system_managed "bash" && ok "bash is system-managed" || fail "bash not system-managed"

# nonexistent package
_is_system_managed "definitely-not-a-real-package-xyz-12345" \
    && fail "fake package is system-managed" || ok "fake package not system-managed"

# ════════════════════════════════════════════════════════
# Results
# ════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed (total: $TESTS)"
echo "════════════════════════════════════"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
