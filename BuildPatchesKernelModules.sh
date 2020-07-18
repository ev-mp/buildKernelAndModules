#!/bin/bash
# Get the kernel source for NVIDIA Jetson Nano Developer Kit, L4T
# Copyright (c) 2016-19 Jetsonhacks 
# MIT License
#Modified Script to Build Jetson Nano and Xavier AGX V4l/HID modules
# Error out if something goes wrong
set -e
echo "The script shall build and installed patched kernel and modules for Librealsense SDK/ with v4l/hid backend"
echo "Note: the patch makes changes to kernel device tree to support HID IMU sensors"

#JETSON_MODEL="NVIDIA Jetson Nano Developer Kit"
#L4T_TARGET="32.4.3"
SOURCE_TARGET="$pwd../"
#SOURCE_TARGET="/usr/src"
KERNEL_RELEASE="4.9"

# < is more efficient than cat command
# NULL byte at end of board description gets bash upset; strip it out
JETSON_BOARD=$(tr -d '\0' </proc/device-tree/model)
echo "Jetson Board (proc/device-tree/model): "$JETSON_BOARD

JETSON_L4T=""

# L4T 32.3.1, NVIDIA added back /etc/nv_tegra_release
if [ -f /etc/nv_tegra_release ]; then
	JETSON_L4T_STRING=$(head -n 1 /etc/nv_tegra_release)
	JETSON_L4T_RELEASE=$(echo $JETSON_L4T_STRING | cut -f 2 -d ' ' | grep -Po '(?<=R)[^;]+')
	JETSON_L4T_REVISION=$(echo $JETSON_L4T_STRING | cut -f 2 -d ',' | grep -Po '(?<=REVISION: )[^;]+')
	JETSON_L4T_VERSION=$JETSON_L4T_RELEASE.$JETSON_L4T_REVISION
	echo "Jetson L4T version: "${JETSON_L4T_VERSION}
else
	echo "/etc/nv_tegra_release not present, aborting script"
	exit;
fi

echo "Cloning Nvidia Tegra kernel source tree into ../linux-4.9"
if [ ! -d ../linux-4.9 ]; then
	pushd ../
	git clone git://nv-tegra.nvidia.com/linux-${KERNEL_RELEASE}
	popd
else
	echo "Library already present, skipping the stage..."
fi


echo "Checking out the proper kernel source version"
pushd ../linux-${KERNEL_RELEASE}
TEGRA_TAG=$(git tag -l | grep ${JETSON_L4T_VERSION})
#retrieve tegra tag version for sync, required for get and sync kernel source with Jetson:
#sudo ./source_sync.sh -k <tegra_tag>  (e.g. tegra-l4t-r32.1)
#https://forums.developer.nvidia.com/t/r32-1-tx2-how-can-i-build-extra-module-in-the-tegra-device/72942/9

popd
#sudo cp ./source_sync.sh /usr/src
sudo cp source_sync.sh /usr/src
pushd /usr/src
echo "Downloading and sync kernel sources using tag ${TEGRA_TAG}, this may take a while..."
#Evgeni redirect to  null env -i sudo ./source_sync.sh -k ${TEGRA_TAG}
popd

#nb=""
#[ $(git branch | grep sandbox | wc -l) -ne 1 ] && nb=" -b"
#git checkout ${nb} sandbox
#git reset --hard origin/l4t/l4t-r${JETSON_L4T_VERSION}-${KERNEL_RELEASE}
echo "/usr/src/sources/kernel/kernel-4.9"
pushd /usr/src/sources/kernel/kernel-4.9

TEGRA_KERNEL_OUT=./OutDir/
#$ cd <kernel_source>
sudo mkdir -p $TEGRA_KERNEL_OUT

# Go get the default config file; this becomes the new system configuration
#sudo make olddefconfig
sudo make ARCH=arm64 O=$TEGRA_KERNEL_OUT tegra_defconfig
# Make a backup of the original configuration
sudo cp ${TEGRA_KERNEL_OUT}.config config_bkp.$(date -Ins)

#echo "Modify kernel tree to support HID IMU sensors"
sudo sed -i '/CONFIG_HID_SENSOR_ACCEL_3D/c\CONFIG_HID_SENSOR_ACCEL_3D=m' ${TEGRA_KERNEL_OUT}.config
sudo sed -i '/CONFIG_HID_SENSOR_GYRO_3D/c\CONFIG_HID_SENSOR_GYRO_3D=m' ${TEGRA_KERNEL_OUT}.config
sudo sed -i '/CONFIG_HID_SENSOR_IIO_COMMON/c\CONFIG_HID_SENSOR_IIO_COMMON=m\nCONFIG_HID_SENSOR_IIO_TRIGGER=m' ${TEGRA_KERNEL_OUT}.config
pwd

echo "Build Kernel Monolythic image"


sudo -s time make ARCH=arm64 O=$TEGRA_KERNEL_OUT -j$(($(nproc)-1))

sudo make ARCH=arm64 O=$TEGRA_KERNEL_OUT modules_install
sudo cp ${TEGRA_KERNEL_OUT}arch/arm64/boot/Image /boot/Image
sudo cp -r ${TEGRA_KERNEL_OUT}arch/arm64/boot/dts/* /boot/dtb/
#sudo -s time make -j$(($(nproc)-1)) modules_prepare
#sudo -s time make -j$(($(nproc)-1)) Image
#sudo -s time make -j$(($(nproc)-1)) modules

popd


echo Evgeni Done!
exit

#env -i sudo ./source_sync.sh -k tegra-l4t-r32.2.3-1

#echo "Getting L4T Version"
#check_L4T_version
#JETSON_L4T="$JETSON_L4T_VERSION"

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`
# e.g. echo "${red}The red tail hawk ${green}loves the green grass${reset}"

#LAST="${SOURCE_TARGET: -1}"
#if [ $LAST != '/' ] ; then
#   SOURCE_TARGET="$SOURCE_TARGET""/"
#fi

INSTALL_DIR=$PWD



# Check to make sure we're installing the correct kernel sources
# Determine the correct kernel version
# The KERNEL_BUILD_VERSION is the release tag for the JetsonHacks buildKernel repository
#KERNEL_BUILD_VERSION=master
#if [ "$JETSON_BOARD" == "$JETSON_MODEL" ] ; then 
  #if [ $JETSON_L4T == "$L4T_TARGET" ] ; then
     #KERNEL_BUILD_VERSION=$L4T_TARGET
  #else
   #echo ""
   #tput setaf 1
   #echo "==== L4T Kernel Version Mismatch! ============="
   #tput sgr0
   #echo ""
   #echo "This repository is for modifying the kernel for a L4T "$L4T_TARGET "system." 
   #echo "You are attempting to modify a L4T "$JETSON_MODEL "system with L4T "$JETSON_L4T
   #echo "The L4T releases must match!"
   #echo ""
   #echo "There may be versions in the tag/release sections that meet your needs"
   #echo ""
   #exit 1
  #fi
#else 
   #tput setaf 1
   #echo "==== Jetson Board Mismatch! ============="
   #tput sgr0
    #echo "Currently this script works for the $JETSON_MODEL."
   #echo "This processor appears to be a $JETSON_BOARD, which does not have a corresponding script"
   #echo ""
   #echo "Exiting"
   #exit 1
#fi

## Check to see if source tree is already installed
#PROPOSED_SRC_PATH="$SOURCE_TARGET""kernel/kernel-"$KERNEL_RELEASE
#echo "Proposed source path: ""$PROPOSED_SRC_PATH"
#if [ -d "$PROPOSED_SRC_PATH" ]; then
  #tput setaf 1
  #echo "==== Kernel source appears to already be installed! =============== "
  #tput sgr0
  #echo "The kernel source appears to already be installed at: "
  #echo "   ""$PROPOSED_SRC_PATH"
  #echo "If you want to reinstall the source files, first remove the directories: "
  #echo "  ""$SOURCE_TARGET""kernel"
  #echo "  ""$SOURCE_TARGET""hardware"
  #echo "then rerun this script"
  #exit 1
#fi

#export SOURCE_TARGET
## -E preserves environment variables
#sudo -E ./scripts/getKernelSources.sh


