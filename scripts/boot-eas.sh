#!/bin/bash
# Launch the v7.2ext guest with the hand-built EAS DTB.
# Kept as a file (not a long one-liner) so the exec wrapper's command line
# stays short -- the wrapper sets oom_score_adj=1000 on its children, so a
# long-lived background qemu under memory pressure is the first thing the
# global OOM killer takes.
set -u

KERNEL_VERSION="${KERNEL_VERSION:-v7.2ext}"
SMP="${SMP:-4}"
MEM="${MEM:-512}"
LOG="${LOG:-/tmp/eas-boot.log}"
TIMEOUT="${TIMEOUT:-150}"

cd "$(dirname "$0")/.." || exit 1

I="work/juno/${KERNEL_VERSION}/image"
DTB="${DTB:-work/dtb/eas-virt-${SMP}.dtb}"

if [ ! -f "$I/Image" ]; then
    echo "missing kernel: $I/Image" >&2
    exit 1
fi
if [ ! -f "$DTB" ]; then
    echo "missing dtb: $DTB" >&2
    exit 1
fi

# Stay as killable as possible but not the OOM killer's first pick.
echo 500 > /proc/self/oom_score_adj 2>/dev/null

rm -f "$LOG"

qemu-system-aarch64 \
    -nographic \
    -M virt \
    -cpu cortex-a57 \
    -smp "$SMP" \
    -m "$MEM" \
    -kernel "$I/Image" \
    -dtb "$DTB" \
    -drive "id=disk0,file=$I/rootfs.ext4,if=none,format=raw" \
    -device virtio-blk-device,drive=disk0 \
    -append "root=/dev/vda rw mem=${MEM}M console=ttyAMA0 rootwait ${EXTRA_APPEND:-}" \
    > "$LOG" 2>&1 &
QPID=$!

echo "$QPID" > /tmp/eas-boot.pid
echo "qemu pid=$QPID log=$LOG smp=$SMP mem=$MEM"

# Watchdog: power the guest off once the report lands or time runs out.
(
    sleep "$TIMEOUT"
    kill -9 "$QPID" 2>/dev/null
) &
WD=$!

wait "$QPID" 2>/dev/null
kill "$WD" 2>/dev/null
echo "qemu exited"