#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright 2019 Joyent, Inc.
# Copyright 2023 ServerOS.
#

NPM =		npm

all: build test
test: install

.PHONY: build install test
build install test:
	$(NPM) $@

clean:
	-rm -rf node_modules
