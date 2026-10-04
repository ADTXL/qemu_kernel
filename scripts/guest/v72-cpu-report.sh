#!/bin/sh
echo "===== CPU REPORT BEGIN ====="
echo "nproc=$(nproc 2>/dev/null || echo '?')"
echo "possible=$(cat /sys/devices/system/cpu/possible)"
echo "online=$(cat /sys/devices/system/cpu/online)"
echo "present=$(cat /sys/devices/system/cpu/present)"
echo "cpuinfo_count=$(grep -c ^processor /proc/cpuinfo)"
echo "--- per-cpu ---"
for c in /sys/devices/system/cpu/cpu[0-9]*; do
  n=$(basename $c)
  echo "$n: online=$(cat $c/online 2>/dev/null) topology_physical=$(cat $c/topology/physical_package_id 2>/dev/null) core=$(cat $c/topology/core_id 2>/dev/null)"
done
echo "===== CPU REPORT END ====="
poweroff -f
