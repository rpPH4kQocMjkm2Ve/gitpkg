# gitpkg

Minimal package manager for git + make projects. Repo-agnostic.

## Why

Nobody uses my software anyway, and maintaining AUR packages is tedious — so this happened.
Each project is just a repo with a Makefile, `gitpkg install` — done.

## Install

### Arch Linux (AUR)

```
yay -S gitpkg
```

### Manual

```
sudo make install
```

### Uninstall

```
sudo make uninstall
```
## How it works

```
gitpkg install <name>...

1. Constructs clone URLs from configured sources:
   https://gitlab.com/user/<name>
   https://github.com/user/<name>
   ...

2. Tries standalone repo first; if not found, searches collections
3. Clones the first source that succeeds
4. Shows the Makefile for review
5. Runs: make build (sandboxed via bubblewrap)
6. Runs: make install DESTDIR=<staging> (sandboxed)
7. Validates staged files (path traversal, symlinks)
8. Deploys files to /
9. Records checksums for integrity verification
10. Tracks installed files in /var/lib/gitpkg/<name>/
```

## Collections

A collection is a single git repository containing multiple packages
as subdirectories, each with its own Makefile:

```
packages/
├── foo/
│   └── Makefile
├── bar/
│   └── Makefile
└── baz/
    └── Makefile
```

When installing a package, gitpkg first tries standalone repos,
then searches all configured collections.

Default collections are listed in `/etc/gitpkg/collections`.
User collections can be managed with:

```
sudo gitpkg collection-add <name>
sudo gitpkg collection-del <name>
gitpkg collection-list
```

During updates, gitpkg detects whether only the package's subdirectory
changed within the collection and skips rebuilds when unnecessary.

## Security

**gitpkg runs `make` from the cloned repository.**

Build and install steps run inside a bubblewrap sandbox with
PID/UTS/IPC namespaces isolated and system directories read-only.
DESTDIR is enforced at filesystem level — installed files are
staged, validated for path traversal and symlink attacks, then deployed.

Before installation, the Makefile is displayed for review.
You can also inspect it beforehand:

```
gitpkg inspect <name>
gitpkg inspect <name> <url>
```

**Always review the Makefile before confirming installation.**

During updates, if the Makefile has changed, the diff is shown
for review before proceeding.

Use `--skip-inspect` to bypass Makefile review during install and update.

## Coexistence with system package managers

gitpkg checks whether a package is already managed by pacman, dpkg, or rpm
before installing, updating, or removing. If a conflict is detected, the
operation is refused with a message to use the system package manager instead.

This prevents file conflicts when the same software is available both
as a gitpkg package and as a system/AUR package.

## Dependencies

- `bash`, `git`, `make`, `find`, `awk`, `sha256sum`, `timeout`
- `bubblewrap` (`bwrap`)
- [`verify-lib`](https://gitlab.com/fkzys/verify-lib)

## Package requirements

Packages must have a `Makefile` with:

- `install` target (required) — must respect `DESTDIR`
- `build` target (optional) — runs sandboxed

Example:

```makefile
PREFIX = /usr
DESTDIR =

build:
    # compile step

install:
    install -Dm755 myapp $(DESTDIR)$(PREFIX)/bin/myapp
```

### Dependency file

Packages may include a `depends` file listing dependencies.
gitpkg checks it before building and warns about missing ones.

Format:

```
# gitpkg packages (checked via /var/lib/gitpkg/<name>/)
gitpkg:some-lib

# system packages (checked via command -v or pacman -Qq)
system:gcc
system:ffmpeg
```

Use `--nodeps` to skip the check.

### Backup file

Packages may include a `backup` file listing paths that should be
preserved on removal and handled carefully on update. Paths are
relative, without leading `/`.

Example `backup`:

```
etc/myapp.conf
```

Behavior:

| Scenario | Result |
|----------|--------|
| Remove | File stays on disk |
| Update, user didn't edit config | Overwritten with new version |
| Update, user edited config | New version saved as `<path>.gitpkg.new` |
| First install | Installed normally |

## Usage

```
gitpkg install [--needed] [--nodeps] [--skip-inspect] <name>...
gitpkg update [--nodeps] [--skip-inspect] [name...]
gitpkg remove [--nodeps] <name>
gitpkg list
gitpkg status
gitpkg files <name>
gitpkg inspect <name> [url]
gitpkg verify [--fix] [name]
sudo gitpkg repo-add <base_url>
sudo gitpkg repo-del <base_url>
gitpkg repo-list
sudo gitpkg collection-add <name>
sudo gitpkg collection-del <name>
gitpkg collection-list
gitpkg search <query>
```

## Environment

| Variable | Default | Effect |
|----------|---------|--------|
| `GITPKG_CLONE_TIMEOUT` | 120 | Clone timeout in seconds |
| `GITPKG_FETCH_TIMEOUT` | 30 | Fetch timeout in seconds |
| `GITPKG_LSREMOTE_TIMEOUT` | 15 | Status check timeout in seconds |

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
| `/usr/bin/gitpkg` | Main script — CLI, help, command dispatch |
| `/usr/lib/gitpkg/common.sh` | Constants, validation, locking, utility helpers |
| `/usr/lib/gitpkg/sandbox.sh` | Bubblewrap build isolation |
| `/usr/lib/gitpkg/package.sh` | URL resolution, cloning, staging, deploy, verification |
| `/etc/gitpkg/repos.conf` | User-added sources |
| `/etc/gitpkg/mirrorlist` | Default sources (shipped) |
| `/etc/gitpkg/pkglist` | Known packages for search/completion |
| `/etc/gitpkg/collections` | Default collection names (shipped) |
| `/etc/gitpkg/collections.conf` | User-added collections |
| `/var/lib/gitpkg/<name>/` | Package metadata (files, commit, urls, checksums, collection, backup, backup_checksums, depends) |
| `/var/cache/gitpkg/<name>/` | Cloned source trees (standalone) |
| `/var/cache/gitpkg/_collections/<name>/` | Cloned collection repositories |

## Options

| Flag | Commands | Effect |
|------|----------|--------|
| `-n, --dry-run` | install, update, remove | Show what would be done |
| `-y, --yes` | remove | Skip confirmation |
| `--skip-inspect` | install, update | Skip Makefile review and confirmation |
| `--fix` | verify | Auto-repair permissions |
| `--needed` | install | Do not reinstall up to date packages |
| `--nodeps` | install, update, remove | Skip dependency check |

## License

AGPL-3.0-or-later
