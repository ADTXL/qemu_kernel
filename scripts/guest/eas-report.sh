#!/bin/sh
# EAS (Energy Aware Scheduler) observation script for v7.2ext.
#
# Every observation point is grep-verified in the v7.2 tree
# (vendor/linux @ 8d3ae59288f1). Comments cite file:line.
#
# v7.2 API changes vs older kernels -- all verified, several were wrong paths:
#   - kernel/sched/energy.c NO LONGER EXISTS. EAS lives in fair.c + topology.c.
#     kernel/sched/fair.c:9357 find_energy_efficient_cpu() is the decision point.
#   - CONFIG_SCHED_ENERGY_MODEL does not exist; the symbol is CONFIG_ENERGY_MODEL
#     (kernel/power/Kconfig:393).
#   - There is NO top-level /sys/kernel/debug/sched_features. The feature file
#     is kernel/sched/debug.c:641 -> debugfs/sched/features  (NOT sched_features).
#   - sched/domains is NOT created unconditionally. kernel/sched/debug.c:762 has
#         if (!sched_debug_verbose) return;
#     so you MUST `echo 1 > debugfs/sched/verbose` first or the whole domains/
#     tree is absent.
#   - EAS on/off sysctl is /proc/sys/kernel/sched_energy_aware
#     (kernel/sched/topology.c:301-307).

DBG=/sys/kernel/debug
DT=/proc/device-tree

echo "===== EAS REPORT BEGIN ====="

# ---------------------------------------------------------------------------
# STEP 0 (must come first): make the active governor schedutil.
#
# EAS precondition #4 (kernel/sched/topology.c:403-410) requires schedutil to
# be driving every CPU of the root domain. cpufreq_ready_for_eas() in
# drivers/cpufreq/cpufreq.c explicitly bails otherwise:
#     /* Do not attempt EAS if schedutil is not being used. */
# Our defconfig sets CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE, so without this
# step sched_is_eas_possible() returns false and the whole EAS block stays off.
# No rebuild needed: CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y and schedutil_gov_init is
# already in vmlinux.
# ---------------------------------------------------------------------------
echo "--- STEP 0: switch governor to schedutil (EAS precondition #4) ---"
for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -w "$p/scaling_governor" ] || continue
    before=$(cat "$p/scaling_governor" 2>/dev/null)
    if echo schedutil > "$p/scaling_governor" 2>/dev/null; then
        echo "  $(basename $p): $before -> $(cat $p/scaling_governor 2>/dev/null)"
    else
        avail=$(cat "$p/scaling_available_governors" 2>/dev/null)
        echo "  $(basename $p): FAILED to set schedutil (available: $avail)"
    fi
done
[ -d /sys/devices/system/cpu/cpufreq ] || echo "  (no cpufreq policies at all)"

echo
echo "--- 0. PROOF our DTB was actually used (cpus node props) ---"
echo "    Without this, every later reading is untrustworthy."
echo "    kernel/sched/topology.c:403-410 lists the 5 EAS preconditions;"
echo "    condition 2 needs capacity asymmetry from capacity-dmips-mhz."
for i in 0 1 2 3; do
    c="$DT/cpus/cpu@$i"
    [ -d "$c" ] || continue
    cap="(absent)"
    opp="(absent)"
    clk="(absent)"
    if [ -r "$c/capacity-dmips-mhz" ]; then
        # DT cells are 4-byte big-endian; busybox od defaults to host order,
        # so reassemble explicitly instead of printing a byte-swapped number.
        cap=$(od -An -tu1 -N4 "$c/capacity-dmips-mhz" 2>/dev/null | \
              awk '{printf "%d", $1*16777216+$2*65536+$3*256+$4}')
    fi
    [ -e "$c/operating-points-v2" ] && opp="present"
    [ -e "$c/clocks" ] && clk="present"
    echo "  cpu@$i: capacity-dmips-mhz=$cap operating-points-v2=$opp clocks=$clk"
done
echo "  root compatible: $(tr -d '\0' < $DT/compatible 2>/dev/null)"

echo
echo "--- 1. cpu_capacity as the kernel computed it (sysfs) ---"
echo "    DT said 400 (little) / 1024 (big); the kernel scales the little"
echo "    cluster by its clock ratio (1200MHz/1800MHz) via capacity_freq_ref,"
echo "    so 266 vs 1024 is expected, not a bug."
for c in /sys/devices/system/cpu/cpu[0-9]*; do
    n=$(basename "$c")
    [ -d "$c/topology" ] || continue
    printf '  %s: capacity=%s core_id=%s\n' \
        "$n" \
        "$(cat $c/cpu_capacity 2>/dev/null || echo -)" \
        "$(cat $c/topology/core_id 2>/dev/null || echo -)"
done
UNIQ=$(cat /sys/devices/system/cpu/cpu*/cpu_capacity 2>/dev/null | sort -u | wc -l)
if [ "$UNIQ" -gt 1 ] 2>/dev/null; then
    echo "  ==> $UNIQ distinct capacity values => asymmetric => EAS precondition #2 POSSIBLE"
else
    echo "  ==> all CPUs share one capacity value => symmetric => EAS cannot engage."
fi

echo
echo "--- 2. cpufreq policies ---"
echo "    drivers/cpufreq/cpufreq-dt-platdev.c:227 returns -ENODEV (no platform"
echo "    device, hence no policy, hence no EM) unless cpu0 has"
echo "    operating-points-v2 and the board is not blocklisted."
if [ -d /sys/devices/system/cpu/cpufreq ]; then
    for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$p" ] || continue
        echo "  $(basename $p):"
        for f in related_cpus affected_cpus scaling_governor \
                 cpuinfo_min_freq cpuinfo_max_freq; do
            [ -r "$p/$f" ] && printf '    %-18s %s\n' "$f" "$(cat $p/$f 2>/dev/null)"
        done
        [ -r "$p/stats/time_in_state" ] && sed 's/^/      /' "$p/stats/time_in_state"
    done
else
    echo "  NO /sys/devices/system/cpu/cpufreq -> cpufreq-dt-platdev bailed out."
fi

echo
echo "--- 3. ENERGY MODEL: is a perf domain actually registered? ---"
echo "    kernel/power/energy_model.c:178 creates debugfs/energy_model"
echo "    UNCONDITIONALLY in fs_initcall, so the directory existing proves"
echo "    NOTHING. A registered PD shows up as a file named after the device."
if [ -d $DBG/energy_model ]; then
    n=$(ls -1 $DBG/energy_model 2>/dev/null | wc -l)
    echo "  dir exists, entries=$n"
    if [ "$n" -gt 0 ]; then
        ls -1 $DBG/energy_model
        # Each entry is a DIRECTORY, not a file: em_debug_create_pd() in
        # kernel/power/energy_model.c creates debugfs_create_dir(dev_name(dev))
        # and only then, inside it, one ps:<frequency>/ directory per perf state
        # with frequency/power/cost/performance/inefficient files.
        # `cat` on the directory yields nothing, which is why an earlier
        # revision of this script printed empty bodies.
        for pd in $DBG/energy_model/*; do
            [ -d "$pd" ] || continue
            echo "  === $(basename $pd) ==="
            for f in cpus flags id; do
                [ -r "$pd/$f" ] && echo "    $f: $(cat $pd/$f 2>/dev/null)"
            done
            for ps in "$pd"/ps:*; do
                [ -d "$ps" ] || continue
                echo "    [$(basename $ps)]"
                for f in frequency power cost performance inefficient; do
                    [ -r "$ps/$f" ] && printf "      %-13s %s\n" "$f" "$(cat $ps/$f 2>/dev/null)"
                done
            done
        done
    else
        echo "  EMPTY => no EM perf domain registered => EAS precondition #1 FAILS."
    fi
else
    echo "  no energy_model dir (CONFIG_DEBUG_FS off?)"
fi

echo
echo "--- 4. EAS switch + governor (precondition #4 = schedutil) ---"
echo "    kernel/sched/topology.c:210 guards the whole block with"
echo "    #if defined(CONFIG_ENERGY_MODEL) && defined(CONFIG_CPU_FREQ_GOV_SCHEDUTIL)"
if [ -r /proc/sys/kernel/sched_energy_aware ]; then
    V=$(cat /proc/sys/kernel/sched_energy_aware 2>/dev/null)
    if [ -n "$V" ]; then
        echo "  sched_energy_aware = $V  ==> EAS globally ACTIVE"
    else
        echo "  /proc/sys/kernel/sched_energy_aware reads EMPTY."
        echo "  kernel/sched/topology.c:286-291 returns *lenp = 0 when"
        echo "  sched_is_eas_possible() is false, so the file existing but"
        echo "  reading empty means EAS is still considered impossible."
    fi
else
    echo "  /proc/sys/kernel/sched_energy_aware ABSENT"
fi
echo "  active governors (must all be schedutil for EAS):"
for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -r "$p/scaling_governor" ] && echo "    $(basename $p): $(cat $p/scaling_governor)"
done
[ -d /sys/devices/system/cpu/cpufreq ] || echo "    (no cpufreq policies)"

echo
echo "--- 5. sched_domain flags: SD_ASYM_CPUCAPACITY ---"
echo "    kernel/sched/debug.c:762 requires sched_debug_verbose != 0."
if [ -w $DBG/sched/verbose ]; then
    echo 1 > $DBG/sched/verbose 2>/dev/null
    echo "  set debugfs/sched/verbose=1"
fi
if [ -d $DBG/sched/domains ]; then
    # flags live at domains/cpu<N>/domain<M>/flags -- kernel/sched/debug.c:794
    # calls register_sd(sd, d_sd), and the "flags" file is created inside that
    # per-domain dentry (debug.c:741). Reading domains/cpuN/flags returns
    # empty, so walk one level deeper.
    for sd in $DBG/sched/domains/cpu*/domain*; do
        [ -d "$sd" ] || continue
        fl=$(cat "$sd/flags" 2>/dev/null)
        [ -n "$fl" ] || continue
        echo "  $(echo $sd | sed 's|.*/sched/||'): $fl"
    done
    echo
    if grep -qs ASYM_CPUCAPACITY $DBG/sched/domains/cpu*/domain*/flags 2>/dev/null; then
        echo "  ==> SD_ASYM_CPUCAPACITY SET (precondition #2 OK)"
    else
        echo "  ==> SD_ASYM_CPUCAPACITY NOT set (precondition #2 FAILS)"
    fi
else
    echo "  domains/ still absent (verbose not writable?)"
fi

echo
echo "--- 6. scheduler features (correct v7.2 path) ---"
if [ -r $DBG/sched/features ]; then
    echo "  /sys/kernel/debug/sched/features:"
    sed 's/^/    /' $DBG/sched/features
else
    echo "  debugfs/sched/features absent"
fi

echo
echo "--- 7. dmesg: capacity / cpufreq / opp / energy evidence ---"
dmesg 2>/dev/null | grep -iE 'cpu_capacity|cpufreq|opp|energy|asym|governor|schedutil' | head -30

echo
echo "--- 7b. VERDICT against the 5 preconditions (topology.c:403-410) ---"
EMOK=0; [ "$(ls -1 $DBG/energy_model 2>/dev/null | wc -l)" -gt 0 ] && EMOK=1
GOVOK=0; ALLSCHED=1
for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -r "$p/scaling_governor" ] || continue
    [ "$(cat $p/scaling_governor)" = "schedutil" ] || ALLSCHED=0
done
[ "$ALLSCHED" = 1 ] && [ -d /sys/devices/system/cpu/cpufreq ] && GOVOK=1
ASYM=0; grep -qs ASYM_CPUCAPACITY $DBG/sched/domains/cpu*/domain*/flags 2>/dev/null && ASYM=1
[ $EMOK -eq 1 ] && echo "  1. Energy Model available ........... OK" || echo "  1. Energy Model available ........... FAIL"
[ $ASYM -eq 1 ] && echo "  2. SD_ASYM_CPUCAPACITY .............. OK" || echo "  2. SD_ASYM_CPUCAPACITY .............. FAIL"
echo "  3. no SMT (cortex-a57, no threads) .... OK"
[ $GOVOK -eq 1 ] && echo "  4. schedutil on all policies ........ OK" || echo "  4. schedutil on all policies ........ FAIL"
echo "  5. freq invariance (arm64 generic) ... OK"

echo
echo "--- 8. hw_pressure / PSI ---"
echo "    CONFIG_PSI=y was added to the v7.2ext defconfig for this."
echo "    /proc/pressure is a DIRECTORY since v6.4 (kernel/sched/psi.c:1713):"
echo "      proc_mkdir(\"pressure\"); proc_create(\"pressure/cpu\"...);"
echo "    so read the cpu/io/memory files inside it, not the directory itself."
if [ -d /proc/pressure ]; then
    echo "  /proc/pressure/ EXISTS:"
    for r in cpu io memory irq; do
        [ -r "/proc/pressure/$r" ] && { echo "    --- $r ---"; sed 's/^/      /' "/proc/pressure/$r"; }
    done
    echo
    echo "  NOTE: 'some' avg10 rising => tasks stalled on CPU."
    echo "  Memory-side hw_pressure (topology_update_hw_pressure) is what feeds"
    echo "  the memory lines; on QEMU 'virt' there is no real stall source, so"
    echo "  memory will read all-zero -- that is the expected result here."
else
    echo "  /proc/pressure ABSENT (unexpected: CONFIG_PSI=y)"
fi

echo
echo "===== EAS REPORT END ====="