
help:
	@echo "Usage :"
	@echo "make <targetboard>"
	@echo "  <targetboard>"
	@echo "     qemu-<juno>"

TARGET_PLATFORM := qemu
TARGET_BOARD := juno
export TARGET_PLATFORM
export TARGET_BOARD

TARGETS := \
	$(foreach target_platform, $(TARGET_PLATFORM), \
		$(foreach target_board, $(TARGET_BOARD), \
			$(target_platform)-$(target_board) \
		)\
	)

$(TARGETS):
	cd build/mk && make target=$@ 

# Convenience passthroughs: build/boot for a given board without the
# 'target=' indirection used above.
#   make boot-test KERNEL_VERSION=v7.2 [BOOT_TIMEOUT=90]
.PHONY: boot-test vmlinux modules qemu_rootfs clean
# Forward -e so TARGET_PLATFORM/TARGET_BOARD exported by callers reach the
# sub-make; otherwise default to the qemu/juno board used by $(TARGETS).
boot-test vmlinux modules qemu_rootfs clean:
	cd build/mk && make $@ KERNEL_VERSION=$(KERNEL_VERSION)



