.PHONY: install uninstall reinstall install-conf test test-root

PREFIX     = /usr
SYSCONFDIR = /etc
DESTDIR    =
pkgname    = gitpkg

BINDIR       = $(PREFIX)/bin
LIBDIR       = $(PREFIX)/lib/$(pkgname)
SHAREDIR     = $(PREFIX)/share
ZSH_COMPDIR  = $(SHAREDIR)/zsh/site-functions
BASH_COMPDIR = $(SHAREDIR)/bash-completion/completions
CONFDIR      = $(SYSCONFDIR)/$(pkgname)
LICENSEDIR   = $(SHAREDIR)/licenses/$(pkgname)

install:
	install -Dm755 gitpkg $(DESTDIR)$(BINDIR)/gitpkg

	install -Dm644 lib/common.sh  $(DESTDIR)$(LIBDIR)/common.sh
	install -Dm644 lib/sandbox.sh $(DESTDIR)$(LIBDIR)/sandbox.sh
	install -Dm644 lib/package.sh $(DESTDIR)$(LIBDIR)/package.sh

	install -Dm644 completions/_gitpkg \
		$(DESTDIR)$(ZSH_COMPDIR)/_gitpkg
	install -Dm644 completions/gitpkg.bash \
		$(DESTDIR)$(BASH_COMPDIR)/gitpkg

	install -Dm644 LICENSE $(DESTDIR)$(LICENSEDIR)/LICENSE

	@for f in mirrorlist pkglist collections allowed_signers gitpkg.conf; do \
		if [ ! -f "$(DESTDIR)$(CONFDIR)/$$f" ]; then \
			install -Dm644 "etc/gitpkg/$$f" "$(DESTDIR)$(CONFDIR)/$$f"; \
			echo "Installed default config: $$f"; \
		else \
			echo "Config exists, skipping: $$f"; \
		fi; \
	done

uninstall:
	rm -f  $(DESTDIR)$(BINDIR)/gitpkg
	rm -rf $(DESTDIR)$(LIBDIR)/
	rm -f  $(DESTDIR)$(ZSH_COMPDIR)/_gitpkg
	rm -f  $(DESTDIR)$(BASH_COMPDIR)/gitpkg
	rm -rf $(DESTDIR)$(LICENSEDIR)/
	@echo "Note: $(CONFDIR)/ preserved. Remove manually if needed."

reinstall: uninstall install

install-conf:
	@for f in mirrorlist pkglist collections allowed_signers gitpkg.conf; do \
		install -Dm644 "etc/gitpkg/$$f" "$(DESTDIR)$(CONFDIR)/$$f"; \
	done
	@echo "All configs force-installed."

test:
	bash tests/test.sh

test-root:
	sudo bash tests/test_integration.sh
