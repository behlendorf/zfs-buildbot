#!/bin/bash

if test -f /etc/buildslave; then
	. /etc/buildslave
fi

INSTALL_METHOD=${INSTALL_METHOD:-"none"}
INSTALL_UPGRADE=${INSTALL_UPGRADE:-"no"}
INSTALL_TESTING=${INSTALL_TESTING:-"no"}
INSTALL_LOG="install.log"
UPGRADE_LOG="upgrade.log"
BUILDER="$(echo $BB_NAME | cut -f1-3 -d'-')"


if [ -z "$INSTALL_REPO" ]; then
	echo "Install repository required"
	exit 1
fi

if [ -z "$UPGRADE_REPO" ]; then
	UPGRADE_REPO="$INSTALL_REPO"
fi

if [[ "$INSTALL_TESTING" == @(y|yes) ]]; then
	TESTING="-testing"
else
	TESTING=""
fi

RESULTS_DIR="$UPLOAD_DIR/${BUILDER}${TESTING}/packages/$INSTALL_METHOD"

# Install zfs packages and required dependencies.
case "$BB_NAME" in
CentOS*)
	# Required for gpg signature checking.
	# Enable EPEL for additional dependencies until they can be removed.
	if cat /etc/centos-release | grep -Eq "release 6."; then
		VERSION="6"
		EPEL_REPO="--enablerepo=epel" # dkms, python34, libudev
	elif cat /etc/centos-release | grep -Eq "release 7."; then
		VERSION=$(grep -o "7.[0-9]*" /etc/centos-release)
		EPEL_REPO="--enablerepo=epel" # dkms, python34
	else
		echo "Only CentOS 6 and 7 are supported"
		exit 1
	fi
	RELEASE="$BB_WEBURL/repo/epel/zfs-release.el${VERSION/./_}.noarch.rpm"

	set -x
	sudo -E yum -y install $RELEASE >>$INSTALL_LOG || exit 1
	sudo sed -i 's/enabled=1/enabled=0/' /etc/yum.repos.d/zfs.repo
	set +x

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

	# Add local, install, and upgrade repositories.  All repositoes
	# are disabled by default and enabled as needed.
	if [ "$INSTALL_REPO" = "local" ]; then
		INSTALL_BASEURL="file://${RESULTS_DIR}/\$basearch/"
		INSTALL_GPGCHECK=0
	else
		INSTALL_BASEURL="$INSTALL_REPO/epel$TESTING/$VERSION/$TYPE\$basearch/"
		# Disabled until this can be fully automated.
		INSTALL_GPGCHECK=0
	fi

	if [ "$UPGRADE_REPO" = "local" ]; then
		UPGRADE_BASEURL="file://${RESULTS_DIR}/\$basearch/"
		UPGRADE_GPGCHECK=0
	else
		UPGRADE_BASEURL="$UPGRADE_REPO/epel$TESTING/$VERSION/$TYPE\$basearch/"
		# Disabled until this can be fully automated.
		UPGRADE_GPGCHECK=0
	fi

	cat <<EOF >>/tmp/zfs-buildbot.repo
[zfs-install]
name=ZFS on Linux - Install $INSTALL_METHOD
baseurl=$INSTALL_BASEURL
enabled=0
metadata_expire=7d
gpgcheck=$INSTALL_GPGCHECK
repo_gpgcheck=$INSTALL_GPGCHECK
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux
       file:///etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux-secondary

[zfs-upgrade]
name=ZFS on Linux - Upgrade $INSTALL_METHOD
baseurl=$UPGRADE_BASEURL
enabled=0
metadata_expire=7d
gpgcheck=$UPGRADE_GPGCHECK
repo_gpgcheck=$UPGRADE_GPGCHECK
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux
       file:///etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux-secondary
EOF

	set -x
	sudo mv /tmp/zfs-buildbot.repo /etc/yum.repos.d/zfs-buildbot.repo
	cat /etc/yum.repos.d/zfs-buildbot.repo
	set +x

	#
	# Install: Install the newly build packages on a clean system.  This
	# allows checking the package dependencies.
	#
	set -x
	sudo -E yum -y --enablerepo=zfs-install $EPEL_REPO \
	    install zfs >>$INSTALL_LOG || exit 1
	sudo -E yum -y --enablerepo=zfs-install $EPEL_REPO \
	    install zfs-test >>$INSTALL_LOG || exit 1
	if cat /etc/centos-release | grep -Eq "7."; then
		sudo -E yum -y --enablerepo=zfs-install $EPEL_REPO \
		    install python2-pyzfs >>$INSTALL_LOG || exit 1
	fi
	sudo modprobe zfs || exit 1
	set +x

	#
	# Upgrade: Install the latest packages from the main repository,
	# load the kernel module, then upgrade the packages to the newly built
	# packages.  This allows testing that upgrade works as intended and
	# the user space binaries are compatible with previous kernel modules.
	#
	if [[ "$INSTALL_UPGRADE" == @(y|yes) ]]; then
		set -x
		sudo -E yum -y --enablerepo=zfs-upgrade $EPEL_REPO \
		    upgrade >>$UPGRADE_LOG || exit 1
		set +x
	fi
	;;

Fedora*)
	# Required for gpg signature checking.
	RELEASE="$BB_WEBURL/repo/fedora/zfs-release$(rpm -E %dist).noarch.rpm"
	set -x
	sudo -E dnf -y install $RELEASE >>$INSTALL_LOG || exit 1
	sudo sed -i 's/enabled=1/enabled=0/' /etc/yum.repos.d/zfs.repo
	set +x

	# TYPE sets the correct additional repository path components.
	# The existing layout may be changed in the future.
	if [[ $INSTALL_METHOD == "dkms" ]]; then
		TYPE=""
	else
		echo "Only DKMS packages provided for Fedora"
		exit 1
	fi

	# Add local, install, and upgrade repositories.  All repositoes
	# are disabled by default and enabled as needed.
	if [ "$INSTALL_REPO" = "local" ]; then
		INSTALL_BASEURL="file://${RESULTS_DIR}/\$basearch/"
		INSTALL_GPGCHECK=0
	else
		INSTALL_BASEURL="$INSTALL_REPO/fedora$TESTING/\$releasever/$TYPE\$basearch/"
		INSTALL_GPGCHECK=1
	fi

	if [ "$UPGRADE_REPO" = "local" ]; then
		UPGRADE_BASEURL="file://${RESULTS_DIR}/\$basearch/"
		UPGRADE_GPGCHECK=0
	else
		UPGRADE_BASEURL="$UPGRADE_REPO/fedora$TESTING/\$releasever/$TYPE\$basearch/"
		UPGRADE_GPGCHECK=1
	fi

	cat <<EOF >>/tmp/zfs-buildbot.repo
[zfs-install]
name=ZFS on Linux - Install $INSTALL_METHOD
baseurl=$INSTALL_BASEURL
enabled=0
metadata_expire=7d
gpgcheck=$INSTALL_GPGCHECK
repo_gpgcheck=$INSTALL_GPGCHECK
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux
       file:///etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux-secondary

[zfs-upgrade]
name=ZFS on Linux - Upgrade $INSTALL_METHOD
baseurl=$UPGRADE_BASEURL
enabled=0
metadata_expire=7d
gpgcheck=$UPGRADE_GPGCHECK
repo_gpgcheck=$UPGRADE_GPGCHECK
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux
       file:///etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux-secondary
EOF

	set -x
	sudo mv /tmp/zfs-buildbot.repo /etc/yum.repos.d/zfs-buildbot.repo
	cat /etc/yum.repos.d/zfs-buildbot.repo

	#
	# Install: Install the newly build packages on a clean system.  This
	# allows checking the package dependencies.
	#
	sudo -E dnf -y --enablerepo=zfs-install \
	    install zfs >>$INSTALL_LOG || exit 1
	sudo -E dnf -y --enablerepo=zfs-install \
	    install zfs-test >>$INSTALL_LOG || exit 1
	sudo -E dnf -y --enablerepo=zfs-install \
	    install python3-pyzfs >>$INSTALL_LOG || exit 1
	sudo modprobe zfs || exit 1
	set +x

	#
	# Upgrade: Install the latest packages from the main repository,
	# load the kernel module, then upgrade the packages to the newly built
	# packages.  This allows testing that upgrade works as intended and
	# the user space binaries are compatible with previous kernel modules.
	#
	if [[ "$INSTALL_UPGRADE" == @(y|yes) ]]; then
		set -x
		sudo -E dnf -y --enablerepo=zfs-upgrade \
		    upgrade >>$UPGRADE_LOG || exit 1
		set +x
	fi
	;;
*)
	echo "$BB_NAME unsupported platform"
	exit 1
	;;
esac

exit 0
