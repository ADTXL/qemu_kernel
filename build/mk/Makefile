KERNEL_ROOT_DIR := $(shell cd ../..;pwd)

ifeq ($(KERNEL_ROOT_DIR),)    
$(error Please run this in a tree)    
endif    
$(warning KERNEL_ROOT_DIR = $(KERNEL_ROOT_DIR))

TARGET	:= $(if $(target),$(target),qemu-juno)
TARGETSPLT := $(subst -, ,$(TARGET))
TARGET_PLATFORM := $(word 1, $(TARGETSPLT))
TARGET_BOARD := $(word 2, $(TARGETSPLT))

$(warning TARGET_PLATFORM=$(TARGET_PLATFORM))
$(warning TARGET_BOARD=$(TARGET_BOARD))

# ---------------------------------------------------------------------------
# Multi-kernel support
#
#   make qemu-juno                        # default kernel (see below)
#   make qemu-juno KERNEL_VERSION=v7.2    # pick an exact kernel tree
#
# Version -> tree/defconfig mapping lives in configs/qemu/kernel-versions.mk
# ---------------------------------------------------------------------------
KERNEL_VERSION ?= v4.19
export KERNEL_VERSION

# v4.19 -> v4_19, v7.2 -> v7_2  (make variable names cannot contain '.')
KERNEL_VERSION_TAG := $(subst .,_,$(KERNEL_VERSION))

include $(KERNEL_ROOT_DIR)/configs/qemu/kernel-versions.mk

# Resolve the requested version to a source tree + defconfig.
KERNEL_SRC_DIR := $(KERNEL_SRC_DIR_$(KERNEL_VERSION_TAG))
KERNEL_DEFCONFIG_NAME := $(KERNEL_DEFCONFIG_$(KERNEL_VERSION_TAG))

ifeq ($(KERNEL_SRC_DIR),)
$(error Unknown KERNEL_VERSION='$(KERNEL_VERSION)'. Add it to configs/qemu/kernel-versions.mk)
endif

$(warning KERNEL_VERSION = $(KERNEL_VERSION) ($(KERNEL_VERSION_TAG)))
$(warning KERNEL_SRC_DIR = $(KERNEL_SRC_DIR))
$(warning KERNEL_DEFCONFIG_NAME = $(KERNEL_DEFCONFIG_NAME))

ifeq (juno, $(TARGET_BOARD))
export PREFIX_CROSS_COMPILE := aarch64-linux-gnu-
export ARCH := arm64
KBUILD_VERBOSE = 0

LINUX_DTS := juno-r1
DTS_DEFPATH := arm
BUSYBOX_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/$(TARGET_PLATFORM)/busybox_defconfig
UBOOT_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/$(TARGET_PLATFORM)/uboot_defconfig

# Per-version kernel source. Historically this was 'common'; now derived from
# KERNEL_VERSION so several trees can live side by side.
KERNEL_SRC_VERSION := $(KERNEL_VERSION)
endif

export KERNEL_ROOT_DIR
OUT_DIR := $(KERNEL_ROOT_DIR)/work
# Work/output directories are namespaced per kernel version so that builds for
# different kernels do not clobber each other.
IMGDIR := $(OUT_DIR)/$(TARGET_BOARD)/$(KERNEL_VERSION)/image
CONFDIR = $(KERNEL_ROOT_DIR)/configs

# Defconfig kept inside this repository (configs/qemu/<ver>/<name>). It is
# staged into the kernel build dir before 'make <name>', because newer kernel
# trees do not carry our board defconfig under arch/arm64/configs/.
KERNEL_DEFCONFIG := $(CONFDIR)/qemu/$(KERNEL_VERSION)/$(KERNEL_DEFCONFIG_NAME)

BOOTLOADER_SRCDIR := $(KERNEL_ROOT_DIR)/bootloader/freedom-u540-c000-bootloader

OPENSBI_SRCDIR := $(KERNEL_ROOT_DIR)/bootloader/opensbi
OPENSBI_WRKDIR := $(OUT_DIR)/$(TARGET_BOARD)/$(KERNEL_VERSION)/opensbi

UBOOT_SRCDIR := $(KERNEL_ROOT_DIR)/bootloader/uboot/$(UBOOT_SRC_VERSION)
UBOOT_WRKDIR := $(OUT_DIR)/$(TARGET_BOARD)/$(KERNEL_VERSION)/uboot

LINUX_SRCDIR := $(KERNEL_SRC_DIR)
LINUX_WRKDIR := $(OUT_DIR)/$(TARGET_BOARD)/$(KERNEL_VERSION)/linux

BUSYBOX_SRCDIR := $(KERNEL_ROOT_DIR)/rootfs/busybox
BUSYBOX_WRKDIR := $(OUT_DIR)/$(TARGET_BOARD)/$(KERNEL_VERSION)/busybox
BUSYBOX_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/busybox_arm64_config

ROOTFS_WRKDIR := $(IMGDIR)/rootfs

QEMU_FSTAB_EXT := $(CONFDIR)/qemu/fstab_ext
QEMU_ROOT := $(KERNEL_ROOT_DIR)/rootfs/root_qemu
QEMU_SRC := $(CONFDIR)/qemu/Makefile.qemu


# package work
PACKAGE_WRKDIR := $(IMGDIR)/package



# CROSS_COMPILR var
CC  = $(PREFIX_CROSS_COMPILE)gcc
CXX = $(PREFIX_CROSS_COMPILE)g++
LD  = $(PREFIX_CROSS_COMPILE)ld
AR  = $(PREFIX_CROSS_COMPILE)ar
AS  = $(PREFIX_CROSS_COMPILE)as
ARFLAGS = -rc

STRIP   = $(PREFIX_CROSS_COMPILE)strip
RANLIB  = $(PREFIX_CROSS_COMPILE)ranlib
OBJCOPY = $(PREFIX_CROSS_COMPILE)objcopy
NM      = $(PREFIX_CROSS_COMPILE)nm

ROOTSIZE := 500M
EXTSIZE := 500M


ifeq ($(ARCH),riscv)
IMAGE_TARGETS:=Image
CP_IMAGE:=Image
PACKAGE_IMAGE:= fw_jump.elf Image
all: busybox vmlinux fw_jump $(ROOTFS_WRKDIR) qemu-remote
	@echo "$@"
else
ifeq ($(ARCH),arm)
IMAGE_TARGETS:=Image bzImage
CP_IMAGE:=Image zImage
PACKAGE_IMAGE:=zImage
else
IMAGE_TARGETS:=Image
CP_IMAGE:=Image
PACKAGE_IMAGE:=Image
endif

all: busybox vmlinux $(ROOTFS_WRKDIR) qemu-remote
	@echo "$@"
endif

# set nproc
# Override on memory-constrained hosts:  make ... JOBS=2
Check_cpu_processor=$(shell grep processor /proc/cpuinfo | wc -l)
JOBSNUM=$(shell expr $(Check_cpu_processor))
JOBS ?= $(JOBSNUM)
nproc := $(JOBS)


# make uboot image
.PHONY: uboot
uboot: $(UBOOT_SRCDIR)
	@echo "compiling uboot....."
	mkdir -p $(UBOOT_WRKDIR)
	mkdir -p $(IMGDIR)
	cp $(UBOOT_DEFCONFIG) $(UBOOT_WRKDIR)/.config
	$(MAKE) -C $(UBOOT_SRCDIR) O=$(UBOOT_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) olddefconfig
	$(MAKE) -C $(UBOOT_SRCDIR) O=$(UBOOT_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) -j$(nproc)
	$(MAKE) -C $(UBOOT_SRCDIR) O=$(UBOOT_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) envtools
	cp -a $(UBOOT_WRKDIR)/u-boot.bin $(uboot_bin)

.PHONY: menuconfig
menuconfig:
	mkdir -p $(LINUX_WRKDIR)
	cp $(KERNEL_DEFCONFIG) $(LINUX_WRKDIR)/.config
	$(MAKE) -C $(LINUX_SRCDIR) O=$(LINUX_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) menuconfig
	$(MAKE) -C $(LINUX_SRCDIR) O=$(LINUX_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) savedefconfig
	mv $(LINUX_WRKDIR)/defconfig $(KERNEL_DEFCONFIG)
        
vmlinux: $(LINUX_SRCDIR)
	@echo "compiling vmlinux for $(KERNEL_VERSION)....."
	mkdir -p $(LINUX_WRKDIR)
	mkdir -p $(IMGDIR)
	rm -rf $(LINUX_WRKDIR)/arch/$(ARCH)/boot/dts
	mkdir -p $(LINUX_SRCDIR)/arch/$(ARCH)/configs
	cp $(KERNEL_DEFCONFIG) $(LINUX_SRCDIR)/arch/$(ARCH)/configs/$(KERNEL_DEFCONFIG_NAME)
	$(MAKE) -C $(LINUX_SRCDIR) O=$(LINUX_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) $(KERNEL_DEFCONFIG_NAME)
	$(MAKE) -C $(LINUX_SRCDIR) O=$(LINUX_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) olddefconfig
	$(MAKE) -C $(LINUX_SRCDIR) O=$(LINUX_WRKDIR) -j$(nproc) \
                ARCH=$(ARCH) \
                CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) \
                $(IMAGE_TARGETS) dtbs
	$(foreach t,$(CP_IMAGE),cp $(LINUX_WRKDIR)/arch/$(ARCH)/boot/$(t) $(IMGDIR);) 
	cp -af $(LINUX_WRKDIR)/arch/$(ARCH)/boot/dts/$(DTS_DEFPATH)/$(LINUX_DTS).dtb $(IMGDIR)/$(LINUX_DTS).dtb

modules: vmlinux
	@echo "compiling kernel modules....."
	$(MAKE) -C $(LINUX_SRCDIR) O=$(LINUX_WRKDIR) -j$(nproc) \
                ARCH=$(ARCH) \
                CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) \
                INSTALL_MOD_PATH=$(LINUX_WRKDIR) \
                modules
	$(MAKE) -C $(LINUX_SRCDIR) O=$(LINUX_WRKDIR) -j$(nproc) \
                ARCH=$(ARCH) \
                CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) \
                INSTALL_MOD_PATH=$(LINUX_WRKDIR) \
                modules_install

fw_jump: $(OPENSBI_SRCDIR) vmlinux
	@echo "compiling opensbi fw_jump....."
	#rm -rf $(opensbi_wrkdir)
	mkdir -p $(OPENSBI_WRKDIR)
	mkdir -p $(IMGDIR)
	$(MAKE) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) \
                        -C $(OPENSBI_SRCDIR) \
                        O=$(OPENSBI_WRKDIR) PLATFORM=qemu/virt \
                        FW_PAYLOAD_PATH=$(IMGDIR)/Image FW_PAYLOAD_FDT_PATH=$(IMGDIR)/$(LINUX_DTS).dtb
	cp -a $(OPENSBI_WRKDIR)/platform/qemu/virt/firmware/fw_jump.elf $(IMGDIR)/fw_jump.elf
        
busybox: $(BUSYBOX_SRCDIR)
	@echo "compiling busybox....."
	mkdir -p $(BUSYBOX_WRKDIR)
	$(MAKE) -C $(BUSYBOX_SRCDIR) O=$(BUSYBOX_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) defconfig </dev/null
	cp $(BUSYBOX_DEFCONFIG) $(BUSYBOX_WRKDIR)/.config
	$(MAKE) -C $(BUSYBOX_SRCDIR) O=$(BUSYBOX_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) -j$(nproc)
	$(MAKE) -C $(BUSYBOX_SRCDIR) O=$(BUSYBOX_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) CONFIG_PREFIX=$(BUSYBOX_WRKDIR) install

$(ROOTFS_WRKDIR): busybox $(root_srcdir) modules
	rm -rf $(ROOTFS_WRKDIR)
	mkdir -p $(ROOTFS_WRKDIR)
	cd $(ROOTFS_WRKDIR) && \
                mkdir root home bin sbin etc dev usr lib lib/modules tmp mnt sys proc var system sdcard usr/lib usr/bin
	cp -rf $(BUSYBOX_WRKDIR)/* $(ROOTFS_WRKDIR)/
	find $(LINUX_WRKDIR)/lib/modules/ -name "*.ko" | xargs -i cp {} $(ROOTFS_WRKDIR)/lib/modules
	#cp -rf $(SYSROOT)/* $(ROOTFS_WRKDIR)/

.PHONY: qemu_rootfs
qemu_rootfs: $(ROOTFS_WRKDIR)
	cp -rf $(QEMU_ROOT)/* $(ROOTFS_WRKDIR)

FSTYPE ?= ext4

# ---- boot-test ---------------------------------------------------------------
# Boot the freshly built image under QEMU and drop into the shell. Exits when
# the guest is powered off (or after BOOT_TIMEOUT seconds, default 60).
#   make boot-test KERNEL_VERSION=v7.2 [BOOT_TIMEOUT=90] [SMP=1] [MEM=512]
BOOT_TIMEOUT ?= 60
SMP ?= 1
MEM ?= 512
QEMU_HW ?= virt
QEMU_CPU ?= cortex-a57

.PHONY: boot-test
boot-test: vmlinux qemu_rootfs
	@command -v mkfs.$(FSTYPE) >/dev/null 2>&1 || command -v mkfs.ext4 >/dev/null 2>&1 || { echo "error: mkfs.ext4 not found (install e2fsprogs)" >&2; exit 1; }
	@command -v qemu-system-aarch64 >/dev/null 2>&1 || { echo "error: qemu-system-aarch64 not found" >&2; exit 1; }
	rm -f $(IMGDIR)/rootfs.ext4
	mkfs.ext4 -d $(ROOTFS_WRKDIR) $(IMGDIR)/rootfs.ext4 1024M
	@echo "booting $(KERNEL_VERSION) under QEMU (timeout $(BOOT_TIMEOUT)s)..."
	timeout $(BOOT_TIMEOUT) qemu-system-aarch64 -nographic -M $(QEMU_HW) -cpu $(QEMU_CPU) -smp $(SMP) -m $(MEM) \
		-kernel $(IMGDIR)/Image \
		-drive id=disk0,file=$(IMGDIR)/rootfs.ext4,if=none,format=raw \
		-device virtio-blk-device,drive=disk0 \
		-append "root=/dev/vda rw mem=$(MEM)M console=ttyAMA0" \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0 || true
	@echo "boot-test done"

qemu-remote: vmlinux qemu_rootfs $(QEMU_SRC) $(QEMU_FSTAB_EXT)
	rm -rf $(PACKAGE_WRKDIR)
	mkdir -p $(PACKAGE_WRKDIR)
	$(foreach t,$(PACKAGE_IMAGE),cp $(IMGDIR)/$(t) $(PACKAGE_WRKDIR)/;)
	cp $(QEMU_FSTAB_EXT) $(PACKAGE_WRKDIR)/
	cp -rf $(ROOTFS_WRKDIR) $(PACKAGE_WRKDIR)/
	cp $(QEMU_SRC) $(PACKAGE_WRKDIR)/Makefile
	cd $(PACKAGE_WRKDIR) && tar -zcvf image.tar.gz ./*
	@echo "make qemu image success, location: $(PACKAGE_WRKDIR)/image.tar.gz"
        

