PREFIX    = /usr
DESTDIR   =

install:
	install -Dm755 gitpkg $(DESTDIR)$(PREFIX)/bin/gitpkg
	install -Dm644 completions/_gitpkg $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_gitpkg
	install -Dm644 completions/gitpkg.bash $(DESTDIR)$(PREFIX)/share/bash-completion/completions/gitpkg
	install -Dm644 mirrorlist $(DESTDIR)/etc/gitpkg/mirrorlist
	install -Dm644 pkglist $(DESTDIR)/etc/gitpkg/pkglist

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/gitpkg
	rm -f $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_gitpkg
	rm -f $(DESTDIR)$(PREFIX)/share/bash-completion/completions/gitpkg
	rm -f $(DESTDIR)/etc/gitpkg/mirrorlist
	rm -f $(DESTDIR)/etc/gitpkg/pkglist
