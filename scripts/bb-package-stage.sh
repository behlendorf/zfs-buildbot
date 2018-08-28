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

case "$BB_NAME" in
CentOS*)
	# Target the CentOS version used by the mock build.
	# For CentOS use the full version number.
	PACKAGE=$(grep -m1 -o 'centos-release-[0-9]*-[.a-zA-Z0-9]*' \
	    $RESULTS_DIR/root.log)
	VERSION=$(echo ${PACKAGE//-/.} | cut -f3 -d'.')
	if [ "$VERSION" = "7" ]; then
		VERSION=$(echo ${PACKAGE//-/.} | cut -f3-4 -d'.')
	fi

	# TYPE sets the correct additional repository path components.
	# The existing layout may be changed in the future.
	if [[ $INSTALL_METHOD == "dkms" ]]; then
		TYPE=""
	elif [[ $INSTALL_METHOD == "kmod-kabi" ]]; then
		TYPE="kmod/"
	else
		echo "Only DKMS and kABI packages provided for CentOS"
		exit 1
	fi

	ROOT_DIR="$BB_REPO_DIR/epel${TESTING}/$VERSION"
	REPO_DIR="$ROOT_DIR/$TYPE"
	LOCK_DIR="/var/run/buildbot/repo/epel${TESTING}/$VERSION"

	# Lock the repository while updating it.
	mkdir -p $LOCK_DIR
	exec 100>$LOCK_DIR/lock
	flock -w 300 100 || exit 1
	PID=$$
	echo $PID 1>&100

	set -x

	# Create the required directories and copy in the packages.
	DIR="$ROOT_DIR/SRPMS"
	mkdir -p $DIR
	cp -u $RESULTS_DIR/SRPMS/*.rpm $DIR || exit 1
	createrepo --update $DIR || exit 1
	rm -f $DIR/repodata/repomd.xml.asc
	gpg --batch --passphrase-file ~/.rpmpassphrase --detach-sign \
	    --armor $DIR/repodata/repomd.xml || exit 1

	DIR="$REPO_DIR/$ARCH"
	mkdir -p $DIR
	cp -u $RESULTS_DIR/$ARCH/*.rpm $DIR || exit 1
	createrepo --update $DIR || exit 1
	rm -f $DIR/repodata/repomd.xml.asc
	gpg --batch --passphrase-file ~/.rpmpassphrase --detach-sign \
	    --armor $DIR/repodata/repomd.xml || exit 1

	DIR="$REPO_DIR/$ARCH/debug"
	mkdir -p $DIR
	cp -u $RESULTS_DIR/$ARCH/debug/*.rpm $DIR || exit 1
	createrepo --update $DIR || exit 1
	rm -f $DIR/repodata/repomd.xml.asc
	gpg --batch --passphrase-file ~/.rpmpassphrase --detach-sign \
	    --armor $DIR/repodata/repomd.xml || exit 1

	set +x
	flock -u 100
	;;

Fedora*)
	PACKAGE=$(grep -m1 -o 'fedora-release-[0-9]*-[.a-zA-Z0-9]*' \
	    $RESULTS_DIR/root.log)
	VERSION=$(echo ${PACKAGE//-/.} | cut -f3 -d'.')

	# TYPE sets the correct additional repository path components.
	# The existing layout may be changed in the future.
	if [[ $INSTALL_METHOD == "dkms" ]]; then
		TYPE=""
	else
		echo "Only DKMS and kABI packages provided for CentOS"
		exit 1
	fi

	ROOT_DIR="$BB_REPO_DIR/fedora${TESTING}/$VERSION"
	REPO_DIR="$ROOT_DIR/$TYPE"
	LOCK_DIR="/var/run/buildbot/repo/fedora${TESTING}/$VERSION"

	# Lock the repository while updating it.
	mkdir -p $LOCK_DIR
	exec 100>$LOCK_DIR/lock
	flock -w 300 100 || exit 1
	PID=$$
	echo $PID 1>&100

	set -x

	# Create the required directories and copy in the packages.
	DIR="$ROOT_DIR/SRPMS"
	mkdir -p $DIR
	cp -u $RESULTS_DIR/SRPMS/*.rpm $DIR || exit 1
	createrepo --update $DIR || exit 1
	rm -f $DIR/repodata/repomd.xml.asc
	gpg --batch --passphrase-file ~/.rpmpassphrase --detach-sign \
	    --armor $DIR/repodata/repomd.xml || exit 1

	DIR="$REPO_DIR/$ARCH"
	mkdir -p $DIR
	cp -u $RESULTS_DIR/$ARCH/*.rpm $DIR || exit 1
	createrepo --update $DIR || exit 1
	rm -f $DIR/repodata/repomd.xml.asc
	gpg --batch --passphrase-file ~/.rpmpassphrase --detach-sign \
	    --armor $DIR/repodata/repomd.xml || exit 1

	DIR="$REPO_DIR/$ARCH/debug"
	mkdir -p $DIR
	cp -u $RESULTS_DIR/$ARCH/debug/*.rpm $DIR || exit 1
	createrepo --update $DIR || exit 1
	rm -f $DIR/repodata/repomd.xml.asc
	gpg --batch --passphrase-file ~/.rpmpassphrase --detach-sign \
	    --armor $DIR/repodata/repomd.xml || exit 1

	set +x
	flock -u 100
	;;
*)
	echo "$BB_NAME unsupported platform"
	exit 1
	;;
esac

exit 0
