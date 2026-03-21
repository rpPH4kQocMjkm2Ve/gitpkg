# /usr/lib/gitpkg/package.sh — URL resolution, cloning, staging, deploy, verification

# Clone result globals
CLONE_SUCCESS_URL=""

# Collection search result globals
_FOUND_COLLECTION=""
_FOUND_WORKDIR=""
_FOUND_GITDIR=""

# ── Signature verification ─────────────────────────────

_build_signers_file() {
    local combined
    combined=$(mktemp /tmp/gitpkg-signers.XXXXXX)
    {
        [[ -f "$SIGNERS_DEFAULT" && -r "$SIGNERS_DEFAULT" ]] && grep -v '^\s*#' "$SIGNERS_DEFAULT" | grep -v '^\s*$'
        [[ -f "$SIGNERS_CONF" && -r "$SIGNERS_CONF" ]] && grep -v '^\s*#' "$SIGNERS_CONF" | grep -v '^\s*$'
    } > "$combined" 2>/dev/null || true
    printf '%s' "$combined"
}

_verify_signature() {
    local gitdir="$1"
    local commit_ref="${2:-HEAD}"

    local combined
    combined=$(_build_signers_file)

    # No keys configured — verification not active
    if [[ ! -s "$combined" ]]; then
        rm -f "$combined"
        return 0
    fi

    local output rc=0
    output=$(git -C "$gitdir" \
        -c gpg.format=ssh \
        -c "gpg.ssh.allowedSignersFile=${combined}" \
        verify-commit "$commit_ref" 2>&1) || rc=$?

    rm -f "$combined"

    if [[ $rc -eq 0 ]]; then
        local signer
        signer=$(printf '%s\n' "$output" \
            | sed -n 's/.*Good.*signature for \([^ ]*\).*/\1/p' | head -1)
        if [[ -n "$signer" ]]; then
            printf '   Signature: verified (%s)\n' "$signer"
        else
            printf '   Signature: verified\n'
        fi
        return 0
    fi

    printf '   WARNING: commit is NOT signed by a trusted key\n' >&2
    return 1
}

# ── URL resolution ────────────────────────────────────────

_resolve_urls() {
    local name="$1"
    local conf base
    for conf in "$REPOS_CONF" "$MIRRORLIST"; do
        [[ -f "$conf" && -r "$conf" ]] || continue
        while IFS= read -r base; do
            [[ -z "$base" || "$base" == \#* ]] && continue
            printf '%s/%s\n' "${base%/}" "$name"
        done < "$conf"
    done | _dedup_urls
}

# ── Collection helpers ────────────────────────────────────

_load_collections() {
    local -a result=()
    local -A seen=()
    local conf
    for conf in "$COLLECTIONS_CONF" "$COLLECTIONS_LIST"; do
        [[ -f "$conf" && -r "$conf" ]] || continue
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            [[ -n "${seen[$line]:-}" ]] && continue
            seen[$line]=1
            result+=("$line")
        done < "$conf"
    done
    [[ ${#result[@]} -gt 0 ]] && printf '%s\n' "${result[@]}"
}

_clone_to() {
    local destdir="$1"; shift
    local -a urls=("$@")

    local url
    for url in "${urls[@]}"; do
        printf '   Cloning %s ... ' "$url"
        local parent
        parent=$(dirname "$destdir")
        [[ -d "$parent" ]] || mkdir -p "$parent"
        if timeout "$CLONE_TIMEOUT" git clone --filter=blob:none "$url" "$destdir" &>/dev/null; then
            echo "ok"
            CLONE_SUCCESS_URL="$url"
            return 0
        fi
        echo "fail"
        rm -rf "$destdir"
    done
    return 1
}

# Search for package $1 inside configured collections.
# Sets globals: _FOUND_COLLECTION, _FOUND_WORKDIR, _FOUND_GITDIR, CLONE_SUCCESS_URL
_find_in_collections() {
    local name="$1"
    local do_fetch="${2:-1}"
    _FOUND_COLLECTION=""
    _FOUND_WORKDIR=""
    _FOUND_GITDIR=""

    local -a collections=()
    mapfile -t collections < <(_load_collections)
    [[ ${#collections[@]} -gt 0 ]] || return 1

    local coll colldir
    for coll in "${collections[@]}"; do
        colldir="${COLLECTIONSDIR}/${coll}"

        if [[ -d "$colldir/.git" ]]; then
            if [[ -f "${colldir}/${name}/Makefile" ]]; then
                _FOUND_COLLECTION="$coll"
                _FOUND_WORKDIR="${colldir}/${name}"
                _FOUND_GITDIR="$colldir"
                CLONE_SUCCESS_URL=$(git -C "$colldir" remote get-url origin 2>/dev/null || true)
                return 0
            fi
            [[ "$do_fetch" -eq 1 ]] || continue
            local branch
            branch=$(git -C "$colldir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
            timeout "$FETCH_TIMEOUT" git -C "$colldir" fetch origin "$branch" &>/dev/null || true
            if git -C "$colldir" cat-file -e "origin/${branch}:${name}/Makefile" 2>/dev/null; then
                git -C "$colldir" reset --hard "origin/${branch}" &>/dev/null || true
                _FOUND_COLLECTION="$coll"
                _FOUND_WORKDIR="${colldir}/${name}"
                _FOUND_GITDIR="$colldir"
                CLONE_SUCCESS_URL=$(git -C "$colldir" remote get-url origin 2>/dev/null || true)
                return 0
            fi
            continue
        fi

        [[ "$do_fetch" -eq 1 ]] || continue

        local -a coll_urls=()
        mapfile -t coll_urls < <(_resolve_urls "$coll")
        [[ ${#coll_urls[@]} -gt 0 ]] || continue

        CLONE_SUCCESS_URL=""
        if _clone_to "$colldir" "${coll_urls[@]}"; then
            if [[ -f "${colldir}/${name}/Makefile" ]]; then
                _FOUND_COLLECTION="$coll"
                _FOUND_WORKDIR="${colldir}/${name}"
                _FOUND_GITDIR="$colldir"
                return 0
            fi
        fi
    done

    return 1
}

# ── Dependency checking ───────────────────────────────────

_check_package_deps() {
    local workdir="$1"
    local depsfile="${workdir}/depends"
    [[ -f "$depsfile" ]] || return 0

    local missing=0
    local header_shown=0

    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue

        local type dep
        type="${line%%:*}"
        dep="${line#*:}"
        [[ -n "$dep" ]] || continue

        case "$type" in
            gitpkg)
                if [[ ! -d "${DBDIR}/${dep}" ]]; then
                    [[ $header_shown -eq 0 ]] && { printf '   Missing dependencies:\n'; header_shown=1; }
                    printf '     [gitpkg]  %-20s → gitpkg install %s\n' "$dep" "$dep"
                    missing=1
                fi
                ;;
            system)
                if ! command -v "$dep" &>/dev/null && \
                   ! pacman -Qq "$dep" &>/dev/null 2>&1; then
                    [[ $header_shown -eq 0 ]] && { printf '   Missing dependencies:\n'; header_shown=1; }
                    printf '     [system]  %-20s → pacman -S %s\n' "$dep" "$dep"
                    missing=1
                fi
                ;;
        esac
    done < "$depsfile"

    return $missing
}

# Check if any installed package depends on the given package
# Prints names of dependent packages to stdout
# Returns 0 if no dependents, 1 if dependents exist
_check_reverse_deps() {
    local name="$1"
    local -a dependents=()
    local d
    for d in "${DBDIR}"/*/; do
        [[ -d "$d" ]] || continue
        local pkg
        pkg=$(basename "$d")
        [[ "$pkg" == "$name" ]] && continue

        # Prefer dbdir copy (stored at install time)
        local depsfile="${d}depends"
        if [[ ! -f "$depsfile" ]]; then
            # Fallback: source tree for packages installed before this feature
            if [[ -f "${d}collection" ]]; then
                local coll
                coll=$(cat "${d}collection")
                depsfile="${COLLECTIONSDIR}/${coll}/${pkg}/depends"
            else
                depsfile="${SRCDIR}/${pkg}/depends"
            fi
        fi

        [[ -f "$depsfile" ]] || continue
        if grep -qxF "gitpkg:${name}" "$depsfile" 2>/dev/null; then
            dependents+=("$pkg")
        fi
    done

    if [[ ${#dependents[@]} -gt 0 ]]; then
        printf '%s\n' "${dependents[@]}"
        return 1
    fi
    return 0
}

# ── Clone ─────────────────────────────────────────────────

_clone() {
    local name="$1"; shift
    local -a urls=("$@")
    local srcdir="${SRCDIR}/${name}"
    CLONE_SUCCESS_URL=""

    if [[ -d "$srcdir" && ! -d "${DBDIR}/${name}" ]]; then
        echo ":: Cleaning stale source cache for ${name}..."
        rm -rf "$srcdir"
    fi

    [[ -d "$srcdir" ]] && die "${name}: source already exists at ${srcdir}"

    if _clone_to "$srcdir" "${urls[@]}"; then
        return 0
    fi

    return 1
}

# ── Stage & Deploy ────────────────────────────────────────

# $1 = name
# $2 = dry_run (0|1)
# $3 = workdir (optional — directory containing the Makefile; defaults to $SRCDIR/$name)
# $4 = gitdir  (optional — git root for commit hash; defaults to workdir)
#
# Returns:
#   0 — deployed successfully
#   1 — dry run completed, nothing deployed
# On fatal errors (validation, empty filelist) calls die() and does not return.
_stage_and_deploy() {
    local name="$1" dry_run="${2:-0}"
    local workdir="${3:-${SRCDIR}/${name}}"
    local gitdir="${4:-${workdir}}"
    local dbdir="${DBDIR}/${name}"

    STAGE_DIR=$(mktemp -d /tmp/gitpkg-stage.XXXXXX)
    BUILD_OVERLAY=$(mktemp -d /tmp/gitpkg-build.XXXXXX)

    cp -a "${workdir}/." "$BUILD_OVERLAY"
    chmod -R a+rX "$BUILD_OVERLAY"
    chmod 777 "$STAGE_DIR"

    if _has_make_target "$BUILD_OVERLAY" build; then
        echo ":: Building ${name}..."
        _sandboxed_make build "$BUILD_OVERLAY"
    fi

    echo ":: Staging ${name}..."
    _sandboxed_make install "$BUILD_OVERLAY" "$STAGE_DIR"

    rm -rf "$BUILD_OVERLAY"
    BUILD_OVERLAY=""

    mkdir -p "$dbdir"

    find "$STAGE_DIR" -not -type d -printf '%P\n' | tr -d '\r' | sort > "${dbdir}/files.tmp"

    if ! _validate_filelist "${dbdir}/files.tmp"; then
        rm -f "${dbdir}/files.tmp"
        rm -rf "$STAGE_DIR" "$dbdir"
        STAGE_DIR=""
        die "filelist contains dangerous paths — aborting"
    fi

    if ! _validate_symlinks "$STAGE_DIR" "${dbdir}/files.tmp"; then
        rm -f "${dbdir}/files.tmp"
        rm -rf "$STAGE_DIR" "$dbdir"
        STAGE_DIR=""
        die "staged symlinks contain path traversal — aborting"
    fi

    mv "${dbdir}/files.tmp" "${dbdir}/files"

    local file_count
    file_count=$(wc -l < "${dbdir}/files")
    if [[ "$file_count" -eq 0 ]]; then
        rm -rf "$STAGE_DIR" "$dbdir"
        STAGE_DIR=""
        die "make install produced no files"
    fi

    # ── Load backup list from package source ──
    local -A _backup_files=()
    if [[ -f "${workdir}/backup" ]]; then
        while IFS= read -r _bline; do
            [[ -z "$_bline" || "$_bline" == \#* ]] && continue
            _backup_files["${_bline#/}"]=1
        done < "${workdir}/backup"
        cp "${workdir}/backup" "${dbdir}/backup"
    fi

    # Store depends file for reverse dependency checking on removal
    if [[ -f "${workdir}/depends" ]]; then
        cp "${workdir}/depends" "${dbdir}/depends"
    fi

    # ── Dry run ──
    if [[ "$dry_run" -eq 1 ]]; then
        printf '   Would deploy %d files:\n' "$file_count"
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if [[ -n "${_backup_files[$f]:-}" && -e "/${f}" ]]; then
                printf '   /%s  (backup — existing preserved)\n' "$f"
            elif [[ -e "/${f}" || -L "/${f}" ]]; then
                printf '   /%s  (overwrite)\n' "$f"
            else
                printf '   /%s\n' "$f"
            fi
        done < "${dbdir}/files"
        rm -rf "$STAGE_DIR" "$dbdir"
        STAGE_DIR=""
        return 1
    fi

    # ── Deploy ──
    local _bkp_chk_tmp="${dbdir}/backup_checksums.tmp"
    : > "$_bkp_chk_tmp"

    printf ':: Deploying %s (%d files)...\n' "$name" "$file_count"
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local dest="/${f}"
        local staged="${STAGE_DIR}/${f}"

        # ── Backup file handling ──
        if [[ -n "${_backup_files[$f]:-}" && -f "$staged" && ! -L "$staged" ]]; then
            local _staged_hash
            _staged_hash=$(sha256sum "$staged" | awk '{print $1}')
            # Always record the package-provided hash for future comparison
            printf '%s\t%s\n' "$_staged_hash" "$f" >> "$_bkp_chk_tmp"

            if [[ -f "$dest" ]]; then
                local _sys_hash
                _sys_hash=$(sha256sum "$dest" | awk '{print $1}')

                # System file identical to new version — skip
                if [[ "$_sys_hash" == "$_staged_hash" ]]; then
                    continue
                fi

                # Was the file modified by the user?
                local _old_pkg_hash=""
                if [[ -f "${dbdir}/backup_checksums" ]]; then
                    _old_pkg_hash=$(awk -F'\t' -v p="$f" '$2 == p {print $1}' \
                        "${dbdir}/backup_checksums" 2>/dev/null)
                fi

                if [[ -n "$_old_pkg_hash" && "$_sys_hash" == "$_old_pkg_hash" ]]; then
                    # User didn't modify — safe to overwrite with new version
                    local destdir; destdir=$(dirname "$dest")
                    [[ -d "$destdir" ]] || install -d -m755 "$destdir"
                    local mode; mode=$(stat -c '%a' "$staged")
                    install -m "$mode" "$staged" "$dest"
                else
                    # User modified — save new version as .gitpkg.new
                    local destdir; destdir=$(dirname "$dest")
                    [[ -d "$destdir" ]] || install -d -m755 "$destdir"
                    local mode; mode=$(stat -c '%a' "$staged")
                    install -m "$mode" "$staged" "${dest}.gitpkg.new"
                    printf '   warning: /%s was modified — new version at %s.gitpkg.new\n' \
                        "$f" "$dest"
                fi
                continue
            fi
            # File doesn't exist on system — fall through to normal install
        fi

        # ── Normal deploy ──
        local destdir; destdir=$(dirname "$dest")
        [[ -d "$destdir" ]] || install -d -m755 "$destdir"

        if [[ -L "$staged" ]]; then
            local link_target; link_target=$(readlink "$staged")
            ln -sf "$link_target" "$dest"
        else
            local mode; mode=$(stat -c '%a' "$staged")
            install -m "$mode" "$staged" "$dest"
        fi
    done < "${dbdir}/files"

    # Finalize backup checksums
    if [[ -s "$_bkp_chk_tmp" ]]; then
        mv "$_bkp_chk_tmp" "${dbdir}/backup_checksums"
    else
        rm -f "$_bkp_chk_tmp" "${dbdir}/backup_checksums"
    fi

    rm -rf "$STAGE_DIR"
    STAGE_DIR=""

    git -C "$gitdir" rev-parse HEAD > "${dbdir}/commit"

    _record_checksums "$dbdir"

    _verify_permissions 0 || true
}

# ── Remove tracked files ─────────────────────────────────

_remove_tracked() {
    local name="$1"
    local filelist="${DBDIR}/${name}/files"
    local backupfile="${DBDIR}/${name}/backup"
    [[ -f "$filelist" ]] || return 0

    # Load backup/preserve list
    local -A _preserve=()
    if [[ -f "$backupfile" ]]; then
        while IFS= read -r _line; do
            [[ -z "$_line" || "$_line" == \#* ]] && continue
            _preserve["${_line#/}"]=1
        done < "$backupfile"
    fi

    local removed=0 preserved=0
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        _validate_path "$f" || continue

        if [[ -n "${_preserve[$f]:-}" ]]; then
            if [[ -L "/${f}" || -f "/${f}" ]]; then
                printf '   Keeping /%s (backup)\n' "$f"
                preserved=$((preserved + 1))
            fi
            continue
        fi

        if [[ -L "/${f}" || -f "/${f}" ]]; then
            rm -f "/${f}"
            removed=$((removed + 1))
        fi
    done < "$filelist"

    awk -F/ '{
        for (i = NF; i > 1; i--) {
            s = ""
            for (j = 1; j < i; j++) s = s "/" $j
            if (s != "") print s
        }
    }' "$filelist" | sort -ru | while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        is_protected_dir "$d" && continue
        rmdir "$d" 2>/dev/null || true
    done

    printf '   Removed %d file(s)\n' "$removed"
    if [[ $preserved -gt 0 ]]; then
        printf '   Preserved %d backup file(s) — remove manually if needed\n' "$preserved"
    fi
}

# ── Checksums & integrity ─────────────────────────────────

_record_checksums() {
    local dbdir="$1"
    local filelist="${dbdir}/files"
    local checksumfile="${dbdir}/checksums"

    : > "$checksumfile"
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if [[ -L "/${f}" ]]; then
            local link_target
            link_target=$(readlink "/${f}")
            printf 'SYMLINK\t%s\t%s\n' "$f" "$link_target" >> "$checksumfile"
        elif [[ -f "/${f}" ]]; then
            local hash
            hash=$(sha256sum "/${f}" | awk '{print $1}')
            printf '%s\t%s\n' "$hash" "$f" >> "$checksumfile"
        fi
    done < "$filelist"
}

_verify_package() {
    local name="$1"
    local dbdir="${DBDIR}/${name}"
    [[ -d "$dbdir" ]] || die "${name} is not installed"

    if [[ ! -f "${dbdir}/checksums" || ! -s "${dbdir}/checksums" ]]; then
        echo "${name}: no checksums recorded (reinstall to generate)"
        return 1
    fi

    local bad=0
    while IFS=$'\t' read -r field1 field2 field3; do
        [[ -z "$field1" ]] && continue
        if [[ "$field1" == "SYMLINK" ]]; then
            local filepath="$field2" expected_target="$field3"
            if [[ ! -L "/${filepath}" ]]; then
                printf '  MISSING SYMLINK: /%s\n' "$filepath"
                bad=1
            else
                local actual_target
                actual_target=$(readlink "/${filepath}")
                if [[ "$actual_target" != "$expected_target" ]]; then
                    printf '  SYMLINK CHANGED: /%s (%s -> %s)\n' "$filepath" "$expected_target" "$actual_target"
                    bad=1
                fi
            fi
        else
            local expected_hash="$field1" filepath="$field2"
            if [[ ! -f "/${filepath}" ]]; then
                printf '  MISSING:  /%s\n' "$filepath"
                bad=1
            else
                local actual
                actual=$(sha256sum "/${filepath}" | awk '{print $1}')
                if [[ "$expected_hash" != "$actual" ]]; then
                    printf '  MODIFIED: /%s\n' "$filepath"
                    bad=1
                fi
            fi
        fi
    done < "${dbdir}/checksums"

    if [[ $bad -eq 0 ]]; then
        printf '%s: OK\n' "$name"
    fi
    return "$bad"
}

# ── Verify permissions ────────────────────────────────────

_verify_permissions() {
    local fix="${1:-0}"
    local bad=0

    echo ":: Verifying directory permissions..."
    local d
    for d in "${!EXPECTED_PERMS[@]}"; do
        [[ -d "$d" ]] || continue
        local mode expected
        mode=$(stat -c '%a' "$d")
        expected="${EXPECTED_PERMS[$d]}"
        if [[ "$mode" != "$expected" ]]; then
            if [[ "$fix" -eq 1 ]]; then
                printf '   WARN: %s has mode %s, expected %s — fixing!\n' "$d" "$mode" "$expected"
                chmod "$expected" "$d"
            else
                printf '   WARN: %s has mode %s, expected %s\n' "$d" "$mode" "$expected"
            fi
            bad=1
        else
            printf '   OK: %s %s\n' "$d" "$mode"
        fi
    done

    if [[ "$bad" -eq 1 && "$fix" -eq 0 ]]; then
        echo "Permission anomalies detected. Run 'gitpkg verify --fix' to repair."
    elif [[ "$bad" -eq 1 && "$fix" -eq 1 ]]; then
        echo "Permission anomalies were repaired."
    fi

    return "$bad"
}

# ── Inspect Makefile ──────────────────────────────────────

_show_makefile() {
    local makefile="$1"
    [[ -f "$makefile" ]] || die "no Makefile found"

    if [[ -t 1 ]]; then
        _strip_escape_sequences < "$makefile" | ${PAGER:-less}
    else
        echo "── Makefile ────────────────────────────────────────────────"
        _strip_escape_sequences < "$makefile"
        echo "────────────────────────────────────────────────────────────"
    fi
}
