# /usr/lib/gitpkg/sandbox.sh — bubblewrap build isolation

_build_bwrap_args() {
    local -a args=(
        --die-with-parent
        --new-session
        --unshare-pid
        --unshare-uts
        --unshare-ipc
        --clearenv
        --setenv PATH "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        --setenv HOME "${HOME}"
        --setenv TERM "dumb"
    )

    [[ -d /usr ]] && args+=(--ro-bind /usr /usr)

    local d
    for d in /bin /lib /lib64 /lib32 /sbin; do
        if [[ -L "$d" ]]; then
            args+=(--symlink "$(readlink "$d")" "$d")
        elif [[ -d "$d" ]]; then
            args+=(--ro-bind "$d" "$d")
        fi
    done

    args+=(--proc /proc --dev /dev --tmpfs /tmp --tmpfs /run)
    [[ -d /dev/shm ]] && args+=(--dev-bind /dev/shm /dev/shm)
    [[ -d /sys ]] && args+=(--ro-bind /sys /sys)
    [[ -d /etc ]] && args+=(--ro-bind /etc /etc)

    if [[ -L /etc/resolv.conf ]]; then
        local _resolv_dir
        _resolv_dir="$(dirname "$(realpath /etc/resolv.conf 2>/dev/null)")" || true
        if [[ -n "$_resolv_dir" && "$_resolv_dir" == /run/* && -d "$_resolv_dir" ]]; then
            args+=(--ro-bind "$_resolv_dir" "$_resolv_dir")
        fi
    fi

    printf '%s\0' "${args[@]}"
}

_sandboxed_make() {
    local target="$1"
    local workdir="$2"
    local destdir="${3:-}"

    local -a bwrap_args=()
    while IFS= read -r -d '' arg; do
        bwrap_args+=("$arg")
    done < <(_build_bwrap_args)

    bwrap_args+=(--bind "$workdir" "$workdir")
    [[ -n "$destdir" ]] && bwrap_args+=(--bind "$destdir" "$destdir")

    [[ -n "${MAKEFLAGS:-}" ]] && bwrap_args+=(--setenv MAKEFLAGS "$MAKEFLAGS")

    local cache_home="${HOME}/.cache"
    if [[ -d "$cache_home" ]]; then
        bwrap_args+=(--bind "$cache_home" "$cache_home")
        bwrap_args+=(--setenv XDG_CACHE_HOME "$cache_home")
    fi
    local d
    for d in "${HOME}/.dotnet" "${HOME}/.nuget" "${HOME}/.cargo"; do
        [[ -d "$d" ]] && bwrap_args+=(--bind "$d" "$d")
    done
    if [[ -d "${HOME}/.dotnet" ]]; then
        bwrap_args+=(--setenv DOTNET_CLI_HOME "${HOME}")
        bwrap_args+=(--setenv DOTNET_NOLOGO "1")
        bwrap_args+=(--setenv DOTNET_CLI_TELEMETRY_OPTOUT "1")
    fi

    local -a make_args=(-C "$workdir" "$target")
    [[ -n "$destdir" ]] && make_args+=(DESTDIR="$destdir")

    bwrap "${bwrap_args[@]}" -- make "${make_args[@]}"
}

_has_make_target() {
    local workdir="$1" target="$2"
    grep -q "^${target}[[:space:]]*:" "${workdir}/Makefile" 2>/dev/null
}
