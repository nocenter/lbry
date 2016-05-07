#!/bin/bash

# Tested on fresh Ubuntu 14.04 install.

# wget https://raw.githubusercontent.com/lbryio/lbry/master/packaging/ubuntu/ubuntu_package_setup.sh
# bash ubuntu_package_setup.sh [BRANCH] [WEB-UI-BRANCH]

set -euo pipefail
set -o xtrace

SOURCE_DIR=$PWD

SUDO=''
if (( $EUID != 0 )); then
    SUDO='sudo'
fi

BRANCH=${1:-master}
WEB_UI_BRANCH=${2:-}

BUILD_DIR="$HOME/lbry-build-$(date +%Y%m%d-%H%M%S)"
mkdir "$BUILD_DIR"
cd "$BUILD_DIR"

# get the required OS packages
$SUDO apt-get -qq update
$SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq install -y --no-install-recommends software-properties-common
$SUDO add-apt-repository -y ppa:spotify-jyrki/dh-virtualenv
$SUDO apt-get -qq update
$SUDO DEBIAN_FRONTEND=noninteractive apt-get -qq install -y --no-install-recommends build-essential git python-dev libffi-dev libssl-dev libgmp3-dev dh-virtualenv debhelper wget

# need a modern version of pip (more modern than ubuntu default)
wget https://bootstrap.pypa.io/get-pip.py
$SUDO python get-pip.py
rm get-pip.py
$SUDO pip install make-deb

# build packages
#
# dpkg-buildpackage outputs its results into '..' so
# we need to move lbry into the build directory 
mv $SOURCE_DIR lbry
(
    cd lbry
    make-deb
    dpkg-buildpackage -us -uc
)


### insert our extra files

# extract .deb
PACKAGE="$(ls | grep '.deb')"
ar vx "$PACKAGE"
mkdir control data
tar -xzf control.tar.gz --directory control
tar -xJf data.tar.xz --directory data

PACKAGING_DIR='lbry/packaging/ubuntu'

# set web ui branch
if [ -z "$WEB_UI_BRANCH" ]; then
  sed -i "s/^WEB_UI_BRANCH='[^']\+'/WEB_UI_BRANCH='$WEB_UI_BRANCH'/" "$PACKAGING_DIR/lbry"
fi

# add files
function addfile() {
  FILE="$1"
  TARGET="$2"
  mkdir -p "$(dirname "data/$TARGET")"
  cp "$FILE" "data/$TARGET"
  echo "$(md5sum "data/$TARGET" | cut -d' ' -f1)  $TARGET" >> control/md5sums
}
addfile "$PACKAGING_DIR/lbry" usr/share/python/lbrynet/bin/lbry
addfile "$PACKAGING_DIR/lbry.desktop" usr/share/applications/lbry.desktop
#addfile lbry/packaging/ubuntu/lbry-init.conf etc/init/lbry.conf

# repackage .deb
$SUDO chown -R root:root control data
tar -czf control.tar.gz -C control .
tar -cJf data.tar.xz -C data .
$SUDO chown root:root debian-binary control.tar.gz data.tar.xz
ar r "$PACKAGE" debian-binary control.tar.gz data.tar.xz

# TODO: we can append to data.tar instead of extracting it all and recompressing
