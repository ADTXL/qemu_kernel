#!/usr/bin/env python3
"""
Generate an EAS (Energy Aware Scheduler) teaching DTB for QEMU arm64 'virt'.

WHY WE CANNOT JUST USE QEMU's OWN DTB
-------------------------------------
1. QEMU's DTB cpu@N nodes have no `clocks`, no `operating-points-v2` and no
   `capacity-dmips-mhz` (verified: only device_type/compatible/reg/
   enable-method/phandle). cpufreq-dt's cpufreq_init() calls clk_get() and
   returns early when it fails, so a clock node is a hard requirement.

2. QEMU 'virt' rejects heterogeneous -cpu lists:
       -cpu cortex-a57,cortex-a53
       -> qemu-system-aarch64: Expected key=value format, found cortex-a53
   So there is no way to get two real CPU classes. Capacity therefore has to
   be faked purely in DT via `capacity-dmips-mhz`.

3. QEMU's generated DTB is regenerated on every boot and changes with -smp,
   so anything we add to it by hand is not reproducible. Hence: dump it, then
   patch it deterministically with this script.

THE TWO TRAPS THIS SCRIPT EXISTS TO AVOID
----------------------------------------
A) MUST be `fixed-factor`, NOT `fixed-rate`, and the properties are
   `clock-mult` / `clock-div` (NOT bare `mult` / `div`).
   drivers/clk/clk-fixed-rate.c only provides .recalc_rate/.recalc_accuracy
   and its own header comment says "rate is always a fixed value. No
   clk_set_rate support". cpufreq's set_target() calls
   dev_pm_opp_set_rate() -> clk_set_rate(), so a fixed-rate clock makes every
   frequency change fail.
   drivers/clk/clk-fixed-factor.c:73-78 provides .set_rate =
   clk_factor_set_rate, and clk_factor_set_rate() unconditionally `return 0;`
   with the comment "We must report success but we can do so unconditionally
   because clk_factor_determine_rate returns values that ensure this call is a
   nop." That is exactly what we want on a machine with no real clock tree.

   _of_fixed_factor_clk_setup() (clk-fixed-factor.c:331) hard-fails with -EIO
   if clock-div or clock-mult is missing. Getting this wrong is *silently*
   fatal downstream: the clock never registers, so OPP's clk_get() returns
   -EPROBE_DEFER, so no OPP table, so cpufreq-dt has no policy, so no energy
   model. The only visible symptom is
       "Fixed factor clock <cpu_little_clk> must have a clock-div property"
   in dmesg plus a bare
       "platform cpufreq-dt: deferred probe pending: (reason unknown)"
   -- the latter is silent because dev_err_probe() (opp/core.c:1625) drops
   -EPROBE_DEFER messages on purpose.

C) OPP sharing is decided by NODE POINTER, not by a cpus phandle.
   drivers/opp/of.c does NOT parse any "cpus" phandle property. What
   dev_pm_opp_of_get_sharing_cpus() does is:
       - read the operating-points-v2 phandle of this cpu -> np
       - if np has "opp-shared", walk every possible cpu and compare
         `if (np == tmp_np)` (i.e. both cpus point at the SAME node)
   So a cluster shares one cpufreq policy by having all its cpu nodes point at
   one identical opp-table node that carries `opp-shared`.

USAGE:
    gen-eas-dtb.py -o out.dtb [-s 4] [-c cortex-a57] [-m 512]

The generated DTB must be passed to QEMU with -dtb.

RUNTIME STEP STILL REQUIRED
---------------------------
EAS precondition #4 (kernel/sched/topology.c:403-410) demands the schedutil
governor; cpufreq_ready_for_eas() in drivers/cpufreq/cpufreq.c returns false
for any other governor. The defconfig default is 'performance', so the guest
script must do:

    echo schedutil > /sys/devices/system/cpu/cpufreq/policy*/scaling_governor

No kernel rebuild is needed for that -- CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y and
schedutil_gov_init is already in vmlinux.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

# CPU layout we teach with: 2 "little" + 2 "big".
# Index into this list == cpu id.
#   (name, compatible, capacity-dmips-mhz, clock symbol, opp symbol, opps)
# opps: (freq_hz, microvolt, energy_cost)
#
# The numbers are deliberately simple and hand-picked so the resulting
# energy profile is easy to reason about on paper:
#   - little: 4 steps, cheap, top cost 36k
#   - big:    5 steps, expensive, top cost 90k
# Running a small task on a big cpu costs 90k/36k = 2.5x more energy per unit
# work than running it on a little cpu at max freq, which is exactly the
# trade-off EAS is meant to expose.
LITTLE = [
    (300_000_000, 800_000, 8_000),
    (600_000_000, 850_000, 15_000),
    (900_000_000, 900_000, 24_000),
    (1_200_000_000, 950_000, 36_000),
]
BIG = [
    (600_000_000, 850_000, 20_000),
    (900_000_000, 900_000, 30_000),
    (1_200_000_000, 950_000, 45_000),
    (1_500_000_000, 1_000_000, 65_000),
    (1_800_000_000, 1_050_000, 90_000),
]

LITTLE_CAPACITY = 400
BIG_CAPACITY = 1024

# dynamic-power-coefficient, per cluster. Required for the energy model:
# drivers/opp/of.c dev_pm_opp_of_register_em() only registers an EM via one
# of two paths, and this is the reachable one:
#   1. "power" (micro-watts) per OPP -> dev_pm_opp_get_power() sums
#      opp->supplies[i].u_watt, which is populated from REGULATOR. With
#      CONFIG_REGULATOR=n (our case) it is always 0 -> dead end.
#   2. "dynamic-power-coefficient" on the cpu node -> dev_pm_opp_calc_power()
#      computes uW = cap * mV^2 * MHz / 1e6 (of.c:1504-1510). Needs only
#      opp-microvolt, which we already provide.
# NOTE: "energy-costs" is NOT read by v7.2 at all -- `git grep -c
# "energy-costs"` returns zero hits tree-wide. It was removed; do not use it.
LITTLE_POWER_COEFF = 100   # 100*950^2*1200/1e6 = 108.3 mW at max little OPP
BIG_POWER_COEFF = 180     # 180*1050^2*1800/1e6 = 357.2 mW at max big OPP

# Phandles we add. The base DTB from QEMU uses 0x8001..0x8007; stay above it.
PH_CPU = [0x8010, 0x8011, 0x8012, 0x8013, 0x8014, 0x8015, 0x8016, 0x8017]
PH_CLK_LITTLE = 0x8014
PH_CLK_BIG = 0x8015
PH_OPP_LITTLE = 0x8016
PH_OPP_BIG = 0x8017
PH_FIXED_FACTOR = 0x8013  # the 24MHz parent both derived clocks hang off


def die(msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(1)


def dump_base_dtb(smp, cpu, mem, qemu="qemu-system-aarch64"):
    """Ask QEMU for the DTB it would have used for this machine."""
    fd, path = tempfile.mkstemp(suffix=".dtb")
    os.close(fd)
    cmd = [
        qemu, "-machine", "virt,dumpdtb=%s" % path,
        "-cpu", cpu, "-smp", str(smp), "-m", str(mem),
    ]
    r = subprocess.run(cmd, capture_output=True)
    if r.returncode != 0:
        die("qemu dumpdtb failed: " + r.stderr.decode(errors="replace"))
    if not os.path.getsize(path):
        die("qemu produced an empty dtb")
    return path


def decompile(dtb):
    fd, dts = tempfile.mkstemp(suffix=".dts")
    os.close(fd)
    r = subprocess.run(["dtc", "-I", "dtb", "-O", "dts", "-o", dts, dtb],
                       capture_output=True)
    if r.returncode != 0:
        die("dtc decompile failed: " + r.stderr.decode(errors="replace"))
    return dts


def replace_cpus_node(dts_text, new_cpus_block):
    """Swap out the whole `cpus { ... };` node using brace matching.

    The base node is emitted by QEMU at one tab of indentation, but we do not
    rely on indentation at all -- we count braces so a reformatted DTB still
    works.
    """
    m = re.search(r"^\s*cpus\s*\{", dts_text, re.M)
    if not m:
        die("no `cpus {` node found in base DTB")
    start = m.start()

    i = dts_text.index("{", m.start())
    depth = 0
    while i < len(dts_text):
        if dts_text[i] == "{":
            depth += 1
        elif dts_text[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    else:
        die("unbalanced braces in cpus node")

    # include the trailing `;`
    end = dts_text.index(";", i) + 1
    return dts_text[:start] + new_cpus_block + dts_text[end:]


def build_cpus_block(ncpu):
    if ncpu != 4:
        die("this generator is written for exactly 4 CPUs "
            "(2 little + 2 big); got -s %d" % ncpu)

    cpu_ph = PH_CPU[:ncpu]
    half = ncpu // 2

    # Which CPUs are little vs big.
    kind = []           # "little" or "big", per cpu
    for i in range(ncpu):
        kind.append("little" if i < half else "big")

    L = []
    a = L.append
    a("\tcpus {")
    a("\t\t#address-cells = <0x01>;")
    a("\t\t#size-cells = <0x00>;")
    a("")
    a("\t\tcpu-map {")
    a("\t\t\tsocket0 {")
    # one cluster per kind, in first-appearance order
    clusters = []
    for i, k in enumerate(kind):
        if k not in clusters:
            clusters.append(k)
    for ci, k in enumerate(clusters):
        members = [i for i, kk in enumerate(kind) if kk == k]
        a("\t\t\t\tcluster%d {" % ci)
        for mi, cpu in enumerate(members):
            a("\t\t\t\t\tcore%d {" % mi)
            a("\t\t\t\t\t\tcpu = <0x%x>;" % cpu_ph[cpu])
            a("\t\t\t\t\t};")
        a("\t\t\t\t};")
    a("\t\t\t};")
    a("\t\t};")
    a("")

    for i in range(ncpu):
        k = kind[i]
        compat = "arm,cortex-a53" if k == "little" else "arm,cortex-a57"
        cap = LITTLE_CAPACITY if k == "little" else BIG_CAPACITY
        clk = "&clk_little" if k == "little" else "&clk_big"
        opp = "&opp_little" if k == "little" else "&opp_big"
        coeff = LITTLE_POWER_COEFF if k == "little" else BIG_POWER_COEFF
        a("\t\tcpu@%d {" % i)
        a("\t\t\tdevice_type = \"cpu\";")
        a("\t\t\tcompatible = \"%s\";" % compat)
        a("\t\t\treg = <0x%x>;" % i)
        a("\t\t\tenable-method = \"psci\";")
        a("\t\t\tphandle = <0x%x>;" % cpu_ph[i])
        # trap A: cpufreq_init() -> clk_get(cpu_dev, NULL) fails without this
        a("\t\t\tclocks = <%s>;" % clk)
        # capacity asymmetry -> drives SD_ASYM_CPUCAPACITY
        a("\t\t\tcapacity-dmips-mhz = <%d>;" % cap)
        # Without this the energy model is never registered:
        # dev_pm_opp_of_register_em() bails with -EINVAL.
        a("\t\t\tdynamic-power-coefficient = <%d>;" % coeff)
        # trap B: sharing is by identical node pointer + opp-shared
        a("\t\t\toperating-points-v2 = <%s>;" % opp)
        a("\t\t};")
        a("")
    a("\t};")
    return "\n".join(L)


def build_extra_nodes():
    L = []
    a = L.append
    a("")
    a("\t/* ---- EAS teaching nodes, appended by scripts/dtb/gen-eas-dtb.py ---- */")
    a("")
    a("\t/* 24 MHz parent. fixed-factor (NOT fixed-rate) because cpufreq's")
    a("\t * set_target() calls clk_set_rate() and fixed-rate has no set_rate op. */")
    a("\t/* NOTE: node labels must not contain '-' -- dtc parses '&ref-clock'")
    a("\t * as the label 'ref' followed by junk, so all labels here use '_'. */")
    a("\tref_clk: ref-clock {")
    a("\t\tcompatible = \"fixed-clock\";")
    a("\t\t#clock-cells = <0x00>;")
    a("\t\tclock-frequency = <0x16e3600>;  /* 24 MHz */")
    a("\t};")
    a("")
    a("\t/* Little cluster clock: 24MHz * 50 = 1200MHz ceiling. */")
    a("\tclk_little: cpu_little_clk {")
    a("\t\tcompatible = \"fixed-factor-clock\";")
    a("\t\t#clock-cells = <0x00>;")
    a("\t\tphandle = <0x%x>;" % PH_CLK_LITTLE)
    a("\t\tclocks = <&ref_clk>;")
    a("\t\tclock-mult = <0x32>;  /* 50 -> 1200 MHz */")
    a("\t\tclock-div = <0x1>;")
    a("\t};")
    a("")
    a("\t/* Big cluster clock: 24MHz * 75 = 1800 MHz ceiling. */")
    a("\tclk_big: cpu_big_clk {")
    a("\t\tcompatible = \"fixed-factor-clock\";")
    a("\t\t#clock-cells = <0x00>;")
    a("\t\tphandle = <0x%x>;" % PH_CLK_BIG)
    a("\t\tclocks = <&ref_clk>;")
    a("\t\tclock-mult = <0x4b>;  /* 75 -> 1800 MHz */")
    a("\t\tclock-div = <0x1>;")
    a("\t};")

    def opp_table(label, ph, opps):
        a("")
        a("\t/* %s */" % label)
        a("\topp_%s: %s-opp-table {" % (label, label))
        a("\t\tcompatible = \"operating-points-v2\";")
        a("\t\tphandle = <0x%x>;" % ph)
        a("\t\t/* REQUIRED for CPU sharing: dev_pm_opp_of_get_sharing_cpus()")
        a("\t\t * returns early unless this boolean is present. */")
        a("\t\topp-shared;")
        for (khz, uv, cost) in opps:
            mhz = khz // 1_000_000
            a("")
            a("\t\topp@%d {" % khz)
            a("\t\t\topp-hz = /bits/ 64 <%d>;" % khz)
            a("\t\t\tclock-hz = /bits/ 64 <%d>;" % khz)
            a("\t\t\topp-microvolt = <%d>;" % uv)
            a("\t\t\t/* KEPT FOR REFERENCE ONLY. v7.2 does not parse this")
            a("\t\t\t * property anywhere (git grep: 0 hits tree-wide); the")
            a("\t\t\t * energy model uses dynamic-power-coefficient instead. */")
            a("\t\t\tenergy-costs = <%d>;" % cost)
            a("\t\t\t/* human-readable note for the lecture */")
            a("\t\t\tdt-note = \"EAS %s @ %d MHz, cost %d\";" % (label, mhz, cost))
            a("\t\t};")
        a("\t};")

    opp_table("little", PH_OPP_LITTLE, LITTLE)
    opp_table("big", PH_OPP_BIG, BIG)
    return "\n".join(L)


def compile_dts(dts_text, out_dtb):
    fd, dts = tempfile.mkstemp(suffix=".dts")
    os.close(fd)
    with open(dts, "w") as f:
        f.write(dts_text)
    r = subprocess.run(["dtc", "-I", "dts", "-O", "dtb", "-o", out_dtb, dts],
                       capture_output=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr.decode(errors="replace"))
        die("dtc compile failed")
    if r.stderr:
        sys.stderr.write("dtc warnings:\n" + r.stderr.decode(errors="replace"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("-s", "--smp", type=int, default=4)
    ap.add_argument("-c", "--cpu", default="cortex-a57")
    ap.add_argument("-m", "--mem", type=int, default=512)
    ap.add_argument("--qemu", default="qemu-system-aarch64")
    ap.add_argument("--keep-dts", help="also write the patched source here")
    args = ap.parse_args()

    for tool in ("dtc", args.qemu):
        if not shutil.which(tool):
            die("%s not found in PATH" % tool)

    base = dump_base_dtb(args.smp, args.cpu, args.mem, args.qemu)
    dts = decompile(base)
    with open(dts) as f:
        text = f.read()

    text = replace_cpus_node(text, build_cpus_block(args.smp))
    # Splice the clock + OPP nodes in just before the root closing brace.
    idx = text.rstrip().rfind("};")
    if idx < 0:
        die("no root closing `};`")
    text = text[:idx] + build_extra_nodes() + "\n" + text[idx:]

    if args.keep_dts:
        with open(args.keep_dts, "w") as f:
            f.write(text)
    compile_dts(text, args.output)
    os.unlink(base)
    os.unlink(dts)
    print("wrote %s (%d bytes)" % (args.output, os.path.getsize(args.output)))


if __name__ == "__main__":
    main()