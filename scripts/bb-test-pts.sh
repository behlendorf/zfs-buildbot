#!/bin/bash

# Check for a local cached configuration.
if test -f /etc/buildslave; then
	. /etc/buildslave
fi

# Custom test options will be saved in the tests directory.
if test -f "../TEST"; then
	. ../TEST
fi

TEST_PTS_SKIP=${TEST_PTS_SKIP:-"No"}
if echo "$TEST_PTS_SKIP" | grep -Eiq "^yes$|^on$|^true$|^1$"; then
	echo "Skipping disabled test"
	exit 3
fi

ZPOOL=${ZPOOL:-"zpool"}
ZFS=${ZFS:-"zfs"}
ZFS_SH=${ZFS_SH:-"zfs.sh"}
PTS=${PTS:-"phoronix-test-suite"}
DEPLOY_LOG="$PWD/deploy.log"
CONSOLE_LOG="$PWD/console.log"

# Cleanup the pool and restore any modified system state.  The console log
# is dumped twice to maximize the odds of preserving debug information.
cleanup()
{
	dmesg >$CONSOLE_LOG
	sudo -E $ZPOOL destroy -f $TEST_PTS_POOL &>/dev/null
	sudo -E $ZFS_SH -u
	dmesg >$CONSOLE_LOG
}
trap cleanup EXIT SIGTERM

set -x

TEST_PTS_URL=${TEST_PTS_URL:-"https://github.com/phoronix-test-suite/phoronix-test-suite/archive/"}
TEST_PTS_VER=${TEST_PTS_VER:-"master.tar.gz"}
TEST_PTS_POOL=${TEST_PTS_POOL:-"tank"}
TEST_PTS_POOL_OPTIONS=${TEST_PTS_POOL_OPTIONS:-""}
TEST_PTS_FS=${TEST_PTS_FS:-"fs"}
TEST_PTS_FS_OPTIONS=${TEST_PTS_FS_OPTIONS:-"-o xattr=sa"}
TEST_PTS_VDEVS=${TEST_PTS_VDEVS:-"raidz xvdb xvdc xvdd xvde xvdf xvdg"}
TEST_PTS_BENCHMARKS=${TEST_PTS_BENCHMARKS:-"pts/compress-gzip-1.1.0 pts/sqlite-1.9.0 pts/pgbench-1.5.2 pts/compilebench-1.0.1 pts/iozone-1.8.0 pts/postmark-1.1.0 pts/aio-stress-1.1.1"}

TEST_DIR="/$TEST_PTS_POOL/$TEST_PTS_FS"

set +x

wget -qO${TEST_PTS_VER} ${TEST_PTS_URL}${TEST_PTS_VER} || exit 1
tar -xzf ${TEST_PTS_VER} || exit 1
rm ${TEST_PTS_VER}

# Using deploy to build packages would be preferable but that requires
# the script to determine what kind of packages to build.
cd phoronix-test-suite*
sudo -E ./install.sh >$DEPLOY_LOG 2>&1 || exit 1

# Configure PTS and pool to start with a clean slate
$PTS enterprise-setup
$PTS user-config-set EnvironmentDirectory="$TEST_DIR"
$PTS user-config-set UploadResults="FALSE"
$PTS user-config-set PromptForTestIdentifier="FALSE"
$PTS user-config-set PromptForTestDescription="FALSE"
$PTS user-config-set PromptSaveName="FALSE"
$PTS user-config-set Configured="TRUE"

sudo -E dmesg -c >/dev/null
sudo -E $ZFS_SH || exit 1a

export TEST_RESULTS_NAME=$(cat /sys/module/zfs/version)
export TEST_RESULTS_DESCRIPTION="Buildbot automated testing results"

sudo -E $ZPOOL create $TEST_PTS_POOL \
    $TEST_PTS_POOL_OPTIONS $TEST_PTS_VDEVS | exit 1
sudo -E $ZFS create $TEST_PTS_POOL/$TEST_PTS_FS \
    $TEST_PTS_FS_OPTIONS | exit 1
sudo -E chmod 777 $TEST_DIR

$PTS batch-benchmark $TEST_PTS_BENCHMARKS
RESULT=$?

exit $RESULT
