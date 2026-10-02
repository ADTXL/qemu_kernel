#!/usr/bin/env bash
#
# test-sched-ext.sh - boot v7.2ext under QEMU and verify a sched_ext BPF
#                     scheduler actually attaches (scx_enabled() == true).
#
# Usage:
#   ./scripts/test-sched-ext.sh [KERNEL_VERSION] [SCX_BIN]
#
# Env overrides:
#   SMP=2        number of vCPUs        (default: 2, sched_ext needs >1 to be useful)
#   MEM=1024     guest memory in MB     (default: 1024)
#   BOOT_WAIT=60 seconds to wait for the guest shell before sending commands
#   RUN_WAIT=30  seconds to wait for the scx_* run before capturing the result
#
set -uo pipefail

KERNEL_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_VERSION="${1:-${KERNEL_VERSION:-v7.2ext}}"
SCX_BIN_NAME="${2:-${SCX_BIN:-scx_simple}}"

IMGDIR="${KERNEL_ROOT_DIR}/work/juno/${KERNEL_VERSION}/image"
ROOTFS_WRKDIR="${IMGDIR}/rootfs"
LOG="${IMGDIR}/sched-ext-test.log"

SMP="${SMP:-2}"
MEM="${MEM:-1024}"
BOOT_WAIT="${BOOT_WAIT:-60}"
RUN_WAIT="${RUN_WAIT:-30}"
CPU="${CPU:-cortex-a57}"

export PATH="${PATH}:/sbin:/usr/sbin"

QEMU_BIN="${QEMU:-$(command -v qemu-system-aarch64 || true)}"
if [ -z "$QEMU_BIN" ] || [ ! -x "$QEMU_BIN" ]; then
	echo "error: qemu-system-aarch64 not found" >&2; exit 1
fi
if [ ! -f "${IMGDIR}/Image" ]; then
	echo "error: no kernel image at ${IMGDIR}/Image -- build first" >&2; exit 1
fi

# ---- repack the rootfs so the freshly built BPF binary is inside ----------
echo "==> repacking rootfs image"
rm -f "${IMGDIR}/rootfs.ext4"
mkfs.ext4 -d "${ROOTFS_WRKDIR}" "${IMGDIR}/rootfs.ext4" 1024M >/dev/null

# ---- boot, drive the serial console with a scripted command list ----------
# Using a pty-free pipe: qemu reads stdin, so feed commands on a delayed pipe.
CMDS=$(cat <<EOF
echo MARK-LOGIN-OK
echo ==== sched_ext sysfs ====
ls /sys/kernel/sched_ext/
echo ==== state before ====
cat /sys/kernel/sched_ext/state
echo ==== running ${SCX_BIN_NAME} ====
${SCX_BIN_NAME} -p 50
echo SCX-EXIT-\$?
sleep ${RUN_WAIT}
echo ==== state after ====
cat /sys/kernel/sched_ext/state
echo ==== attach stats ====
for f in /sys/kernel/debug/scx/stats /sys/kernel/debug/scx/dsq; do
	echo ---\$f---; head -20 \$f 2>/dev/null || echo (absent)
done
echo ==== ps ====
ps -o pid,comm,cls 2>/dev/null || ps
echo MARK-DONE
poweroff -f
EOF
)

{
	sleep "$BOOT_WAIT"
	printf '%s\n' "$CMDS"
	sleep "$RUN_WAIT"
} | timeout $((BOOT_WAIT + RUN_WAIT + 90)) "$QEMU_BIN" \
	-nographic -M virt -cpu "$CPU" -smp "$SMP" -m "$MEM" \
	-kernel "${IMGDIR}/Image" \
	-drive id=disk0,file="${IMGDIR}/rootfs.ext4",if=none,format=raw \
	-device virtio-blk-device,drive=disk0 \
	-append "root=/dev/vda rw mem=${MEM}M console=ttyAMA0 rootwait" \
	-netdev user,id=net0 -device virtio-net-device,netdev=net0 \
	> "$LOG" 2>&1

echo "==> qemu exited, log: $LOG"