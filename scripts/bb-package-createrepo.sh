#!/bin/bash

INSTALL_METHOD=${INSTALL_METHOD:-"none"}
INSTALL_TESTING=${INSTALL_TESTING:-"no"}
BUILDER="$(echo $BB_NAME | cut -f1-3 -d'-')"
ARCH=$(arch)

if [[ "$INSTALL_TESTING" == @(y|yes) ]]; then
	TESTING="-testing"
else
	TESTING=""
fi

RESULTS_DIR="$BB_UPLOAD_DIR/${BUILDER}${TESTING}/packages/$INSTALL_METHOD"

set -x

# Sign packages with the ZFS on Linux buildbot key.
find $RESULTS_DIR -name "*.rpm" -exec rpmsign.exp {} + || exit 1

# Create a signed repository.
REPO_DIRS="$RESULTS_DIR/SRPMS $RESULTS_DIR/$ARCH $RESULTS_DIR/$ARCH/debug"
for DIR in $REPO_DIRS; do
	createrepo $DIR || exit 1
	rm -f $DIR/repodata/repomd.xml.asc
	gpg --batch --passphrase-file ~/.rpmpassphrase --detach-sign \
	    --armor $DIR/repodata/repomd.xml || exit 1
done

exit 0
