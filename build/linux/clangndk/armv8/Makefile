#
# This make job requires the following environment variables to be set:
#
# SDK                - path to StrataXGS SDK root directory
#
# Optionally the following environment variables can be set to
# override the default build server configuration:
#
# PPC_TOOLS_DIR     - path to build tools (if not in PATH already)
# PPC_CROSS_COMPILE - cross compile tools prefix
# LINUX_INCLUDE      - path to Linux kernel include directory
#

KERNEL_ROOT_DIR :=$(shell if [ -n "$$KERNEL_ROOT_DIR" ] ; then\
	echo $$KERNEL_ROOT_DIR;\
	else\
	cd $(dir $(lastword $(MAKEFILE_LIST))); while /usr/bin/test ! -e RELEASE ; do \
	dir=`cd ../;pwd`;			\
	if [ "$$dir" = "/" ] ; then		\
	   echo Cannot find KERNEL_ROOT_DIR in $(lastword $(MAKEFILE_LIST)) 1>&2;		\
	   exit 1;				\
	fi ;					\
	cd $$dir;				\
	done ;					\
	pwd;					\
	fi)

ifeq ($(KERNEL_ROOT_DIR),)					
$(error Please run this in a tree)		
endif 				

export KERNEL_ROOT_DIR

export TARGET_BOARD := clangndk

override kernel_version=4_19
platform=armv8-$(kernel_version)

export KERNEL_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/$(TARGET_BOARD)/4.19.176/arm64/linux_defconfig
export LINUX_DTS := uniphier-ld20-global
export DTS_DEFPATH := socionext
export BUSYBOX_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/$(TARGET_BOARD)/busybox_defconfig
export UBOOT_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/$(TARGET_BOARD)/uboot-uniphier_v8_defconfig201704
export KERNEL_SRC_VERSION := common
export UBOOT_SRC_VERSION := u-boot-2020.10

export PREFIX_HOST_COMPILE := /home/dman/android11/android-ndk-r22/toolchains/llvm/prebuilt/linux-x86_64/bin/

include ${KERNEL_ROOT_DIR}/buildroot/make/Make.linux

