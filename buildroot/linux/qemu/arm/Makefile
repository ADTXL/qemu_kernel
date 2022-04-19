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

KERNEL_ROOT_DIR := $(shell cd ../../../../;pwd)

ifeq ($(KERNEL_ROOT_DIR),)					
$(error Please run this in a tree)		
endif 				

export KERNEL_ROOT_DIR

export TARGET_BOARD := qemu

override kernel_version=4_19
platform=arm-$(kernel_version)

export KERNEL_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/$(TARGET_BOARD)/android-4.19-r/arm/linux_defconfig
export LINUX_DTS := juno-r1
export DTS_DEFPATH := arm
export BUSYBOX_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/$(TARGET_BOARD)/busybox_defconfig
export UBOOT_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/$(TARGET_BOARD)/uboot_defconfig
export KERNEL_SRC_VERSION := common

include ${KERNEL_ROOT_DIR}/buildroot/make/Make.linux

