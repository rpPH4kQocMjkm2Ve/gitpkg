PREFIX    = /usr
DESTDIR   =

install:
	install -Dm755 gitpkg $(DESTDIR)$(PREFIX)/bin/gitpkg
	install -Dm644 lib/common.sh  $(DESTDIR)$(PREFIX)/lib/gitpkg/common.sh
	install -Dm644 lib/sandbox.sh $(DESTDIR)$(PREFIX)/lib/gitpkg/sandbox.sh
	install -Dm644 lib/package.sh $(DESTDIR)$(PREFIX)/lib/gitpkg/package.sh
	install -Dm644 completions/_gitpkg $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_gitpkg
	install -Dm644 completions/gitpkg.bash $(DESTDIR)$(PREFIX)/share/bash-completion/completions/gitpkg
	install -Dm644 mirrorlist $(DESTDIR)/etc/gitpkg/mirrorlist
	install -Dm644 pkglist $(DESTDIR)/etc/gitpkg/pkglist
	install -Dm644 collections $(DESTDIR)/etc/gitpkg/collections
	install -Dm644 allowed_signers $(DESTDIR)/etc/gitpkg/allowed_signers
	install -Dm644 gitpkg.conf $(DESTDIR)/etc/gitpkg/gitpkg.conf

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/gitpkg
	rm -rf $(DESTDIR)$(PREFIX)/lib/gitpkg
	rm -f $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_gitpkg
	rm -f $(DESTDIR)$(PREFIX)/share/bash-completion/completions/gitpkg
	rm -f $(DESTDIR)/etc/gitpkg/mirrorlist
	rm -f $(DESTDIR)/etc/gitpkg/pkglist
	rm -f $(DESTDIR)/etc/gitpkg/collections
	rm -f $(DESTDIR)/etc/gitpkg/allowed_signers
	rm -f $(DESTDIR)/etc/gitpkg/gitpkg.conf
