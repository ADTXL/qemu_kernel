
help:
	@echo "Usage :"
	@echo "make <targetboard>"
	@echo "  <targetboard>"
	@echo "     qemu-<juno>"

TARGET_PLATFORM := qemu
TARGET_BOARD := juno

TARGETS := \
	$(foreach target_platform, $(TARGET_PLATFORM), \
		$(foreach target_board, $(TARGET_BOARD), \
			$(target_platform)-$(target_board) \
		)\
	)

$(TARGETS):
	cd build/mk && make target=$@ 




