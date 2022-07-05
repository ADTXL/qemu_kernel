#!/usr/bin/env bash

set -e


KernelRootPath="/home/user/txl/project/qemu_kernel"
qemuBinPath="/home/user/txl/project/qemu_kernel/qemu/bin"
QEMU=""$qemuBinPath"/qemu-system-aarch64"

imgdir=""$KernelRootPath"/work/juno/image"
rootfs_wrkdir=""$imgdir"/rootfs"
fstab_ext=""$KernelRootPath"/configs/qemu/fstab_ext"

ROOTSIZE="500M"
EXTSIZE="500M"

FSTYPE="ext4"

if [ -f "$imgdir"/rootfs."$FSTYPE" ]
then
	rm -f "$imgdir"/rootfs."$FSTYPE"
fi

if [ -f "$imgdir"/work."$FSTYPE" ]
then
	rm -f "$imgdir"/work."$FSTYPE"
fi

if [ -n "$1" ] 
then
	echo "run qemu with external filesystem"
	cp "$fstab_ext" "$rootfs_wrkdir"/etc/fstab
	mkfs."$FSTYPE" -d "$rootfs_wrkdir" "$imgdir"/rootfs."$FSTYPE" "$ROOTSIZE"
	mkfs."$FSTYPE" -d $1 "$imgdir"/work."$FSTYPE" "$EXTSIZE"
	"$QEMU" -nographic -M virt -cpu cortex-a57 -smp 1 -m 512 -kernel "$imgdir"/Image \
		-drive id=disk0,file="$imgdir"/rootfs."$FSTYPE",if=none,format=raw \
		-device virtio-blk-device,drive=disk0 \
		-append 'root=/dev/vda rw mem=512M  console=ttyAMA0' \
		-drive id=disk1,file="$imgdir"/work."$FSTYPE",if=none,format=raw \
		-device virtio-blk-device,drive=disk1 \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0
else
	echo "run qemu without external filesystem"
	mkfs."$FSTYPE" -d "$rootfs_wrkdir" "$imgdir"/rootfs."$FSTYPE" "$ROOTSIZE"
	"$QEMU" -nographic -s -S -M virt -cpu cortex-a57 -smp 1 -m 512 -kernel "$imgdir"/Image \
		-drive id=disk0,file="$imgdir"/rootfs."$FSTYPE",if=none,format=raw \
		-device virtio-blk-device,drive=disk0 \
		-append 'root=/dev/vda rw mem=512M  console=ttyAMA0' \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0
fi

