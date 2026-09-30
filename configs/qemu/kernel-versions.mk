# Kernel version -> source tree / defconfig mapping.
#
# Usage:
#   make qemu-juno                       # uses DEFAULT_KERNEL_VERSION (v4.19)
#   make qemu-juno KERNEL_VERSION=v7.2   # uses kernel/v7.2
#
# Each supported version defines:
#   KERNEL_SRC_DIR_<tag>   path (relative to repo root or absolute) of the kernel tree
#   KERNEL_DEFCONFIG_<tag> kernel defconfig name (must exist under
#                          arch/arm64/configs/ of that tree)
#   KERNEL_EXTRA_DTS_<tag> optional DTBs (space separated, relative to
#                          arch/arm64/boot/dts/) to copy into the image dir
#
# Tags are matched by stripping the leading 'v' and replacing '.' with '_',
# e.g. v7.2 -> v7_2.

# Default version when KERNEL_VERSION is not given on the command line.
DEFAULT_KERNEL_VERSION := v4.19

# --- v4.19 : historical kernel shipped inside the git repo (kernel/common) ---
KERNEL_SRC_DIR_v4_19     := $(KERNEL_ROOT_DIR)/kernel/common
KERNEL_DEFCONFIG_v4_19   := juno_defconfig
KERNEL_EXTRA_DTS_v4_19   :=

# --- v7.2 : fetched on demand by scripts/setup-kernel.sh (NOT in git) ---
KERNEL_SRC_DIR_v7_2      := $(KERNEL_ROOT_DIR)/kernel/v7.2
KERNEL_DEFCONFIG_v7_2    := juno_defconfig
KERNEL_EXTRA_DTS_v7_2    :=

# --- v7.3 : optional, same convention ---
KERNEL_SRC_DIR_v7_3      := $(KERNEL_ROOT_DIR)/kernel/v7.3
KERNEL_DEFCONFIG_v7_3    := juno_defconfig
KERNEL_EXTRA_DTS_v7_3    :=
