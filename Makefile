#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright 2022 Joyent, Inc.
# Copyright 2022 MNX Cloud, Inc.
# Copyright 2023 ServerOS.
#

#
# We allow build.env not to exist in case build automation expects to run
# generic 'make check' actions without actually running ./configure in
# advance of a full build.
#
ifeq ($(MAKECMDGOALS),check)
-include build.env
else
include build.env
endif

ROOT =		$(PWD)
PROTO =		$(ROOT)/proto
STRAP_PROTO =	$(ROOT)/proto.strap
MANIFEST_DIR =	$(ROOT)/manifest.d
BOOT_MANIFEST_DIR =	$(ROOT)/boot.manifest.d
BOOT_PROTO =	$(ROOT)/proto.boot
TESTS_PROTO =	$(ROOT)/proto.tests

# On Darwin/OS X we support running 'make check'
ifeq ($(shell uname -s),Darwin)
PATH =		/bin:/usr/bin:/usr/sbin:/sbin:/opt/local/bin
NATIVE_CC =	gcc
else
PATH =		/usr/bin:/usr/sbin:/sbin:/opt/local/bin
NATIVE_CC =	/opt/local/bin/gcc
endif

BUILD_PLATFORM := $(shell uname -v)

#
# This number establishes a maximum for ServerOS, illumos-extra, and
# illumos.  Support for it can and should be added to other projects
# as time allows.  The default value on large (16 GB or more) zones/systems
# is 128; on smaller systems it is 8.  You can override this in the usual way;
# i.e.,
#
# gmake world live MAX_JOBS=32
#
CRIPPLED_HOST :=	$(shell [[ `prtconf -m 2>/dev/null || echo 999999` -lt \
    16384 ]] && echo yes || echo no)
ifeq ($(CRIPPLED_HOST),yes)
MAX_JOBS ?=	8
else
MAX_JOBS ?=	$(shell tools/optimize_jobs)
endif

LOCAL_SUBDIRS :=	$(shell ls projects/local)
PKGSRC =	$(ROOT)/pkgsrc
MANIFEST_FILE =	manifest
BOOT_MANIFEST =	boot.manifest
JSSTYLE =	$(ROOT)/tools/jsstyle/jsstyle
JSLINT =	$(ROOT)/tools/javascriptlint/build/install/jsl
CSTYLE =	$(ROOT)/tools/cstyle
MANCHECK =	$(ROOT)/tools/mancheck/mancheck
MANCF =		$(ROOT)/tools/mancf/mancf
TZCHECK =	$(ROOT)/tools/tzcheck/tzcheck
UCODECHECK =	$(ROOT)/tools/ucodecheck/ucodecheck

CTFBINDIR = \
	$(ROOT)/projects/illumos/usr/src/tools/proto/*/opt/onbld/bin/i386
CTFMERGE =	$(CTFBINDIR)/ctfmerge
CTFCONVERT =	$(CTFBINDIR)/ctfconvert

SUBDIR_DEFS = \
	CTFMERGE=$(CTFMERGE) \
	CTFCONVERT=$(CTFCONVERT) \
	MAX_JOBS=$(MAX_JOBS)

ADJUNCT_TARBALL :=	$(shell ls `pwd`/illumos-adjunct*.tgz 2>/dev/null \
	| tail -n1 && echo $?)

STAMPFILE :=	$(ROOT)/proto/buildstamp

MANCF_FILE :=	$(ROOT)/proto/usr/share/man/man.cf

BASE_MANIFESTS := \
	$(MANIFEST_DIR)/illumos.manifest \
	$(MANIFEST_DIR)/illumos-extra.manifest \
	$(MANIFEST_DIR)/server-os.manifest \
	$(MANIFEST_DIR)/man.manifest \

MANCHECK_CONFS := \
	$(ROOT)/man/mancheck.conf \
	$(ROOT)/projects/illumos/mancheck.conf \
	$(ROOT)/projects/illumos-extra/mancheck.conf \
	$(shell ls projects/local/*/mancheck.conf 2>/dev/null)

BOOT_MANIFESTS := \
	$(BOOT_MANIFEST_DIR)/illumos.manifest

LOCAL_MANIFESTS :=	$(LOCAL_SUBDIRS:%=$(MANIFEST_DIR)/%.manifest)

TEST_IPS_MANIFEST_ROOT = projects/illumos/usr/src/pkg/manifests

#
# To avoid cross-repository flag days, the list of IPS manifest
# files which define the files included in the test archive is
# stored in the illumos.git repository. By including the
# following Makefile, we get the $(TEST_IPS_MANIFEST_FILES) macro.
#
include projects/illumos/usr/src/Makefile.testarchive

TEST_IPS_MANIFESTS = $(TEST_IPS_MANIFEST_FILES:%=$(TEST_IPS_MANIFEST_ROOT)/%)
TESTS_MANIFEST = $(ROOT)/tests.manifest

BOOT_VERSION :=	boot-$(shell [[ -f $(ROOT)/configure-buildver ]] && \
    echo $$(head -n1 $(ROOT)/configure-buildver)-)$(shell head -n1 $(STAMPFILE))
BOOT_TARBALL :=	output/$(BOOT_VERSION).tgz

TESTS_VERSION :=	tests-$(shell [[ -f $(ROOT)/configure-buildver ]] && \
    echo $$(head -n1 $(ROOT)/configure-buildver)-)$(shell head -n1 $(STAMPFILE))
TESTS_TARBALL :=	output/$(TESTS_VERSION).tgz

CTFTOOLS_TARBALL := $(ROOT)/output/ctftools/ctftools.tar.gz

STRAP_CACHE_TARBALL := $(ROOT)/output/strap-cache/proto.tar.gz

ifdef PLATFORM_PASSWORD
PLATFORM_PASSWORD_OPT=-p $(PLATFORM_PASSWORD)
endif

TOOLS_TARGETS = \
	$(MANCHECK) \
	$(MANCF) \
	$(TZCHECK) \
	$(UCODECHECK) \
	tools/cryptpass

world: 0-preflight-stamp 0-strap-stamp 0-illumos-stamp 0-extra-stamp \
	0-livesrc-stamp 0-local-stamp 0-tools-stamp 0-devpro-stamp \
	$(TOOLS_TARGETS)

live: world manifest boot $(TOOLS_TARGETS) $(MANCF_FILE) mancheck
	@echo $(LOCAL_MANIFESTS)
	mkdir -p ${ROOT}/log
	./tools/build_live -m $(ROOT)/$(MANIFEST_FILE) -o $(ROOT)/output \
	    $(PLATFORM_PASSWORD_OPT) $(ROOT)/proto

boot: $(BOOT_TARBALL)

.PHONY: pkgsrc
pkgsrc:
	cd $(PKGSRC) && gmake install

$(BOOT_TARBALL): world manifest
	pfexec rm -rf $(BOOT_PROTO)
	mkdir -p $(BOOT_PROTO)/etc/version/
	mkdir -p $(ROOT)/output
	pfexec ./tools/builder/builder $(ROOT)/$(BOOT_MANIFEST) \
	    $(BOOT_PROTO) $(ROOT)/proto
	cp $(STAMPFILE) $(BOOT_PROTO)/etc/version/boot
	(cd $(BOOT_PROTO) && pfexec gtar czf $(ROOT)/$@ .)

#
# Manifest construction.  
#
# The manifest is a result of combining 5 sources for manifests that are collected
# in the MANIFEST_DIR.
# The illumos manifest is copied from 
# illumos, illumos-extra, and the root of live (covering mainly what's in src).
# Additional manifests come from each of $(LOCAL_SUBDIRS), which may choose
# to construct them programmatically.
#
# These all end up in $(MPROTO), where we tell tools/build_manifest to look;
# it will pick up every file in that directory and treat it as a manifest.
#
# In addition, a separate manifest is generated in similar manner for the
# boot tarball.
#
# Look ma, no for loops in these shell fragments!
#
manifest: $(MANIFEST_FILE) $(BOOT_MANIFEST)

mancheck.conf: $(MANCHECK_CONFS)
	cat $(MANCHECK_CONFS) >$@ 2>/dev/null

.PHONY: mancheck
mancheck: manifest mancheck.conf $(MANCHECK)
	$(MANCHECK) -f manifest -s -c $(ROOT)/mancheck.conf

$(MANIFEST_DIR) $(BOOT_MANIFEST_DIR):
	mkdir -p $@

# copies the illumos manifest file, which is under source control in the illumos repo
$(MANIFEST_DIR)/illumos.manifest: projects/illumos/manifest | $(MANIFEST_DIR)
	cp projects/illumos/manifest $(MANIFEST_DIR)/illumos.manifest

# copies the illumos extra manifest file, which is under source control in the illumos-extra repo
$(MANIFEST_DIR)/illumos-extra.manifest: projects/illumos-extra/manifest | $(MANIFEST_DIR)
	cp projects/illumos-extra/manifest $(MANIFEST_DIR)/illumos-extra.manifest

# copies the ServerOS manifest file, which is under source control as /src/manifest
$(MANIFEST_DIR)/server-os.manifest: src/manifest | $(MANIFEST_DIR)
	cp src/manifest $(MANIFEST_DIR)/server-os.manifest

# copies the man manifest file, which is under source control as /man/manifest
$(MANIFEST_DIR)/man.manifest: man/manifest | $(MANIFEST_DIR)
	cp man/manifest $(MANIFEST_DIR)/man.manifest

# copies the manifest files of the local projects, under source control in the local project repo
$(MANIFEST_DIR)/%.manifest: projects/local/%/manifest
	cd $(ROOT)/projects/local/$* && \
		cp manifest $(MANIFEST_DIR)/$*.manifest \

# copies the illumos boot manifest file, which is under source control in the illumos repo
$(BOOT_MANIFEST_DIR)/illumos.manifest: projects/illumos/manifest | $(BOOT_MANIFEST_DIR)
	cp projects/illumos/boot.manifest $(BOOT_MANIFEST_DIR)/illumos.manifest

$(MANIFEST_FILE): $(BASE_MANIFESTS) $(LOCAL_MANIFESTS)
	-rm -f $@
	./tools/build_manifest $(MANIFEST_DIR) | ./tools/sorter > $@

$(BOOT_MANIFEST): $(BOOT_MANIFESTS)
	-rm -f $@
	./tools/build_manifest $(BOOT_MANIFEST_DIR) | ./tools/sorter > $@

$(TESTS_MANIFEST): world
	-rm -f $@
	echo "f tests.manifest 0444 root sys" >> $@
	echo "f tests.buildstamp 0444 root sys" >> $@
	cat $(TEST_IPS_MANIFESTS) | \
	    ./tools/generate-manifest-from-ips.nawk | \
	    ./tools/sorter >> $@

#
# We want a copy of the buildstamp in the tests archive, but
# don't want to call it 'buildstamp' since that would potentially
# overwrite the same file in the platform.tgz if they were
# ever extracted to the same area for investigation. Juggle a bit.
#
$(TESTS_TARBALL): $(TESTS_MANIFEST)
	pfexec rm -f $@
	pfexec rm -rf $(TESTS_PROTO)
	mkdir -p $(TESTS_PROTO)
	cp $(STAMPFILE) $(ROOT)/tests.buildstamp
	pfexec ./tools/builder/builder $(TESTS_MANIFEST) $(TESTS_PROTO) \
	    $(PROTO) $(ROOT)
	pfexec gtar -C $(TESTS_PROTO) -I pigz -cf $@ .
	rm $(ROOT)/tests.buildstamp

tests-tar: $(TESTS_TARBALL)

#
# Update source code from parent repositories.  We do this for each local
# project as well as for illumos, illumos-extra, and server-image via the
# update_base tool.
#
update: update-base $(LOCAL_SUBDIRS:%=%.update)
	-rm -f 0-local-stamp

.PHONY: update-base
update-base:
	./tools/update_base

.PHONY: %.update
%.update:
	cd $(ROOT)/projects/local/$* && \
		gmake update; \
	-rm -f 0-subdir-$*-stamp

0-local-stamp: $(LOCAL_SUBDIRS:%=0-subdir-%-stamp)
	touch $@

0-subdir-%-stamp: 0-illumos-stamp
	@echo "========== building $* =========="
	cd "$(ROOT)/projects/local/$*" && \
		gmake $(SUBDIR_DEFS) DESTDIR=$(PROTO) world install; \
	touch $@

0-devpro-stamp:
	[ ! -d projects/devpro ] || \
	    (cd projects/devpro && gmake DESTDIR=$(PROTO) install)
	touch $@

$(STAMPFILE):
	mkdir -p $(ROOT)/proto
	if [[ -z $$BUILDSTAMP ]]; then \
	    BUILDSTAMP=$$(TZ=UTC date "+%Y%m%dT%H%M%SZ"); \
	fi ; \
	echo "$$BUILDSTAMP" >$(STAMPFILE)

0-illumos-stamp: 0-strap-stamp $(STAMPFILE)
	@if [[ "$(ILLUMOS_CLOBBER)" = "yes" ]]; then \
		(cd $(ROOT) && MAX_JOBS=$(MAX_JOBS) ./tools/clobber_illumos) \
	fi
	(cd $(ROOT) && MAX_JOBS=$(MAX_JOBS) ./tools/build_illumos)
	touch $@

FORCEARG_yes=-f

# Check any build requirements that are easy to catch early.
0-preflight-stamp:
	$(ROOT)/tools/preflight
	touch $@

# build our proto.strap area
0-strap-stamp:
	$(ROOT)/tools/build_strap make \
	    -a $(ADJUNCT_TARBALL) -d $(STRAP_PROTO) -j $(MAX_JOBS) \
	    $(FORCEARG_$(FORCE_STRAP_REBUILD))
	touch $@

# build a proto.strap cache tarball
$(STRAP_CACHE_TARBALL):
	$(ROOT)/tools/build_strap make \
	    -a $(ADJUNCT_TARBALL) -d $(STRAP_PROTO) -j $(MAX_JOBS) \
            -o $(STRAP_CACHE_TARBALL) $(FORCEARG_$(FORCE_STRAP_REBUILD))

# build a CTF tools tarball
$(CTFTOOLS_TARBALL): 0-strap-stamp $(STAMPFILE)
	$(ROOT)/tools/build_ctftools make \
	    -j $(MAX_JOBS) -o $(CTFTOOLS_TARBALL)

# additional illumos-extra content for proto itself
0-extra-stamp: 0-preflight-stamp 0-illumos-stamp
	(cd $(ROOT)/projects/illumos-extra && \
	    gmake $(SUBDIR_DEFS) DESTDIR=$(PROTO) \
	    install)
	touch $@

0-livesrc-stamp: 0-illumos-stamp 0-strap-stamp 0-extra-stamp
	@echo "========== building src =========="
	(cd $(ROOT)/src && \
	    gmake -j$(MAX_JOBS) NATIVEDIR=$(STRAP_PROTO) \
	    DESTDIR=$(PROTO) && \
	    gmake NATIVEDIR=$(STRAP_PROTO) DESTDIR=$(PROTO) install)
	(cd $(ROOT)/man/ && gmake install DESTDIR=$(PROTO) $(SUBDIR_DEFS))
	touch $@

0-tools-stamp: 0-pwgen-stamp
	(cd $(ROOT)/tools/builder && gmake builder)
	(cd $(ROOT)/tools/format_image && gmake)
	touch $@

0-pwgen-stamp:
	(cd ${ROOT}/tools/pwgen-* && autoconf && ./configure && \
	    make && cp pwgen ${ROOT}/tools)
	touch $@

tools/cryptpass: src/cryptpass.c
	$(NATIVE_CC) -Wall -W -O2 -o $@ $<

$(MANCF_FILE): $(MANCF) $(MANIFEST)
	@rm -f $@
	$(MANCF) -t -f $(MANIFEST) > $@

.PHONY: $(MANCF)
$(MANCF): 0-illumos-stamp
	(cd tools/mancf && gmake mancf CC=$(NATIVE_CC) $(SUBDIR_DEFS))

.PHONY: $(MANCHECK)
$(MANCHECK): 0-illumos-stamp
	(cd tools/mancheck && gmake mancheck CC=$(NATIVE_CC) $(SUBDIR_DEFS))

.PHONY: $(TZCHECK)
$(TZCHECK): 0-illumos-stamp
	(cd tools/tzcheck && gmake tzcheck CC=$(NATIVE_CC) $(SUBDIR_DEFS))

.PHONY: $(UCODECHECK)
$(UCODECHECK): 0-illumos-stamp
	(cd tools/ucodecheck && gmake ucodecheck CC=$(NATIVE_CC) $(SUBDIR_DEFS))

jsl: $(JSLINT)

$(JSLINT):
	@(cd $(ROOT)/tools/javascriptlint; make CC=$(NATIVE_CC) install)

check: $(JSLINT)
	@(cd $(ROOT)/src && make check)

clean:
	./tools/clobber_illumos
	rm -f $(MANIFEST) $(BOOT_MANIFEST) $(TESTS_MANIFEST)
	rm -rf $(MANIFEST_DIR)/* $(BOOT_MANIFEST_DIR)/*
	(cd $(ROOT)/src && gmake clean)
	[ ! -d $(ROOT)/projects/illumos-extra ] || \
	    (cd $(ROOT)/projects/illumos-extra && gmake clean)
	[ ! -d projects/local ] || for dir in $(LOCAL_SUBDIRS); do \
		cd $(ROOT)/projects/local/$${dir} && \
			gmake clean; \
	done
	(cd $(PKGSRC) && gmake clean)
	(cd $(ROOT) && rm -rf $(PROTO))
	(cd $(ROOT) && [ -h $(STRAP_PROTO) ] || rm -rf $(STRAP_PROTO))
	(cd $(ROOT) && rm -f $(STRAP_PROTO))
	(cd $(ROOT) && pfexec rm -rf $(BOOT_PROTO))
	(cd $(ROOT) && pfexec rm -rf $(TESTS_PROTO))
	(cd $(ROOT) && mkdir -p $(PROTO) $(BOOT_PROTO) \
	    $(TESTS_PROTO))
	rm -f tools/cryptpass
	(cd tools/builder && gmake clean)
	(cd tools/format_image && gmake clean)
	(cd tools/mancheck && gmake clean)
	(cd tools/mancf && gmake clean)
	(cd tools/tzcheck && gmake clean)
	(cd tools/ucodecheck && gmake clean)
	(cd man && gmake clean)
	rm -f mancheck.conf
	rm -f 0-*-stamp 1-*-stamp

clobber: clean
	pfexec rm -rf output/* output-iso/* output-usb/*

iso: live
	./tools/build_boot_image -I -r $(ROOT)

usb: live
	./tools/build_boot_image -r $(ROOT)

#
# The build itself doesn't add debug suffixes to its outputs when running
# in the 'ILLUMOS_ENABLE_DEBUG=exclusive' (configure -d) mode, so the settings
# below add suffixes to the bits-dir copies of these files as appropriate.
# The 'PUB_' prefix below indicates published build artifacts.
#
# This is all overridden if PLATFORM_DEBUG_SUFFIX is defined in the environment,
# however.
#
ifeq ($(ILLUMOS_ENABLE_DEBUG),exclusive)
    PLATFORM_DEBUG_SUFFIX ?= -debug
endif

BUILD_NAME			?= platform

#
# Values specific to the 'platform' build.
#
PLATFORM_BITS_DIR		= $(ROOT)/output/bits/platform$(PLATFORM_DEBUG_SUFFIX)
PLATFORM_BRANCH ?= $(shell git symbolic-ref HEAD | awk -F/ '{print $$3}')

CTFTOOLS_BITS_DIR		= $(ROOT)/output/ctftools/bits

STRAP_CACHE_BITS_DIR		= $(ROOT)/output/strap-cache/bits

#
# PUB_BRANCH_DESC indicates the different 'projects' branches used by the build.
# Our shell script uniqifies the branches used, then emits a
# hyphen-separated string of 'projects' branches *other* than ones which
# match $PLATFORM_BRANCH (the branch of server-image.git itself).
# While this doesn't perfectly disambiguate builds from different branches,
# it is good enough for our needs.
#
PUB_BRANCH_DESC		= $(shell ./tools/projects_branch_desc $(PLATFORM_BRANCH))

PLATFORM_TIMESTAMP		= $(shell head -n1 $(STAMPFILE))
PLATFORM_STAMP			= $(PLATFORM_BRANCH)$(PUB_BRANCH_DESC)-$(PLATFORM_TIMESTAMP)

PLATFORM_TARBALL_BASE		= platform-$(PLATFORM_TIMESTAMP).tgz
PLATFORM_TARBALL		= output/$(PLATFORM_TARBALL_BASE)

PUB_BOOT_BASE			= boot$(PLATFORM_DEBUG_SUFFIX)-$(PLATFORM_STAMP).tgz
PUB_TESTS_BASE			= tests$(PLATFORM_DEBUG_SUFFIX)-$(PLATFORM_STAMP).tgz

PUB_PLATFORM_IMG_BASE		= platform$(PLATFORM_DEBUG_SUFFIX)-$(PLATFORM_STAMP).tgz
PUB_PLATFORM_MF_BASE		= platform$(PLATFORM_DEBUG_SUFFIX)-$(PLATFORM_STAMP).imgmanifest

PUB_PLATFORM_MF			= $(PLATFORM_BITS_DIR)/$(PUB_PLATFORM_MF_BASE)
PUB_PLATFORM_TARBALL		= $(PLATFORM_BITS_DIR)/$(PUB_PLATFORM_IMG_BASE)

PUB_BOOT_TARBALL		= $(PLATFORM_BITS_DIR)/$(PUB_BOOT_BASE)
PUB_TESTS_TARBALL		= $(PLATFORM_BITS_DIR)/$(PUB_TESTS_BASE)

PLATFORM_IMAGE_UUID		?= $(shell uuid -v4)

.PHONY: common-platform-publish
common-platform-publish:
	@echo "# Publish common platform$(PLATFORM_DEBUG_SUFFIX) bits"
	mkdir -p $(PLATFORM_BITS_DIR)
	cp $(PLATFORM_TARBALL) $(PUB_PLATFORM_TARBALL)
	cp $(TESTS_TARBALL) $(PUB_TESTS_TARBALL)
	for config_file in configure-projects configure-build; do \
	    if [[ -f $$config_file ]]; then \
	        cp $$config_file $(PLATFORM_BITS_DIR); \
	    fi; \
	done
	echo $(PLATFORM_STAMP) > latest-build-stamp
	./tools/build_changelog
	cp output/gitstatus.json $(PLATFORM_BITS_DIR)
	cp output/changelog.txt $(PLATFORM_BITS_DIR)

#
# A wrapper to build the additional components that a ServerOS release needs.
#
.PHONY: server-os-build
server-os-build:
	./tools/build_boot_image -I -r $(ROOT)
	./tools/build_boot_image -r $(ROOT)
	./tools/build_vmware -r $(ROOT)

.PHONY: server-os-publish
server-os-publish:
	@echo "# Publish ServerOS $(PLATFORM_TIMESTAMP) images"
	mkdir -p $(PLATFORM_BITS_DIR)
	cp output/platform-$(PLATFORM_TIMESTAMP)/root.password \
	    $(PLATFORM_BITS_DIR)/SINGLE_USER_ROOT_PASSWORD.txt
	cp output-iso/platform-$(PLATFORM_TIMESTAMP).iso \
	    $(PLATFORM_BITS_DIR)/server-os-$(PLATFORM_TIMESTAMP).iso
	cp output-usb/platform-$(PLATFORM_TIMESTAMP).usb.gz \
	    $(PLATFORM_BITS_DIR)/server-os-$(PLATFORM_TIMESTAMP)-USB.img.gz
	cp output-vmware/server-os-$(PLATFORM_TIMESTAMP).vmwarevm.tar.gz \
		$(PLATFORM_BITS_DIR)
	(cd $(PLATFORM_BITS_DIR) && \
	    $(ROOT)/tools/server-os-index $(PLATFORM_TIMESTAMP) > index.html)
	(cd $(PLATFORM_BITS_DIR) && \
	    /usr/bin/sum -x md5 * > md5sums.txt)

.PHONY: ctftools-publish
ctftools-publish:
	@echo "# Publish ctftools tarball"
	mkdir -p $(CTFTOOLS_BITS_DIR)
	git -C projects/illumos log -1 >$(CTFTOOLS_BITS_DIR)/gitstatus.illumos
	cp $(CTFTOOLS_TARBALL) $(CTFTOOLS_BITS_DIR)/ctftools.tar.gz

.PHONY: strap-cache-publish
strap-cache-publish:
	@echo "# Publish strap-cache tarball"
	mkdir -p $(STRAP_CACHE_BITS_DIR)
	git -C projects/illumos-extra log -1 \
	    >$(STRAP_CACHE_BITS_DIR)/gitstatus.illumos-extra
	cp $(STRAP_CACHE_TARBALL) $(STRAP_CACHE_BITS_DIR)/proto.strap.tar.gz

#
# Define a series of phony targets that encapsulate a standard 'release' process
# for ServerOS builds. These are a convenience to allow
# callers to invoke only two 'make' commands after './configure' has been run.
# We can't combine these because our stampfile likely doesn't exist at the point
# that the various build artifact Makefile macros are set, resulting in
# misnamed artifacts. Thus, expected usage is:
#
# ./configure
# make common-release; make server-os-release
#
.PHONY: common-release
common-release: \
    check \
    live \
    pkgsrc

.PHONY: server-os-release
server-os-release: \
    tests-tar \
    common-platform-publish \
    server-os-build \
    server-os-publish

.PHONY: ctftools-release
ctftools-release: \
    $(CTFTOOLS_TARBALL) \
    ctftools-publish

.PHONY: strap-cache-release
strap-cache-release: \
    $(STRAP_CACHE_TARBALL) \
    strap-cache-publish

print-%:
	@echo '$*=$($*)'

FRC:

.PHONY: manifest check jsl FRC
