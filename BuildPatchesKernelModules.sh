#!/bin/bash
# Get the kernel source for NVIDIA Jetson Nano Developer Kit, L4T
# Copyright (c) 2016-19 Jetsonhacks 
# MIT License
#Modified Script to Build Jetson Nano and Xavier AGX V4l/HID modules

set -e
echo "The script shall build and installed patched kernel and modules for Librealsense SDK/ with v4l/hid backend"
echo "Note: the patch makes changes to kernel device tree to support HID IMU sensors"
source ./patch-utils.sh

#cd ~/git/buildKernelAndModules/
#source ./patch-utils.sh 
#TEGRA_TAG=tegra-l4t-r32.4.3
#scripts_dir=$(pwd)
#sudo rm -rf /lib/modules/`uname -r`/kernel/drivers/iio
#sudo rm -rf ${TEGRA_TAG}-*.ko

#Evgeni TODO - Add empty space check - require 3Gb (2+ required for git clone)
#du -hs / 
#df -h --total | head -n 2 | tail -n 1 | awk '{print $3}' -> prints 18G


#Tegra-specific
KERNEL_RELEASE="4.9"
#Identify the Jetson board
JETSON_BOARD=$(tr -d '\0' </proc/device-tree/model)
echo "Jetson Board (proc/device-tree/model): "$JETSON_BOARD

JETSON_L4T=""

# With L4T 32.3.1, NVIDIA added back /etc/nv_tegra_release
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
echo "Jetson L4T version is "${JETSON_L4T_VERSION}

# Get the linux kernel repo, extract the L4T tag
echo "Obtain the correspondig L4T git tag for the kernel source tree"
l4t_gh_dir=../linux-${KERNEL_RELEASE}-source-tree
if [ ! -d ${l4t_gh_dir} ]; then
	mkdir ${l4t_gh_dir}
	pushd ${l4t_gh_dir}
	git init
	git remote add origin git://nv-tegra.nvidia.com/linux-${KERNEL_RELEASE}
	# Use Nvidia script instead to synchronize source tree and peripherals
	#git clone git://nv-tegra.nvidia.com/linux-${KERNEL_RELEASE}
	popd
else
	echo "Directory ${l4t_gh_dir} is present, skipping initialization..."
fi

#Search the repository for the tag that matches the maj.min for L4T
pushd ${l4t_gh_dir}
TEGRA_TAG=$(git ls-remote --tags origin | grep ${JETSON_L4T_VERSION} | grep '[^^{}]$' | tail -n 1 | awk -F/ '{print $NF}')
echo "The corresponding tag is ${TEGRA_TAG}"
echo -e "\e[32mThe matching L4T source tree tag is \e[47m${TEGRA_TAG}\e[0m"
popd


#retrieve tegra tag version for sync, required for get and sync kernel source with Jetson:
#https://forums.developer.nvidia.com/t/r32-1-tx2-how-can-i-build-extra-module-in-the-tegra-device/72942/9
#Download kernel and peripheral sources as the L4T github repo is not self-contained to build kernel modules
scripts_dir=$(pwd)
echo -e "\e[32mCreate the sandbox - NVidia L4T source tree(s)\e[0m"
sudo ./source_sync.sh -k ${TEGRA_TAG}
KBASE=./sources/kernel/kernel-4.9
echo ${KBASE}
pushd ${KBASE}

echo -e "\e[32mCopy LibRealSense patches to the sandbox\e[0m"
L4T_Patches_Dir=${scripts_dir}/LRS_Patches/
if [ ! -d ${L4T_Patches_Dir} ]; then
	echo -e "\e[41mThe L4T kernel patches directory  ${L4T_Patches_Dir} was not found, aborting\e[0m"
	exit 1
else
	sudo cp -r ${L4T_Patches_Dir} .
fi

#Clean the kernel WS
echo -e "\e[32mPrepare workspace for kernel build\e[0m"
sudo make ARCH=arm64 mrproper -j$(($(nproc)-1)) && sudo make ARCH=arm64 tegra_defconfig -j$(($(nproc)-1))
#Reuse existing module.symver
sudo cp /usr/src/linux-headers-4.9.140-tegra-ubuntu18.04_aarch64/kernel-4.9/Module.symvers .

echo "\e[32mUpdate the kernel tree to support HID IMU sensors\e[0m"
sudo sed -i '/CONFIG_HID_SENSOR_ACCEL_3D/c\CONFIG_HID_SENSOR_ACCEL_3D=m' .config
sudo sed -i '/CONFIG_HID_SENSOR_GYRO_3D/c\CONFIG_HID_SENSOR_GYRO_3D=m' .config
sudo sed -i '/CONFIG_HID_SENSOR_IIO_COMMON/c\CONFIG_HID_SENSOR_IIO_COMMON=m\nCONFIG_HID_SENSOR_IIO_TRIGGER=m' .config
sudo make ARCH=arm64 prepare modules_prepare  -j$(($(nproc)-1))

echo "\e[32mApply Librealsense Kernel Patches\e[0m"
sudo -s patch -p1 < ./LRS_Patches/01-realsense-camera-formats-L4T-4.9.patch
sudo -s patch -p1 < ./LRS_Patches/02-realsense-metadata-L4T-4.9.patch
sudo -s patch -p1 < ./LRS_Patches/03-realsense-hid-L4T-4.9.patch
sudo -s patch -p1 < ./LRS_Patches/04-media-uvcvideo-mark-buffer-error-where-overflow.patch
sudo -s patch -p1 < ./LRS_Patches/05-realsense-powerlinefrequency-control-fix.patch

# sudo apt-get install module-assistant
# from https://forums.developer.nvidia.com/t/solved-l4t-compiling-simple-kernel-module-fails/36955/6
#to handle ./scripts/recordmcount: not found
#sudo make ARCH=arm64 scripts

echo -e "\e[32mCompiling uvc module\e[0m"
#sudo -s make -j -C $KBASE M=$KBASE/drivers/media/usb/uvc/ modules
sudo -s make -j$(($(nproc)-1)) ARCH=arm64 M=drivers/media/usb/uvc/ modules
echo -e "\e[32mCompiling v4l2-core modules\e[0m"
#sudo -s make -j -C $KBASE M=$KBASE/drivers/media/v4l2-core modules
sudo -s make -j$(($(nproc)-1)) ARCH=arm64  M=drivers/media/v4l2-core modules
echo -e "\e[32mCompiling accelerometer and gyro modules\e[0m"
sudo -s make -j$(($(nproc)-1)) ARCH=arm64  M=drivers/iio modules

echo -e "\e[32mCopying the patched modules to ${scripts_dir} \e[0m"
sudo cp drivers/media/usb/uvc/uvcvideo.ko ${scripts_dir}/${TEGRA_TAG}-uvcvideo.ko
sudo cp drivers/media/v4l2-core/videobuf-vmalloc.ko ${scripts_dir}/${TEGRA_TAG}-videobuf-vmalloc.ko
sudo cp drivers/media/v4l2-core/videobuf-core.ko ${scripts_dir}/${TEGRA_TAG}-videobuf-core.ko
sudo cp drivers/iio/common/hid-sensors/hid-sensor-iio-common.ko ${scripts_dir}/${TEGRA_TAG}-hid-sensor-iio-common.ko
sudo cp drivers/iio/common/hid-sensors/hid-sensor-trigger.ko ${scripts_dir}/${TEGRA_TAG}-hid-sensor-trigger.ko
sudo cp drivers/iio/accel/hid-sensor-accel-3d.ko ${scripts_dir}/${TEGRA_TAG}-hid-sensor-accel-3d.ko
sudo cp drivers/iio/gyro/hid-sensor-gyro-3d.ko ${scripts_dir}/${TEGRA_TAG}-hid-sensor-gyro-3d.ko
popd

echo -e "\e[32mMove the modified modules into the modules tree\e[0m"
#Optional - create kernel modules directories in kernel tree
sudo mkdir -p /lib/modules/`uname -r`/kernel/drivers/iio/accel
sudo mkdir -p /lib/modules/`uname -r`/kernel/drivers/iio/gyro
sudo mkdir -p /lib/modules/`uname -r`/kernel/drivers/iio/common/hid-sensors
sudo cp  ${scripts_dir}/${TEGRA_TAG}-hid-sensor-accel-3d.ko     /lib/modules/`uname -r`/kernel/drivers/iio/accel/hid-sensor-accel-3d.ko
sudo cp  ${scripts_dir}/${TEGRA_TAG}-hid-sensor-gyro-3d.ko      /lib/modules/`uname -r`/kernel/drivers/iio/gyro/hid-sensor-gyro-3d.ko
sudo cp  ${scripts_dir}/${TEGRA_TAG}-hid-sensor-iio-common.ko   /lib/modules/`uname -r`/kernel/drivers/iio/common/hid-sensors/hid-sensor-iio-common.ko
sudo cp  ${scripts_dir}/${TEGRA_TAG}-hid-sensor-trigger.ko      /lib/modules/`uname -r`/kernel/drivers/iio/common/hid-sensors/hid-sensor-trigger.ko
# update kernel module dependencies
sudo depmod

echo -e "\e[32mInsert the modified kernel modules\e[0m"
try_module_insert uvcvideo              ${scripts_dir}/${TEGRA_TAG}-uvcvideo.ko                /lib/modules/`uname -r`/kernel/drivers/media/usb/uvc/uvcvideo.ko
try_module_insert hid_sensor_accel_3d   ${scripts_dir}/${TEGRA_TAG}-hid-sensor-accel-3d.ko     /lib/modules/`uname -r`/kernel/drivers/iio/accel/hid-sensor-accel-3d.ko
try_module_insert hid_sensor_gyro_3d    ${scripts_dir}/${TEGRA_TAG}-hid-sensor-gyro-3d.ko      /lib/modules/`uname -r`/kernel/drivers/iio/gyro/hid-sensor-gyro-3d.ko
#Preventively unload all HID-related modules
try_unload_module hid_sensor_accel_3d
try_unload_module hid_sensor_gyro_3d
try_unload_module hid_sensor_trigger
try_unload_module hid_sensor_trigger
try_module_insert hid_sensor_trigger    ${scripts_dir}/${TEGRA_TAG}-hid-sensor-trigger.ko      /lib/modules/`uname -r`/kernel/drivers/iio/common/hid-sensors/hid-sensor-trigger.ko
try_module_insert hid_sensor_iio_common ${scripts_dir}/${TEGRA_TAG}-hid-sensor-iio-common.ko   /lib/modules/`uname -r`/kernel/drivers/iio/common/hid-sensors/hid-sensor-iio-common.ko

echo -e "\e[92m\n\e[1mScript has completed. Please consult the installation guide for further instruction.\n\e[0m"
