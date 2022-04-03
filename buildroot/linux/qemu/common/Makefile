
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


ifeq (,$(platform))
$(error Makefile: error: Internal error: platform variable is not set)
else

override-target=linux-$(TARGET_BOARD)-$(platform)
include $(KERNEL_ROOT_DIR)/buildroot/make/Make.config
endif


ifeq ($(kernel_version),2_6)
KOBJ=ko
endif


lmsc_platform=$(platform)

ifeq (2.6.24.4, $(KERN_VER))
lmsc_platform=$(platform).2.6.24
endif

ifeq (2.6.25, $(KERN_VER))
lmsc_platform=$(platform).2.6.25
endif

ifeq (2.6.27.18, $(KERN_VER))
lmsc_platform=$(platform).2.6.27
endif

ifeq (3.0,$(WRS_LINUX_VERSION))
lmsc_platform=$(platform)-wr30
endif

ifeq ($(DESTDIR),)
DESTDIR=${BLDDIR}
endif


ifeq (1,$(KS_HIGHMEM))
lmsc_platform:=$(lmsc_platform)-highmem
endif

$(DEST_DIR):
	mkdir -p $@

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


ifeq ($(nproc),)					
$(error Please check make.tools)		
endif 

	
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
	
vmlinux: $(LINUX_SRCDIR) $(KERNEL_DEFCONFIG)
	@echo "compiling vmlinux....."
	mkdir -p $(LINUX_WRKDIR)
	mkdir -p $(IMGDIR)
	cp -af $(KERNEL_DEFCONFIG) $(LINUX_WRKDIR)/.config
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
	
busybox: $(BUSYBOX_SRCDIR) $(BUSYBOX_DEFCONFIG)
	@echo "compiling busybox....."
	mkdir -p $(BUSYBOX_WRKDIR)
	cp $(BUSYBOX_DEFCONFIG) $(BUSYBOX_SRCDIR)/.config
	cd $(BUSYBOX_SRCDIR) && \
		$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) -j$(nproc) && \
		$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(PREFIX_CROSS_COMPILE) CONFIG_PREFIX=$(BUSYBOX_WRKDIR) install

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
	
kernel_modules:
	@echo "$@"

clean:
	@echo "clean all...."
	@echo "$@"

distclean: clean


# Make.config defines remaining phony targets
.PHONY: check kernel_modules kernel_targets DELIVER

