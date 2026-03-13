# /usr/lib/gitpkg/common.sh — constants, validation, locking, utility helpers

readonly VERSION="0.7.5"
readonly DBDIR="/var/lib/gitpkg"
readonly SRCDIR="/var/cache/gitpkg"
readonly COLLECTIONSDIR="${SRCDIR}/_collections"
readonly LOCK_FILE="/var/lock/gitpkg.lock"
readonly CONFDIR="/etc/gitpkg"
readonly REPOS_CONF="${CONFDIR}/repos.conf"
readonly MIRRORLIST="${CONFDIR}/mirrorlist"
readonly PKGLIST="${CONFDIR}/pkglist"
readonly COLLECTIONS_CONF="${CONFDIR}/collections.conf"
readonly COLLECTIONS_LIST="${CONFDIR}/collections"
readonly CLONE_TIMEOUT="${GITPKG_CLONE_TIMEOUT:-120}"
readonly FETCH_TIMEOUT="${GITPKG_FETCH_TIMEOUT:-30}"
readonly LSREMOTE_TIMEOUT="${GITPKG_LSREMOTE_TIMEOUT:-15}"
readonly MAX_STATUS_PARALLEL=8

readonly -a PROTECTED_DIRS=(
    /usr /usr/bin /usr/lib /usr/share /usr/local /usr/local/bin
    /usr/share/applications /usr/share/licenses
    /usr/share/zsh /usr/share/zsh/site-functions
    /usr/share/bash-completion /usr/share/bash-completion/completions
    /etc
)

readonly -A EXPECTED_PERMS=(
    [/]=755
    [/usr]=755
    [/usr/bin]=755
    [/usr/lib]=755
    [/usr/share]=755
    [/etc]=755
    [/var]=755
    [/tmp]=1777
    [/run]=755
)

# ── Output helpers ────────────────────────────────────────

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ── Dependency check ──────────────────────────────────────

_check_deps() {
    local dep
    for dep in git bwrap make find awk sha256sum timeout; do
        command -v "$dep" &>/dev/null || die "required dependency not found: ${dep}"
    done
}

# ── Locking ───────────────────────────────────────────────

LOCK_ACQUIRED=0

acquire_lock() {
    local lock_dir
    lock_dir=$(dirname "$LOCK_FILE")
    [[ -d "$lock_dir" ]] || mkdir -p "$lock_dir"

    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        die "another gitpkg operation is running"
    fi
    LOCK_ACQUIRED=1
}

# ── Cleanup ───────────────────────────────────────────────

STAGE_DIR=""
BUILD_OVERLAY=""
STATUS_TMPDIR=""

cleanup() {
    set +e
    [[ -n "$BUILD_OVERLAY" && -d "$BUILD_OVERLAY" ]] && rm -rf "$BUILD_OVERLAY"
    [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]] && rm -rf "$STAGE_DIR"
    [[ -n "$STATUS_TMPDIR" && -d "$STATUS_TMPDIR" ]] && rm -rf "$STATUS_TMPDIR"
    if [[ "$LOCK_ACQUIRED" -eq 1 ]]; then
        flock -u 9 2>/dev/null
        exec 9>&- 2>/dev/null
        rm -f "$LOCK_FILE"
        LOCK_ACQUIRED=0
    fi
}

trap cleanup EXIT
trap 'exit 1' TERM INT HUP

# ── Path validation ───────────────────────────────────────

_validate_path() {
    local filepath="$1"
    if [[ -z "$filepath" ]]; then
        return 1
    fi
    if [[ "$filepath" == /* ]]; then
        return 1
    fi
    if [[ "$filepath" =~ \.\. ]]; then
        return 1
    fi
    if [[ "$filepath" == *$'\n'* ]]; then
        return 1
    fi
    return 0
}

_validate_filelist() {
    local filelist="$1"
    local bad=0
    while IFS= read -r f; do
        if [[ -z "$f" ]]; then
            continue
        fi
        if ! _validate_path "$f"; then
            printf 'REJECTED: dangerous path in filelist: %s\n' "$f" >&2
            bad=1
        fi
    done < "$filelist"
    return "$bad"
}

_validate_symlinks() {
    local stagedir="$1" filelist="$2"
    local bad=0
    while IFS= read -r f; do
        if [[ -z "$f" ]]; then
            continue
        fi
        local staged="${stagedir}/${f}"
        if [[ ! -L "$staged" ]]; then
            continue
        fi
        local target
        target=$(readlink "$staged")
        if [[ "$target" =~ \.\. ]]; then
            printf 'REJECTED: symlink with traversal: %s -> %s\n' "$f" "$target" >&2
            bad=1
        fi
    done < "$filelist"
    return "$bad"
}

# ── Internal helpers ──────────────────────────────────────

is_protected_dir() {
    local dir="$1" p
    for p in "${PROTECTED_DIRS[@]}"; do
        [[ "$dir" == "$p" ]] && return 0
    done
    return 1
}

_dedup_urls() {
    awk 'NF && !seen[$0]++'
}

_ensure_conf() {
    [[ -d "$CONFDIR" ]] || mkdir -p "$CONFDIR"
    [[ -d "$COLLECTIONSDIR" ]] || mkdir -p "$COLLECTIONSDIR"
    if [[ ! -f "$REPOS_CONF" ]]; then
        touch "$REPOS_CONF"
        chmod 644 "$REPOS_CONF"
    fi
    if [[ ! -f "$COLLECTIONS_CONF" ]]; then
        touch "$COLLECTIONS_CONF"
        chmod 644 "$COLLECTIONS_CONF"
    fi
}

_safe_read_commit() {
    local commitfile="$1"
    if [[ -f "$commitfile" && -s "$commitfile" ]]; then
        head -c 64 "$commitfile" | tr -cd 'a-f0-9'
    else
        printf 'unknown'
    fi
}

_strip_escape_sequences() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b[PX^_][^\x1b]*\x1b\\//g; s/\x1b.//g'
}

# ── System package manager detection ──────────────────────

_is_system_managed() {
    local name="$1"
    if command -v pacman &>/dev/null; then
        pacman -Qq "$name" &>/dev/null 2>&1 && return 0
    fi
    if command -v dpkg &>/dev/null; then
        dpkg -s "$name" &>/dev/null 2>&1 && return 0
    fi
    if command -v rpm &>/dev/null; then
        rpm -q "$name" &>/dev/null 2>&1 && return 0
    fi
    return 1
}
