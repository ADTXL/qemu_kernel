#!/usr/bin/env bash
#
# run_qemu.sh - boot a previously built kernel image under QEMU (arm64 virt)
#
# Usage:
#   ./run_qemu.sh [KERNEL_VERSION]
#
# Environment overrides:
#   KERNEL_VERSION=v7.2     which image dir to boot   (default: v4.19)
#   EXT=/path/to/dir        mount an extra ext4 disk at boot (optional)
#   QEMU=/path/to/qemu      qemu-system-aarch64 binary
#   SMP=4                   number of vCPUs              (default: 1)
#   MEM=512                 guest memory in MB            (default: 512)
#   CPU=cortex-a57          -cpu model                    (default: cortex-a57)
#
set -euo pipefail

KERNEL_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_VERSION="${1:-${KERNEL_VERSION:-v4.19}}"

# ---- locate the qemu binary -------------------------------------------------
if [ -n "${QEMU:-}" ]; then
	QEMU_BIN="$QEMU"
elif [ -x "${KERNEL_ROOT_DIR}/qemu/bin/qemu-system-aarch64" ]; then
	# self-built qemu shipped under qemu/ (see qemu/readme.md)
	QEMU_BIN="${KERNEL_ROOT_DIR}/qemu/bin/qemu-system-aarch64"
else
	# fall back to a system-wide qemu
	QEMU_BIN="$(command -v qemu-system-aarch64 || true)"
fi

if [ -z "${QEMU_BIN}" ] || [ ! -x "${QEMU_BIN}" ]; then
	echo "error: qemu-system-aarch64 not found." >&2
	echo "  install it (apt install qemu-system-arm) or build it under qemu/ (see qemu/readme.md)" >&2
	echo "  or pass QEMU=/path/to/qemu-system-aarch64" >&2
	exit 1
fi

# ---- resolve image directory ------------------------------------------------
IMGDIR="${KERNEL_ROOT_DIR}/work/juno/${KERNEL_VERSION}/image"
if [ ! -f "${IMGDIR}/Image" ]; then
	echo "error: no kernel image for '${KERNEL_VERSION}' at ${IMGDIR}/Image" >&2
	echo "  build it first, e.g.  make qemu-juno KERNEL_VERSION=${KERNEL_VERSION}" >&2
	exit 1
fi

ROOTFS_WRKDIR="${IMGDIR}/rootfs"
FSTYPE="ext4"
ROOTSIZE="1024M"
EXTSIZE="1024M"

# mkfs.ext4/e2fsprogs usually live in /sbin or /usr/sbin
export PATH="${PATH}:/sbin:/usr/sbin"

command -v mkfs."${FSTYPE}" >/dev/null 2>&1 || {
	echo "error: mkfs.${FSTYPE} not found (install e2fsprogs)" >&2; exit 1; }

# ---- build the DTB if a source dts is present -------------------------------
if [ -f "${KERNEL_ROOT_DIR}/arm_juno.dts" ] && command -v dtc >/dev/null 2>&1; then
	dtc -I dts -O dtb -o "${KERNEL_ROOT_DIR}/arm_juno.dtb" \
		"${KERNEL_ROOT_DIR}/arm_juno.dts" >/dev/null 2>&1 || true
fi

rm -f "${IMGDIR}/rootfs.${FSTYPE}" "${IMGDIR}/work.${FSTYPE}"

SMP="${SMP:-1}"
MEM="${MEM:-512}"
CPU="${CPU:-cortex-a57}"

if [ -n "${EXT:-}" ]; then
	echo "run qemu (kernel ${KERNEL_VERSION}) with external filesystem"
	cp "${KERNEL_ROOT_DIR}/configs/qemu/fstab_ext" "${ROOTFS_WRKDIR}/etc/fstab"
	mkfs."${FSTYPE}" -d "${ROOTFS_WRKDIR}" "${IMGDIR}/rootfs.${FSTYPE}" "${ROOTSIZE}" >/dev/null
	mkfs."${FSTYPE}" -d "${EXT}" "${IMGDIR}/work.${FSTYPE}" "${EXTSIZE}" >/dev/null
	exec "${QEMU_BIN}" -nographic -M virt -cpu "${CPU}" -smp "${SMP}" -m "${MEM}" \
		-kernel "${IMGDIR}/Image" \
		-drive id=disk0,file="${IMGDIR}/rootfs.${FSTYPE}",if=none,format=raw \
		-device virtio-blk-device,drive=disk0 \
		-append "root=/dev/vda rw mem=${MEM}M console=ttyAMA0" \
		-drive id=disk1,file="${IMGDIR}/work.${FSTYPE}",if=none,format=raw \
		-device virtio-blk-device,drive=disk1 \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0
else
	echo "run qemu (kernel ${KERNEL_VERSION}) without external filesystem"
	mkfs."${FSTYPE}" -d "${ROOTFS_WRKDIR}" "${IMGDIR}/rootfs.${FSTYPE}" "${ROOTSIZE}" >/dev/null
	exec "${QEMU_BIN}" -nographic -M virt -cpu "${CPU}" -smp "${SMP}" -m "${MEM}" \
		-kernel "${IMGDIR}/Image" \
		-drive id=disk0,file="${IMGDIR}/rootfs.${FSTYPE}",if=none,format=raw \
		-device virtio-blk-device,drive=disk0 \
		-append "root=/dev/vda rw mem=${MEM}M console=ttyAMA0" \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0
fi
