#!/bin/bash

if test -f /etc/buildslave; then
	. /etc/buildslave
fi

INSTALL_METHOD=${INSTALL_METHOD:-"none"}
INSTALL_TESTING=${INSTALL_TESTING:-"no"}
BUILDER="$(echo $BB_NAME | cut -f1-3 -d'-')"
ARCH=$(arch)

if [[ "$INSTALL_TESTING" == @(y|yes) ]]; then
	TESTING="-testing"
else
	TESTING=""
fi

RESULTS_DIR="$UPLOAD_DIR/${BUILDER}${TESTING}/packages/$INSTALL_METHOD"
MOCK_OPTIONS="--rebuild --resultdir=$RESULTS_DIR"

set -x
mkdir -p "$RESULTS_DIR"

# Links to logs which will be created by mock.
ln -s "$RESULTS_DIR/build.log" build.log
ln -s "$RESULTS_DIR/root.log" root.log
ln -s "$RESULTS_DIR/state.log" state.log

sh ./autogen.sh || exit 1

# Create source packages.
case "$INSTALL_METHOD" in
dkms)
	./configure --with-config=srpm || exit 1
	make srpm || exit 1
	rm zfs-kmod*.src.rpm
	;;

kmod-kabi)
	./configure --with-config=srpm --with-spec=redhat || exit 1
	make srpm || exit 1
	rm zfs-dkms*.src.rpm
	;;
esac

# Create binaries from source packages in a pristine environment.
mock $MOCK_OPTIONS zfs-*.src.rpm || exit 1

# Organize the resulting packages for uploading and create a repository
# for local package installation.
mkdir -p $RESULTS_DIR/SRPMS
mkdir -p $RESULTS_DIR/$ARCH
mkdir -p $RESULTS_DIR/$ARCH/debug

mv $RESULTS_DIR/*.src.rpm $RESULTS_DIR/SRPMS
mv $RESULTS_DIR/*debug*.rpm $RESULTS_DIR/$ARCH/debug
mv $RESULTS_DIR/*.rpm $RESULTS_DIR/$ARCH

createrepo $RESULTS_DIR/SRPMS || exit 1
createrepo $RESULTS_DIR/$ARCH || exit 1
createrepo $RESULTS_DIR/$ARCH/debug || exit 1

exit 0
