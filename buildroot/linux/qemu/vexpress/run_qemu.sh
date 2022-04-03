#!/usr/bin/env bash

set -e


KernelRootPath="/home/android-4.19-r"
qemuBinPath="/home/qemu-dev/bin/"
QEMU=""$qemuBinPath"/qemu-system-arm"

imgdir=""$KernelRootPath"/work/linux-qemu-vexpress-4_19/image"
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

echo $1
if [ -n "$1" ] 
then
	echo "run qemu with external filesystem"
	cp "$fstab_ext" "$rootfs_wrkdir"/etc/fstab
	mkfs."$FSTYPE" -d "$rootfs_wrkdir" "$imgdir"/rootfs."$FSTYPE" "$ROOTSIZE"
	mkfs."$FSTYPE" -d $1 "$imgdir"/work."$FSTYPE" "$EXTSIZE"
	"$QEMU" -nographic -M vexpress-a9 -m 512 -kernel "$imgdir"/zImage \
		-dtb "$imgdir"/vexpress-v2p-ca9.dtb \
		-append 'root=/dev/mmcblk0  console=ttyAMA0' \
		-sd "$imgdir"/rootfs."$FSTYPE" \
		-drive id=disk1,file="$imgdir"/work."$FSTYPE",if=none,format=raw \
		-device virtio-blk-device,drive=disk1 \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0
else
	echo "run qemu without external filesystem"
	mkfs."$FSTYPE" -d "$rootfs_wrkdir" "$imgdir"/rootfs."$FSTYPE" "$ROOTSIZE"
	"$QEMU" -nographic -M vexpress-a9 -m 512 -kernel "$imgdir"/zImage \
		-dtb "$imgdir"/vexpress-v2p-ca9.dtb \
		-append 'root=/dev/mmcblk0  console=ttyAMA0' \
		-sd "$imgdir"/rootfs."$FSTYPE" \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0
fi

