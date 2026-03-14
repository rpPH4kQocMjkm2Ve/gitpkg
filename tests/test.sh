#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Source common.sh directly (skip verify-lib)
. ./lib/common.sh
. ./lib/sandbox.sh

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ════════════════════════════════════════════════════════
# _validate_path
# ════════════════════════════════════════════════════════

# valid
_validate_path "usr/bin/foo"         && ok || fail "validate_path: usr/bin/foo"
_validate_path "etc/gitpkg/conf"     && ok || fail "validate_path: etc/gitpkg/conf"
_validate_path "usr/lib/x/y.so"      && ok || fail "validate_path: nested"
_validate_path "usr/share/licenses/gitpkg/LICENSE" && ok || fail "validate_path: deep path"

# rejected: absolute
_validate_path "/usr/bin/foo"        && fail "validate_path: absolute" || ok
_validate_path "/etc/passwd"         && fail "validate_path: absolute etc" || ok

# rejected: traversal
_validate_path "usr/../etc/passwd"   && fail "validate_path: traversal" || ok
_validate_path "../etc/passwd"       && fail "validate_path: leading traversal" || ok
_validate_path "usr/bin/../../x"     && fail "validate_path: mid traversal" || ok
_validate_path "usr/..hidden"        && fail "validate_path: dot dot in name" || ok

# rejected: empty
_validate_path ""                    && fail "validate_path: empty" || ok

# rejected: newline
_validate_path $'usr/bin/foo\nbar'   && fail "validate_path: newline" || ok

# ════════════════════════════════════════════════════════
# _validate_filelist
# ════════════════════════════════════════════════════════

# valid filelist
printf 'usr/bin/foo\nusr/lib/bar.so\n' > "${TMPDIR_TEST}/good.list"
_validate_filelist "${TMPDIR_TEST}/good.list" && ok || fail "validate_filelist: valid"

# traversal
printf 'usr/bin/foo\nusr/../etc/shadow\n' > "${TMPDIR_TEST}/bad.list"
_validate_filelist "${TMPDIR_TEST}/bad.list" 2>/dev/null \
    && fail "validate_filelist: traversal" || ok

# absolute path
printf '/etc/passwd\n' > "${TMPDIR_TEST}/abs.list"
_validate_filelist "${TMPDIR_TEST}/abs.list" 2>/dev/null \
    && fail "validate_filelist: absolute" || ok

# empty lines skipped
printf '\nusr/bin/foo\n\n' > "${TMPDIR_TEST}/empty.list"
_validate_filelist "${TMPDIR_TEST}/empty.list" && ok || fail "validate_filelist: empty lines"

# single valid entry
printf 'usr/bin/single\n' > "${TMPDIR_TEST}/single.list"
_validate_filelist "${TMPDIR_TEST}/single.list" && ok || fail "validate_filelist: single"

# ════════════════════════════════════════════════════════
# _validate_symlinks
# ════════════════════════════════════════════════════════

STAGEDIR="${TMPDIR_TEST}/stage"
mkdir -p "${STAGEDIR}/usr/bin"

# safe symlink
ln -sf /usr/lib/libfoo.so "${STAGEDIR}/usr/bin/link1"
printf 'usr/bin/link1\n' > "${TMPDIR_TEST}/sym.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/sym.list" && ok || fail "validate_symlinks: safe"

# traversal symlink
ln -sf ../../etc/shadow "${STAGEDIR}/usr/bin/link2"
printf 'usr/bin/link2\n' > "${TMPDIR_TEST}/badsym.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/badsym.list" 2>/dev/null \
    && fail "validate_symlinks: traversal" || ok

# regular file (not a symlink, should pass)
touch "${STAGEDIR}/usr/bin/regular"
printf 'usr/bin/regular\n' > "${TMPDIR_TEST}/reg.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/reg.list" && ok || fail "validate_symlinks: regular"

# relative symlink with .. is rejected (correct behavior)
ln -sf ../lib/libbar.so "${STAGEDIR}/usr/bin/link3"
printf 'usr/bin/link3\n' > "${TMPDIR_TEST}/relsym.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/relsym.list" 2>/dev/null \
    && fail "validate_symlinks: relative with dotdot should fail" || ok

# relative symlink without .. is safe
ln -sf libfoo.so "${STAGEDIR}/usr/bin/link4"
printf 'usr/bin/link4\n' > "${TMPDIR_TEST}/relsafe.list"
_validate_symlinks "$STAGEDIR" "${TMPDIR_TEST}/relsafe.list" && ok || fail "validate_symlinks: relative no dotdot"

# ════════════════════════════════════════════════════════
# is_protected_dir
# ════════════════════════════════════════════════════════

is_protected_dir /usr             && ok || fail "is_protected_dir: /usr"
is_protected_dir /usr/bin         && ok || fail "is_protected_dir: /usr/bin"
is_protected_dir /usr/lib         && ok || fail "is_protected_dir: /usr/lib"
is_protected_dir /usr/share       && ok || fail "is_protected_dir: /usr/share"
is_protected_dir /usr/local       && ok || fail "is_protected_dir: /usr/local"
is_protected_dir /usr/local/bin   && ok || fail "is_protected_dir: /usr/local/bin"
is_protected_dir /etc             && ok || fail "is_protected_dir: /etc"

is_protected_dir /opt             && fail "is_protected_dir: /opt" || ok
is_protected_dir /opt/custom      && fail "is_protected_dir: /opt/custom" || ok
is_protected_dir /var/lib         && fail "is_protected_dir: /var/lib" || ok
is_protected_dir /home            && fail "is_protected_dir: /home" || ok
is_protected_dir /tmp             && fail "is_protected_dir: /tmp" || ok

# ════════════════════════════════════════════════════════
# _dedup_urls
# ════════════════════════════════════════════════════════

result=$(printf 'https://a.com\nhttps://b.com\nhttps://a.com\n' | _dedup_urls)
count=$(echo "$result" | wc -l)
[[ $count -eq 2 ]] && ok || fail "dedup_urls: count=$count expected 2"

# preserves order
first=$(echo "$result" | head -1)
[[ "$first" == "https://a.com" ]] && ok || fail "dedup_urls: order"

# empty lines filtered
result=$(printf '\nhttps://a.com\n\n' | _dedup_urls)
count=$(echo "$result" | wc -l)
[[ $count -eq 1 ]] && ok || fail "dedup_urls: empty lines"

# all unique
result=$(printf 'https://a.com\nhttps://b.com\nhttps://c.com\n' | _dedup_urls)
count=$(echo "$result" | wc -l)
[[ $count -eq 3 ]] && ok || fail "dedup_urls: all unique"

# single url
result=$(printf 'https://only.com\n' | _dedup_urls)
[[ "$result" == "https://only.com" ]] && ok || fail "dedup_urls: single"

# ════════════════════════════════════════════════════════
# _safe_read_commit
# ════════════════════════════════════════════════════════

# normal hex commit
echo "abc123def456" > "${TMPDIR_TEST}/commit"
result=$(_safe_read_commit "${TMPDIR_TEST}/commit")
[[ "$result" == "abc123def456" ]] && ok || fail "safe_read_commit: normal ($result)"

# non-hex stripped
echo "abc123XYZ!@#def" > "${TMPDIR_TEST}/commit_dirty"
result=$(_safe_read_commit "${TMPDIR_TEST}/commit_dirty")
[[ "$result" == "abc123def" ]] && ok || fail "safe_read_commit: dirty ($result)"

# missing file
result=$(_safe_read_commit "${TMPDIR_TEST}/nonexistent")
[[ "$result" == "unknown" ]] && ok || fail "safe_read_commit: missing ($result)"

# empty file
: > "${TMPDIR_TEST}/empty_commit"
result=$(_safe_read_commit "${TMPDIR_TEST}/empty_commit")
[[ "$result" == "unknown" ]] && ok || fail "safe_read_commit: empty ($result)"

# full 40-char sha
echo "a]a2b3c4d5e6f7890123456789abcdef01234567" > "${TMPDIR_TEST}/full_commit"
result=$(_safe_read_commit "${TMPDIR_TEST}/full_commit")
[[ ${#result} -le 64 ]] && ok || fail "safe_read_commit: truncation (${#result})"

# ════════════════════════════════════════════════════════
# _strip_escape_sequences
# ════════════════════════════════════════════════════════

result=$(printf '\033[31mred\033[0m' | _strip_escape_sequences)
[[ "$result" == "red" ]] && ok || fail "strip_escape: color ($result)"

result=$(printf 'plain text' | _strip_escape_sequences)
[[ "$result" == "plain text" ]] && ok || fail "strip_escape: plain ($result)"

result=$(printf '\033[1;32mbold green\033[0m' | _strip_escape_sequences)
[[ "$result" == "bold green" ]] && ok || fail "strip_escape: bold ($result)"

result=$(printf 'no escapes here' | _strip_escape_sequences)
[[ "$result" == "no escapes here" ]] && ok || fail "strip_escape: none ($result)"

# ════════════════════════════════════════════════════════
# _has_make_target (sandbox.sh)
# ════════════════════════════════════════════════════════

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

_has_make_target "$MAKEDIR" build   && ok || fail "has_make_target: build"
_has_make_target "$MAKEDIR" install && ok || fail "has_make_target: install"
_has_make_target "$MAKEDIR" clean   && ok || fail "has_make_target: clean"
_has_make_target "$MAKEDIR" test    && fail "has_make_target: test (absent)" || ok
_has_make_target "$MAKEDIR" deploy  && fail "has_make_target: deploy (absent)" || ok

# target with spaces
cat > "${MAKEDIR}/Makefile" << 'EOF'
build :
	@echo building
EOF
_has_make_target "$MAKEDIR" build && ok || fail "has_make_target: space before colon"

# Makefile with only install (common pattern)
cat > "${MAKEDIR}/Makefile" << 'EOF'
PREFIX = /usr
DESTDIR =

install:
	install -Dm755 foo $(DESTDIR)$(PREFIX)/bin/foo
EOF
_has_make_target "$MAKEDIR" install && ok || fail "has_make_target: install only"
_has_make_target "$MAKEDIR" build   && fail "has_make_target: no build target" || ok

# ════════════════════════════════════════════════════════
# _is_system_managed
# ════════════════════════════════════════════════════════

# bash should be system-managed on any distro
_is_system_managed "bash" && ok || fail "is_system_managed: bash"

# nonexistent package
_is_system_managed "definitely-not-a-real-package-xyz-12345" \
    && fail "is_system_managed: fake package" || ok

# ════════════════════════════════════════════════════════
# Results
# ════════════════════════════════════════════════════════

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
