# gitpkg

Minimal package manager for git + make projects. Repo-agnostic.

## How it works

```
gitpkg install <name>...

1. Constructs clone URLs from configured sources:
   https://gitlab.com/user/<name>
   https://github.com/user/<name>
   ...

2. Clones the first that succeeds
3. Shows the Makefile for review
4. Runs: make build (as nobody)
5. Runs: make install DESTDIR=<staging>
6. Deploys files to /
7. Tracks installed files in /var/lib/gitpkg/<name>/
```

## Security

**gitpkg runs `make` from the cloned repository.**

Before installation, the Makefile is displayed for review.
You can also inspect it beforehand:

```
gitpkg inspect <name>
gitpkg inspect <name> <url>
```

**Always review the Makefile before confirming installation.**
gitpkg does not sandbox the build beyond running `make build`
as the `nobody` user. `make install` runs as root.

During updates, if the Makefile has changed, the diff is shown
for review before proceeding.

Use `--skip-inspect` to bypass Makefile review during install and update.

## Install

```
sudo make install
```

## Uninstall

```
sudo make uninstall
```

## Package requirements

Packages must have a `Makefile` with:

- `install` target (required) — must respect `DESTDIR`
- `build` target (optional) — runs as `nobody`

Example:

```makefile
PREFIX = /usr
DESTDIR =

build:
    # compile step

install:
    install -Dm755 myapp $(DESTDIR)$(PREFIX)/bin/myapp
```

## Usage

```
gitpkg install <name>...
gitpkg update [name]
gitpkg remove <name>
gitpkg list
gitpkg status
gitpkg files <name>
gitpkg inspect <name> [url]
gitpkg verify [--fix]
gitpkg repo-add <base_url>
gitpkg repo-del <base_url>
gitpkg repo-list
gitpkg search <query>
```

## Sources

Package sources are base URLs at user/org level:

```
sudo gitpkg repo-add https://github.com/username
sudo gitpkg repo-add https://codeberg.org/username
```

Clone URL is constructed as `base_url/package_name`.
Works with any git hosting.

Default sources are shipped in `/etc/gitpkg/mirrorlist`.
User-added sources are stored in `/etc/gitpkg/repos.conf`.

## Files

| Path | Purpose |
|------|---------|
| `/usr/bin/gitpkg` | Main script |
| `/etc/gitpkg/repos.conf` | User-added sources |
| `/etc/gitpkg/mirrorlist` | Default sources (shipped) |
| `/etc/gitpkg/pkglist` | Known packages for search/completion |
| `/var/lib/gitpkg/<name>/` | Package metadata (files, commit, urls) |
| `/var/cache/gitpkg/<name>/` | Cloned source trees |

## Options

| Flag | Commands | Effect |
|------|----------|--------|
| `-n, --dry-run` | install, update, remove | Show what would be done |
| `-y, --yes` | remove | Skip confirmation |
| `--skip-inspect` | install, update | Skip Makefile review and confirmation |
| `--fix` | verify | Auto-repair permissions |

## License

GPL-3.0
