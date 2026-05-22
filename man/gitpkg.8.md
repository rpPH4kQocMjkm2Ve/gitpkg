---
title: GITPKG
section: 8
header: System Administration
footer: gitpkg
---

# NAME

gitpkg — minimal package manager for git + make projects

# SYNOPSIS

**gitpkg** *command* [*options*] [*args*]

# DESCRIPTION

**gitpkg** is a repo-agnostic package manager that clones git repositories,
builds and installs their contents with **make**(1), and tracks installed
files. Build and install steps run inside a **bubblewrap**(1) sandbox with
PID, UTS, and IPC namespaces isolated and system directories read-only.

Packages can be installed by name (resolved from configured source URLs) or
by providing a direct git URL. When installing by name, **gitpkg** constructs
clone URLs from each configured source as *base_url/package_name* and tries
them in order. If the standalone repo is not found, it searches configured
collection repositories (a single git repo containing multiple packages as
subdirectories).

Before installation, the Makefile is displayed for review. If
*/etc/gitpkg/allowed_signers* or *signers.conf* contains SSH public keys,
**gitpkg** requires valid commit signatures for install and update.

Packages installed by direct URL remember their source and update from the
same URL.

# COMMANDS

**install** [*options*] <*name*|*url*> [*name*|*url*...]
:   Clone, build, and install one or more packages. Accepts package names
    (resolved from configured sources) or direct git URLs (*https://*,
    *http://*, *ssh://*, *git://*, *git@*, *file://*). Requires root.

**update** [*options*] [*name*...]
:   Update one or more packages to the latest commit. When called without
    arguments, updates all installed packages. Requires root.

**remove** [*options*] <*name*> [*name*...]
:   Uninstall and remove source for one or more packages. Each package is
    confirmed individually unless **-y** is given. Requires root.

**list**
:   List installed packages with their commit hashes and collection markers.

**status**
:   Check each installed package for upstream updates. Uses **git
    ls-remote**(1) to compare local and remote HEAD commits.

**files** <*name*>
:   List files tracked by an installed package.

**inspect** <*name*> [*url*]
:   Display the Makefile of a package before installing. Can fetch from a
    remote URL, cached source, or collection.

**verify** [**--fix**] [*name*]
:   Without arguments, verify system directory permissions. When a package
    *name* is given, verify its checksums and file integrity.

**search** <*query*>
:   Search known packages (from *pkglist*) and cached collections.

**repo-add** <*base_url*>
:   Add a package source URL. Requires root.

**repo-del** <*base_url*>
:   Remove a package source URL. Requires root.

**repo-list**
:   List configured package sources (user repos and default mirrorlist).

**collection-add** <*name*>
:   Register a collection repository. Requires root.

**collection-del** <*name*>
:   Unregister a collection repository. Requires root.

**collection-list**
:   List configured collections (user and default).

**signer-add** <*principal*> <*ssh-pubkey*>
:   Add a trusted SSH signing key. Requires root.

**signer-del** <*principal*>
:   Remove a trusted SSH signing key. Requires root.

**signer-list**
:   List trusted SSH signing keys (user and default keyring).

# OPTIONS

**-n**, **--dry-run**
:   Show what would be done without making changes. Applies to **install**,
    **update**, and **remove**.

**-y**, **--yes**
:   Skip confirmation prompts. Applies to **remove**.

**--skip-inspect**
:   Skip Makefile review and confirmation. Applies to **install** and
    **update**.

**--needed**
:   Do not reinstall packages that are already installed. Applies to
    **install**.

**--nodeps**
:   Skip dependency checks. Applies to **install**, **update**, and
    **remove**.

**--nosig**
:   Skip commit signature verification. Applies to **install** and
    **update**.

**--fix**
:   Auto-repair permission anomalies found by **verify**.

**--clone-timeout** <*seconds*>
:   Clone timeout in seconds (default: 120). Overrides *CLONE_TIMEOUT* from
    **gitpkg.conf**(5). Applies to **install** and **update**.

**--fetch-timeout** <*seconds*>
:   Fetch timeout in seconds (default: 30). Overrides *FETCH_TIMEOUT* from
    **gitpkg.conf**(5). Applies to **install** and **update**.

**--status-timeout** <*seconds*>
:   Status check timeout in seconds (default: 15). Overrides
    *STATUS_TIMEOUT* from **gitpkg.conf**(5). Applies to **status**.

**-h**, **--help**
:   Show usage summary and exit.

**-V**, **--version**
:   Show version and exit.

# CONFIGURATION

**gitpkg** can be configured via */etc/gitpkg/gitpkg.conf*. Values set in the
config file can be overridden by command-line flags. The file format is
*KEY=VALUE*, one per line. Lines starting with **#** are ignored.

**CLONE_TIMEOUT**
:   Timeout in seconds for **git clone** operations. Default: **120**.

**FETCH_TIMEOUT**
:   Timeout in seconds for **git fetch** operations. Default: **30**.

**STATUS_TIMEOUT**
:   Timeout in seconds for **git ls-remote** status checks. Default: **15**.

# SIGNATURE VERIFICATION

If */etc/gitpkg/allowed_signers* or */etc/gitpkg/signers.conf* contains SSH
public keys, **gitpkg** requires valid commit signatures for install and
update operations. Unsigned or untrusted commits are rejected.

Default keys ship in */etc/gitpkg/allowed_signers*. User keys are managed
with the **signer-add** and **signer-del** commands.

Use **--nosig** to bypass signature verification.

# COLLECTIONS

A collection is a single git repository containing multiple packages as
subdirectories, each with its own Makefile:

    packages/
    ├── foo/
    │   └── Makefile
    ├── bar/
    │   └── Makefile
    └── baz/
        └── Makefile

When installing a package, **gitpkg** first tries standalone repos, then
searches all configured collections. Default collections are listed in
*/etc/gitpkg/collections*. User collections are managed with the
**collection-add** and **collection-del** commands.

During updates, **gitpkg** detects whether only the package's subdirectory
changed within the collection and skips rebuilds when unnecessary.

# DEPENDENCY CHECK

Packages may include a *depends* file listing dependencies:

- **gitpkg**:*name* — checked via */var/lib/gitpkg/<name>/*
- **system**:*name* — checked via **command -v**(1) or **pacman -Qq**

Use **--nodeps** to skip the dependency check.

# BACKUP FILES

Packages may include a *backup* file listing configuration paths that should
be preserved on removal and handled carefully on update. Paths are relative
without leading **/**.

| Scenario | Result |
|---|---|
| Remove | File stays on disk |
| Update, user didn't edit config | Overwritten with new version |
| Update, user edited config | New version saved as *path*.gitpkg.new |
| First install | Installed normally |

# FILES

*/etc/gitpkg/gitpkg.conf*
:   Timeout configuration file. See **CONFIGURATION** above.

*/etc/gitpkg/repos.conf*
:   User-added package source URLs.

*/etc/gitpkg/mirrorlist*
:   Default package source URLs (shipped with the package).

*/etc/gitpkg/pkglist*
:   Known packages for search and tab completion.

*/etc/gitpkg/collections*
:   Default collection names (shipped with the package).

*/etc/gitpkg/collections.conf*
:   User-added collection names.

*/etc/gitpkg/allowed_signers*
:   Default trusted SSH signing keys (shipped with the package).

*/etc/gitpkg/signers.conf*
:   User-added trusted SSH signing keys.

*/var/lib/gitpkg/<name>/*
:   Package metadata: installed files, commit hash, source URLs, checksums,
    collection marker, backup file list, and dependency list.

*/var/cache/gitpkg/<name>/*
:   Cloned source trees for standalone packages.

*/var/cache/gitpkg/_collections/<name>/*
:   Cloned collection repositories.

*/run/gitpkg/gitpkg.lock*
:   Exclusive lock file preventing concurrent operations.

# EXIT STATUS

**0**
:   Success.

**1**
:   Error. Common causes: missing dependencies, invalid arguments, network
    failure, build failure, lock held by another instance, unsigned commit.

# EXAMPLES

Install a package by name:

    sudo gitpkg install myapp

Install multiple packages by name:

    sudo gitpkg install myapp mylib mytool

Install a package directly from a git URL:

    sudo gitpkg install https://github.com/user/repo

Install packages by name and URL in a single command:

    sudo gitpkg install myapp https://github.com/user/tool

Install without re-installing already up-to-date packages:

    sudo gitpkg install --needed myapp mylib

Install without Makefile review:

    sudo gitpkg install --skip-inspect myapp

Update all packages:

    sudo gitpkg update

Update specific packages:

    sudo gitpkg update myapp mylib

Preview an update:

    sudo gitpkg update -n myapp

Remove a package:

    sudo gitpkg remove myapp

Remove multiple packages:

    sudo gitpkg remove myapp mylib mytool -y

Remove without dependency check:

    sudo gitpkg remove --nodeps myapp

List installed packages:

    gitpkg list

Check for updates:

    gitpkg status

Inspect a Makefile before installing:

    gitpkg inspect myapp

Verify package integrity:

    sudo gitpkg verify myapp

Search for packages:

    gitpkg search myapp

Add a package source:

    sudo gitpkg repo-add https://github.com/username

# SEE ALSO

**gitpkg.conf**(5), **bubblewrap**(1), **git**(1), **make**(1),
**ssh-keygen**(1)
