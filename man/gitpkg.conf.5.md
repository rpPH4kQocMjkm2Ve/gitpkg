---
title: GITPKG.CONF
section: 5
header: File Formats
footer: gitpkg
---

# NAME

gitpkg.conf — configuration file for gitpkg

# SYNOPSIS

*/etc/gitpkg/gitpkg.conf*

# DESCRIPTION

**gitpkg.conf** is the configuration file for **gitpkg**(8). It is read on
every invocation. Changes take effect immediately without restarting any
service.

The file format is *KEY=VALUE*, one per line. Lines starting with **#** are
ignored. Values must be numeric. Values set in the config file can be
overridden by command-line flags.

Only allowed keys are accepted. Unknown keys produce a warning on stderr
and are ignored.

The file must be owned by root (uid 0); otherwise it is rejected entirely.

# OPTIONS

**CLONE_TIMEOUT**
:   Timeout in seconds for **git clone** operations. Overridden by
    **\--clone-timeout** flag. Default: **120**.

**FETCH_TIMEOUT**
:   Timeout in seconds for **git fetch** operations. Overridden by
    **\--fetch-timeout** flag. Default: **30**.

**STATUS_TIMEOUT**
:   Timeout in seconds for **git ls-remote** status checks. Overridden by
    **\--status-timeout** flag. Default: **15**.

# SECURITY

The configuration file must be owned by root when at */etc/gitpkg/gitpkg.conf*.
If the file is owned by another user, it is rejected and no values are loaded.

Only the keys listed above are accepted. Attempts to set arbitrary shell
variables via the config file are silently ignored. The file is parsed
line-by-line with a safe parser — it is never sourced or evaluated as shell
code.

# EXAMPLES

Default configuration (all values commented out):

    # /etc/gitpkg/gitpkg.conf
    #CLONE_TIMEOUT=120
    #FETCH_TIMEOUT=30
    #STATUS_TIMEOUT=15

Set longer clone timeout for slow networks:

    CLONE_TIMEOUT=300

Faster status checks:

    STATUS_TIMEOUT=5

# SEE ALSO

**gitpkg**(8), **git-clone**(1), **git-fetch**(1), **git-ls-remote**(1)
