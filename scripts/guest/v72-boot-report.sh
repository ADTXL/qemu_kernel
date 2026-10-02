#!/bin/sh
# Auto-run from /etc/profile on the v7.2 (lean) QEMU guest.
# Proof-of-boot report: confirms which kernel actually booted and that the
# lean configuration is in effect.

echo ""
echo "===== V72-LEAN BOOT REPORT BEGIN ====="

echo "--- 1. kernel identity ---"
uname -a
echo "release: $(uname -r)"
echo "build:   $(cat /proc/sys/kernel/version 2>/dev/null)"

echo "--- 2. uptime / cmdline ---"
cat /proc/uptime
cat /proc/cmdline

echo "--- 3. root mount ---"
mount | grep -E " / | /proc | /sys " | head -5

echo "--- 4. cpu topology (2 vCPUs expected) ---"
echo "possible: $(cat /sys/devices/system/cpu/possible)"
echo "online:   $(cat /sys/devices/system/cpu/online)"
echo "nr_cpus:  $(grep -c ^processor /proc/cpuinfo)"

echo "--- 5. scheduler state (which classes are compiled in) ---"
echo "sched_features:  $(cat /sys/kernel/debug/sched_features 2>/dev/null || echo '(debugfs not mounted)')"
echo "pid_max:         $(cat /proc/sys/kernel/pid_max)"
ls /sys/kernel/debug/sched/ 2>/dev/null | head -8 || echo "(no debugfs/sched)"

echo "--- 6. lean check: sched_ext should be ABSENT (not in lean config) ---"
if [ -d /sys/kernel/sched_ext ]; then
	echo "UNEXPECTED: sched_ext present"
else
	echo "OK: no /sys/kernel/sched_ext (expected for lean profile)"
fi

echo "--- 7. lean check: BTF should be absent (DEBUG_INFO_BTF off) ---"
if [ -e /sys/kernel/btf/vmlinux ]; then
	echo "BTF present: $(ls -la /sys/kernel/btf/vmlinux)"
else
	echo "OK: no /sys/kernel/btf/vmlinux (expected for lean profile)"
fi

echo "--- 8. shell works ---"
echo "hello from busybox $(busybox | head -1)"

echo "--- 9. process count ---"
echo "tasks: $(ls -d /proc/[0-9]* | wc -l)"

echo "===== V72-LEAN BOOT REPORT END ====="
echo ""

# shut the guest down cleanly so the test terminates on its own
poweroff -f