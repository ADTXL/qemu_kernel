
KERNEL_ROOT_DIR := $(shell cd ../..;pwd)

ifeq ($(KERNEL_ROOT_DIR),)    
$(error Please run this in a tree)    
endif    
$(warning KERNEL_ROOT_DIR = $(KERNEL_ROOT_DIR))

TARGET	:= $(target)
TARGETSPLT := $(subst -, ,$(TARGET))
TARGET_PLATFORM := $(word 1, $(TARGETSPLT))
TARGET_BOARD := $(word 2, $(TARGETSPLT))

$(warning TARGET_PLATFORM=$(TARGET_PLATFORM))
$(warning TARGET_BOARD=$(TARGET_BOARD))

ifeq (juno, $(TARGET_BOARD))
export PREFIX_CROSS_COMPILE := aarch64-linux-gnu-
export ARCH := arm64
KBUILD_VERBOSE = 0

LINUX_DTS := juno-r1
DTS_DEFPATH := arm
BUSYBOX_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/$(TARGET_PLATFORM)/busybox_defconfig
UBOOT_DEFCONFIG := $(KERNEL_ROOT_DIR)/configs/$(TARGET_PLATFORM)/uboot_defconfig
KERNEL_SRC_VERSION := common
endif

export KERNEL_ROOT_DIR
OUT_DIR := $(KERNEL_ROOT_DIR)/work
IMGDIR := $(OUT_DIR)/$(TARGET_BOARD)/image
CONFDIR = $(KERNEL_ROOT_DIR)/configs

BOOTLOADER_SRCDIR := $(KERNEL_ROOT_DIR)/bootloader/freedom-u540-c000-bootloader

OPENSBI_SRCDIR := $(KERNEL_ROOT_DIR)/bootloader/opensbi
OPENSBI_WRKDIR := $(OUT_DIR)/$(TARGET_BOARD)/opensbi

UBOOT_SRCDIR := $(KERNEL_ROOT_DIR)/bootloader/uboot/$(UBOOT_SRC_VERSION)
UBOOT_WRKDIR := $(OUT_DIR)/$(TARGET_BOARD)/uboot

LINUX_SRCDIR := $(KERNEL_ROOT_DIR)/kernel/$(KERNEL_SRC_VERSION)
LINUX_WRKDIR := $(OUT_DIR)/$(TARGET_BOARD)/linux

BUSYBOX_SRCDIR := $(KERNEL_ROOT_DIR)/rootfs/busybox
BUSYBOX_WRKDIR := $(OUT_DIR)/$(TARGET_BOARD)/busybox
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
Check_cpu_processor=$(shell grep processor /proc/cpuinfo | wc -l)
JOBSNUM=$(shell expr $(Check_cpu_processor))
nproc := $(JOBSNUM)


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
	@echo "compiling vmlinux....."
	mkdir -p $(LINUX_WRKDIR)
	mkdir -p $(IMGDIR)
	rm -rf $(LINUX_WRKDIR)/arch/$(ARCH)/boot/dts
	$(MAKE) -C $(LINUX_SRCDIR) O=$(LINUX_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) $(TARGET_BOARD)_defconfig
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
	$(MAKE) -C $(BUSYBOX_SRCDIR) O=$(BUSYBOX_WRKDIR) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) defconfig
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

qemu-remote: vmlinux qemu_rootfs $(QEMU_SRC) $(QEMU_FSTAB_EXT)
	rm -rf $(PACKAGE_WRKDIR)
	mkdir -p $(PACKAGE_WRKDIR)
	$(foreach t,$(PACKAGE_IMAGE),cp $(IMGDIR)/$(t) $(PACKAGE_WRKDIR)/;)
	cp $(QEMU_FSTAB_EXT) $(PACKAGE_WRKDIR)/
	cp -rf $(ROOTFS_WRKDIR) $(PACKAGE_WRKDIR)/
	cp $(QEMU_SRC) $(PACKAGE_WRKDIR)/Makefile
	cd $(PACKAGE_WRKDIR) && tar -zcvf image.tar.gz ./*
	@echo "make qemu image success, location: $(PACKAGE_WRKDIR)/image.tar.gz"
        


