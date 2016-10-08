#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
	. /etc/buildslave
fi

#
# Update image with the most current pacakges.
# Minimal dependencies to generate source RPMs.
#
case "$BB_NAME" in
CentOS*)
	set -x
	sudo -E yum -y upgrade
	sudo -E yum -y install gcc automake libtool git \
	    rpm-build createrepo kernel-devel
	;;
Fedora*)
	set -x
	sudo -E dnf -y upgrade
	sudo -E dnf -y install gcc make automake libtool git \
	    rpm-build createrepo
	;;
*)
	echo "$BB_NAME unsupported platform"
	;;
esac
