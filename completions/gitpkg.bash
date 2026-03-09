# bash completion for gitpkg

_gitpkg() {
    local cur prev words cword
    _init_completion || return

    local commands="install update remove list status files inspect verify repo-add repo-del repo-list collection-add collection-del collection-list search"

    local cmd="" i
    for ((i = 1; i < cword; i++)); do
        case "${words[i]}" in
            -*)  continue ;;
            *)   cmd="${words[i]}"; break ;;
        esac
    done

    if [[ -z "$cmd" ]]; then
        if [[ "$cur" == -* ]]; then
            COMPREPLY=($(compgen -W "-h --help -V --version" -- "$cur"))
        else
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        fi
        return
    fi

    # Installed packages
    local -a pkgs=()
    local d name
    for d in /var/lib/gitpkg/*/; do
        [[ -d "$d" ]] || continue
        name="${d%/}"; name="${name##*/}"
        pkgs+=("$name")
    done

    # Known packages from pkglist
    local -a known=()
    if [[ -f /etc/gitpkg/pkglist ]]; then
        while IFS='|' read -r pname _; do
            [[ -n "$pname" && "$pname" != \#* ]] && known+=("$pname")
        done < /etc/gitpkg/pkglist
    fi

    # Packages from cached collections
    local subdir d name
    for d in /var/cache/gitpkg/_collections/*/; do
        [[ -d "$d" ]] || continue
        for subdir in "$d"*/; do
            [[ -f "${subdir}Makefile" ]] || continue
            name="${subdir%/}"; name="${name##*/}"
            known+=("$name")
        done
    done

    # Configured repo URLs
    local -a repo_urls=()
    if [[ -f /etc/gitpkg/repos.conf ]]; then
        while IFS= read -r line; do
            [[ -n "$line" && "$line" != \#* ]] && repo_urls+=("$line")
        done < /etc/gitpkg/repos.conf
    fi

    # Configured collection names
    local -a coll_names=()
    local _cfile
    for _cfile in /etc/gitpkg/collections.conf /etc/gitpkg/collections; do
        [[ -f "$_cfile" ]] || continue
        while IFS= read -r line; do
            [[ -n "$line" && "$line" != \#* ]] && coll_names+=("$line")
        done < "$_cfile"
    done

    case "$cmd" in
        install)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-n --dry-run --skip-inspect --needed --nodeps" -- "$cur"))
            else
                local -a all=($(printf '%s\n' "${known[@]}" "${pkgs[@]}" | sort -u))
                COMPREPLY=($(compgen -W "${all[*]}" -- "$cur"))
            fi
            ;;
        update)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-n --dry-run --nodeps" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "${pkgs[*]}" -- "$cur"))
            fi
            ;;
        remove)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-n --dry-run -y --yes" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "${pkgs[*]}" -- "$cur"))
            fi
            ;;
        files)
            if [[ "$cur" != -* ]]; then
                COMPREPLY=($(compgen -W "${pkgs[*]}" -- "$cur"))
            fi
            ;;
        inspect)
            if [[ "$cur" != -* ]]; then
                local -a all=($(printf '%s\n' "${known[@]}" "${pkgs[@]}" | sort -u))
                COMPREPLY=($(compgen -W "${all[*]}" -- "$cur"))
            fi
            ;;
        verify)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--fix" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "${pkgs[*]}" -- "$cur"))
            fi
            ;;
        repo-del)
            if [[ "$cur" != -* ]]; then
                COMPREPLY=($(compgen -W "${repo_urls[*]}" -- "$cur"))
            fi
            ;;
        collection-del)
            if [[ "$cur" != -* ]]; then
                COMPREPLY=($(compgen -W "${coll_names[*]}" -- "$cur"))
            fi
            ;;
        search)
            # Free-text, no completion
            ;;
    esac
}

complete -F _gitpkg gitpkg
