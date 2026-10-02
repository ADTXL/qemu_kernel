#!/bin/sh
# Runs automatically from /etc/profile on the v7.2ext QEMU guest.
# Verifies that a sched_ext BPF scheduler really attaches and dispatches tasks.

echo ""
echo "===== SCHED_EXT TEST BEGIN ====="

echo "--- 0. mount debugfs (for authoritative scx stats) ---"
mkdir -p /sys/kernel/debug 2>/dev/null
mount -t debugfs none /sys/kernel/debug 2>&1 || echo "(mount rc=$?)"
ls /sys/kernel/debug/scx/ 2>&1

echo "--- 1. sysfs subsystem + state before ---"
ls /sys/kernel/sched_ext/ 2>&1
echo "state(before): $(cat /sys/kernel/sched_ext/state 2>&1)"
echo "root cgroup scx.enable(before): $(cat /sys/fs/cgroup/cgroup.scx.enable 2>&1)"

echo "--- 2. cpu topology ---"
echo "possible: $(cat /sys/devices/system/cpu/possible 2>&1)"
echo "online:   $(cat /sys/devices/system/cpu/online 2>&1)"

echo "--- 3. baseline: dispatch counters before attach ---"
cat /sys/kernel/debug/scx/stats 2>&1 | head -30

echo "--- 4. load scx_simple in background ---"
scx_simple > /tmp/scx_run.log 2>&1 &
SCX_PID=$!
echo "pid=$SCX_PID"
sleep 6

echo "--- 5. alive? ---"
kill -0 $SCX_PID 2>/dev/null && echo "ALIVE" || echo "DEAD"

echo "--- 6. BPF program counters (local=/global= dispatched by BPF) ---"
cat /tmp/scx_run.log 2>&1

echo "--- 7. state after attach ---"
echo "state(after): $(cat /sys/kernel/sched_ext/state 2>&1)"

echo "--- 8. authoritative stats after attach ---"
cat /sys/kernel/debug/scx/stats 2>&1 | head -30

echo "--- 9. switch_stats ---"
cat /sys/kernel/debug/scx/switch_stats 2>&1 | head -10

echo "--- 10. show all tasks (dp = dispatched count per cpu) ---"
cat /sys/kernel/debug/scx/show_stalls 2>/dev/null | head -3
echo "--- tasks with sched_ext policy (SCHED_EXT=7) ---"
for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    comm=$(cat $p/comm 2>/dev/null)
    # policy lives in /proc/<pid>/sched via 'policy' in chrt; fall back to comm
    echo "$pid $comm"
done 2>/dev/null | head -15

kill $SCX_PID 2>/dev/null
sleep 2
echo "state(final): $(cat /sys/kernel/sched_ext/state 2>&1)"
echo "===== SCHED_EXT TEST END ====="
echo ""