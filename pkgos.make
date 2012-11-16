# -*- Makefile -*-, you silly Emacs!
# vim: set ft=make:

DEBVERS		?= $(shell dpkg-parsechangelog | sed -n -e 's/^Version: //p')
VERSION		?= $(shell echo '$(DEBVERS)' | sed -e 's/^[[:digit:]]*://' -e 's/[~-].*//')
DEBFLAVOR	?= $(shell dpkg-parsechangelog | grep -E ^Distribution: | cut -d" " -f2)
DEBPKGNAME	?= $(shell dpkg-parsechangelog | grep -E ^Source: | cut -d" " -f2)
UPSTREAM_GIT	?= git://github.com/openstack/$(DEBPKGNAME).git

test:
	echo $(UPSTREAM_GIT)

get-vcs-source:
	git remote add upstream $(UPSTREAM_GIT) || true
	git fetch upstream
	if [ ! -f ../$(DEBPKGNAME)_$(VERSION).orig.tar.xz ] ; then \
		git archive --prefix=$(DEBPKGNAME)-$(VERSION)/ $(VERSION) | xz >../$(DEBPKGNAME)_$(VERSION).orig.tar.xz ; \
	fi
	if ! git checkout master ; then \
		echo "No upstream branch: checking out" ; \
		git checkout -b master upstream/master ; \
	fi
	git checkout debian/experimental

.PHONY: get-vcs-source
