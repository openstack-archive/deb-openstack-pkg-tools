# -*- Makefile -*-, you silly Emacs!
# vim: set ft=make:

DEBVERS		?= $(shell dpkg-parsechangelog | sed -n -e 's/^Version: //p')
VERSION		?= $(shell echo '$(DEBVERS)' | sed -e 's/^[[:digit:]]*://' -e 's/[-].*//')
DEBFLAVOR	?= $(shell dpkg-parsechangelog | grep -E ^Distribution: | cut -d" " -f2)
DEBPKGNAME	?= $(shell dpkg-parsechangelog | grep -E ^Source: | cut -d" " -f2)
UPSTREAM_GIT	?= git://github.com/openstack/$(DEBPKGNAME).git
GIT_TAG		?= $(shell echo '$(VERSION)' | sed -e 's/~/_/')
MANIFEST_EXCLUDE_STANDARD ?= $(DEBPKGNAME)
DEBIAN_BRANCH	?= $(shell cat debian/gbp.conf | grep debian-branch | cut -d'=' -f2 | awk '{print $1}')

gen-init-configurations:
	# Create the init scripts and systemd unit files from the template
	set -e ; set -x ; for i in `ls -1 debian/*.init.in` ; do \
		MYINIT=`echo $$i | sed s/.init.in//` ; \
		cp $$i $$MYINIT.init ; \
		cat /usr/share/openstack-pkg-tools/init-script-template >>$$MYINIT.init ; \
		pkgos-gen-systemd-unit $$i ; \
	done
	# If there's an upstart.in file, use that one instead of the generated one
	set -e ; set -x ; for i in `ls -1 debian/*.upstart.in` ; do \
		MYPKG=`echo $$i | sed s/.upstart.in//` ; \
		cp $$MYPKG.upstart.in $$MYPKG.upstart ; \
	done
	# Generate the upstart job if there's no already existing .upstart.in
	set -e ; set -x ; for i in `ls debian/*.init.in` ; do \
		MYINIT=`echo $$i | sed s/.init.in/.upstart.in/` ; \
		if ! [ -e $$MYINIT ] ; then \
			pkgos-gen-upstart-job $$i ; \
		fi \
	done
	# If there's a service.in file, use that one instead of the generated one
	set -e ; set -x ; for i in `ls -1 debian/*.service.in`; do \
		MYPKG=`echo $$i | sed s/.service.in//` ; \
		cp $$MYPKG.service.in $$MYPKG.service ; \
	done
	# Generate the systemd unit if there's no already existing .service.in
	set -e ; set -x ; for i in `ls debian/*.init.in` ; do \
		MYINIT=`echo $$i | sed s/.init.in/.service.in/` ; \
		if ! [ -e $$MYINIT ] ; then \
			pkgos-gen-systemd-unit $$i ; \
		fi \
	done

override_dh_systemd_enable: gen-init-configurations
	dh_systemd_enable

override_dh_installinit: gen-init-configurations
	dh_installinit --error-handler=true

gen-author-list:
	git log --format='%aN <%aE>' | awk '{arr[$$0]++} END{for (i in arr){print arr[i], i;}}' | sort -rn | cut -d' ' -f2-

gen-upstream-changelog:
	git checkout master || git checkout upstream/master
	git reset --hard $(GIT_TAG)
	git log >$(CURDIR)/../CHANGELOG
	git checkout debian/$(DEBFLAVOR)
	mv $(CURDIR)/../CHANGELOG $(CURDIR)/debian/CHANGELOG
	git add $(CURDIR)/debian/CHANGELOG
	git commit -a -m "Updated upstream changelog"

override_dh_installchangelogs:
	if [ -e $(CURDIR)/debian/CHANGELOG ] ; then \
		dh_installchangelogs $(CURDIR)/debian/CHANGELOG ; \
	else \
		dh_installchangelogs ; \
	fi

get-orig-source:
	uscan --verbose --force-download --rename --destdir=../build-area

fetch-upstream-remote:
	git remote add upstream $(UPSTREAM_GIT) || true
	git fetch upstream

gen-orig-xz:
	git tag -v $(GIT_TAG) || true
	if [ ! -f ../$(DEBPKGNAME)_$(VERSION).orig.tar.xz ] ; then \
		git archive --prefix=$(DEBPKGNAME)-$(VERSION)/ $(GIT_TAG) | xz >../$(DEBPKGNAME)_$(VERSION).orig.tar.xz ; \
	fi
	[ ! -e ../build-area ] && mkdir ../build-area || true
	[ ! -e ../build-area/$(DEBPKGNAME)_$(VERSION).orig.tar.xz ] && cp ../$(DEBPKGNAME)_$(VERSION).orig.tar.xz ../build-area

gen-orig-gz:
	git tag -v $(GIT_TAG) || true
	if [ ! -f ../$(DEBPKGNAME)_$(VERSION).orig.tar.gz ] ; then \
		git archive --prefix=$(DEBPKGNAME)-$(VERSION)/ $(GIT_TAG) | gzip >../$(DEBPKGNAME)_$(VERSION).orig.tar.gz ; \
	fi
	[ ! -e ../build-area ] && mkdir ../build-area || true
	[ ! -e ../build-area/$(DEBPKGNAME)_$(VERSION).orig.tar.gz ] && cp ../$(DEBPKGNAME)_$(VERSION).orig.tar.gz ../build-area

gen-orig-bz2:
	git tag -v $(GIT_TAG) || true
	if [ ! -f ../$(DEBPKGNAME)_$(VERSION).orig.tar.bz2 ] ; then \
		git archive --prefix=$(DEBPKGNAME)-$(VERSION)/ $(GIT_TAG) | bzip2 >../$(DEBPKGNAME)_$(VERSION).orig.tar.bz2 ; \
	fi
	[ ! -e ../build-area ] && mkdir ../build-area || true
	[ ! -e ../build-area/$(DEBPKGNAME)_$(VERSION).orig.tar.bz2 ] && cp ../$(DEBPKGNAME)_$(VERSION).orig.tar.bz2 ../build-area

get-master-branch:
	if ! git checkout master ; then \
		echo "No upstream branch: checking out" ; \
		git checkout -b master upstream/master ; \
	fi
	git checkout $(DEBIAN_BRANCH)

get-vcs-source:
	$(CURDIR)/debian/rules fetch-upstream-remote
	$(CURDIR)/debian/rules gen-orig-xz
	$(CURDIR)/debian/rules get-master-branch

versioninfo:
	echo $(VERSION) > versioninfo

display-po-stats:
	cd $(CURDIR)/debian/po ; for i in *.po ; do \
		echo -n $$i": " ; \
		msgfmt -o /dev/null --statistic $$i ; \
	done

call-for-po-trans:
	podebconf-report-po --call --withtranslators --languageteam

regen-manifest-patch:
	quilt pop -a || true
	quilt push install-missing-files.patch
	git checkout MANIFEST.in
	git ls-files --no-empty-directory --exclude-standard $(MANIFEST_EXCLUDE_STANDARD) | grep -v '.py$$' | grep -v LICENSE | sed -n 's/.*/include &/gp' >> MANIFEST.in
	quilt refresh
	quilt pop -a

override_dh_gencontrol:
	if dpkg-vendor --derives-from ubuntu ; then \
		dh_gencontrol -- -T$(CURDIR)/debian/ubuntu_control_vars ; \
	else \
		dh_gencontrol -- -T$(CURDIR)/debian/debian_control_vars ; \
	fi

.PHONY: get-vcs-source get-orig-source override_dh_installinit regen-manifest-patch call-for-po-trans display-po-stats versioninfo
