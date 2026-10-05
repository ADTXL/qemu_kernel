# qemu_kernel — 在 QEMU 上学 Linux kernel

用 QEMU(arm64 virt) 搭一个最小可跑的环境，学习内核的启动、内存管理、**调度**、驱动与调试。

支持多个内核版本，源码树按需拉取，不塞进 git 仓库（一份 Linux 树约 2 GB）：

| 版本 | 源码树 | defconfig | 定位 |
| --- | --- | --- | --- |
| `v4.19` (默认) | `kernel/common` | `juno_defconfig` | 仓库内历史版本，用于和旧内核对比 |
| `v7.2` | `kernel/v7.2` | `juno_defconfig` | **lean 教学基线**，编译快、无实验特性 |
| `v7.2ext` | `kernel/v7.2`（同一份树） | `juno_defconfig` | 实验变体：`SCHED_CLASS_EXT` + `DEBUG_INFO_BTF` |
| `v7.3` | `kernel/v7.3` | `juno_defconfig` | 可选，约定同上 |

版本映射见 `configs/qemu/kernel-versions.mk`。

`v7.2` 与 `v7.2ext` 共用源码树，**只有 defconfig 不同**，这样切换变体不用重新拉源码：

```
v7.2     Image 22.1 MB   SCHED_CLASS_EXT=无   BTF=无   ← 教学 / ftrace
v7.2ext  Image 26.1 MB   SCHED_CLASS_EXT=有   BTF=有   ← sched_ext / EAS 实验
```

---

# 1. 准备环境

## 1.1 编译安装 qemu

参考 `qemu/readme.md`。也可以直接用系统自带的：

```
sudo apt install qemu-system-arm
```

`run_qemu.sh` / `make boot-test` 的查找顺序：`qemu/bin/qemu-system-aarch64` →
系统 `qemu-system-aarch64`。也可用 `QEMU=/path/to/qemu` 显式指定。

## 1.2 安装 toolchain

```
sudo apt-get install gcc-aarch64-linux-gnu     # 64 bit
sudo apt-get install gcc-arm-linux-gnueabihf   # 32 bit（部分 target 需要）
```

## 1.3 其它依赖

```
sudo apt install bison flex openssl libssl-dev bc \
                 e2fsprogs qemu-system-arm
```

> `e2fsprogs` 提供 `mkfs.ext4`（通常在 `/sbin`），打包 rootfs 和 `make boot-test` 都要用。

## 1.4 只在编译 `v7.2ext`（sched_ext）时额外需要

| 依赖 | 用途 | 备注 |
| --- | --- | --- |
| `clang` + `lld` | 编 `tools/sched_ext` 的 BPF 程序 | `LLVM=1` 走 clang，链接用 `ld.lld` |
| `pahole >= 1.26` | 生成 BTF 时写入 kfunc decl tag | Ubuntu 自带 1.25 **不够**，见 §6.1 |
| `libdw-dev` | pahole 编译依赖 | `apt install libdw-dev` |
| arm64 `libelf`/`zlib`/`zstd` | `resolve_btfids` 静态链接 | 可能需要加 Ubuntu ports 源 |

内存紧张时 `pahole` 需要约 1.9 GB RSS，建议配一个 swapfile，否则容易被 OOM killer 杀掉。

---

# 2. 编译

## 2.1 获取内核源码树（v4.19 除外）

`v4.19` 已随仓库提供（`kernel/common`），其它版本先拉源码：

```
# 从 torvalds/linux 拉指定 tag 到 kernel/<version>
scripts/setup-kernel.sh v7.2

# 或链接一个已有的本地内核树（省磁盘 / 省时间）
scripts/setup-kernel.sh v7.2 --link /path/to/linux
```

## 2.2 编译

```
make                                    # 打印可用 target
make qemu-juno                          # 默认版本 v4.19
make qemu-juno KERNEL_VERSION=v7.2      # lean 教学基线
make qemu-juno KERNEL_VERSION=v7.2ext   # sched_ext 实验变体
```

产物在 `work/juno/<version>/image/`：`Image`、`juno-r1.dtb`、`rootfs/`、
`rootfs.ext4`、`package/image.tar.gz`。

各版本输出互相隔离（`work/juno/<ver>/`），可以同时存在多个变体。

### 内存受限的机器

内核编译是内存大户。8 G 机器上 swap 满了以后，多路并发很容易被 OOM killer
**静默**杀掉，表现为「编译中途无故退出」。这时降低并发：

```
make qemu-juno KERNEL_VERSION=v7.2 JOBS=2
```

实测耗时（4 核 / 8 G / `JOBS=2`）：`v7.2` 从 `olddefconfig` 到 `Image` 约 **56 分钟**。
`v7.2ext` 含 BTF 生成会更慢（`pahole` 阶段要约 1.9 GB RSS），但没有干净的
全量计时数据，暂不给具体数字。

## 2.3 单独构建某一阶段

顶层 Makefile 透传了这几个目标：

```
make vmlinux      KERNEL_VERSION=v7.2     # 只编内核
make qemu_rootfs  KERNEL_VERSION=v7.2     # 只做 rootfs
make boot-test    KERNEL_VERSION=v7.2     # 编 + 打包 + 起 QEMU
make clean        KERNEL_VERSION=v7.2
```

## 2.4 改配置

```
make -C build/mk target=qemu-juno menuconfig KERNEL_VERSION=v7.2
```

会在 `configs/qemu/<ver>/juno_defconfig` 上生成精简后的 defconfig 并写回。

> ⚠️ 内核树的 `ARCH` 是**从环境变量读的**，`O=` 不会帮你记住它。
> 手动跑内核 make 时必须显式带上：
> `make O=<objtree> ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig`
> **平时请走项目 Makefile**（它已经 `export ARCH := arm64`）。

---

# 3. 运行

```
./run_qemu.sh v7.2                 # 脚本方式（默认 4 核）
SMP=8 MEM=1024 ./run_qemu.sh v7.2  # 可调 vCPU 数 / 内存
```

或用 Makefile（自动 `mkfs.ext4` + 起 QEMU）：

```
make boot-test KERNEL_VERSION=v7.2 BOOT_TIMEOUT=90 SMP=4 MEM=1024
```

可用变量：`BOOT_TIMEOUT`(60) / `SMP`(4) / `MEM`(512) / `QEMU_HW`(virt) / `QEMU_CPU`(cortex-a57)。

> ⚠️ **`-smp` 超过 `CONFIG_NR_CPUS` 会被内核剪掉**，而且**没有 boot 参数能绕过**
> （`nr_cpus=` 只能调小、`maxcpus=` 在 arm64 的 DT 路径上不生效）。
> 改 `-smp` 前先看 §6.8。

正常启动到 shell：

```
[    2.760162] virtio_blk virtio1: [vda] 2097152 512-byte logical blocks (1.07 GB/1.00 GiB)
[    4.364807] EXT4-fs (vda): mounted filesystem ... r/w with ordered mode.
[    4.367556] VFS: Mounted root (ext4 filesystem) on device 254:0.
[    4.377808] VFS: Pivoted into new rootfs
[    4.462454] Run /sbin/init as init process

Processing /etc/profile... Done

~ #
```

退出：`Ctrl + a`，再按 `x`。

## 3.1 guest 里有什么

静态 busybox（`/bin/busybox`），`/sbin/init` 是它的软链，`/etc/inittab` 里
`::respawn:-/bin/sh` 直接给一个 shell。debugfs 由 `/etc/fstab` 自动挂载：

```
debugfs /sys/kernel/debug debugfs defaults 0 0
```

所以 `/sys/kernel/debug/sched/` 开箱可用。

> ⚠️ **`sched_features` 在两个版本间改名 + 挪位置了**，跨版本写脚本要注意：
>
> | | v4.19 | v7.2 |
> | --- | --- | --- |
> | 路径 | `/sys/kernel/debug/sched_features` | `/sys/kernel/debug/sched/features` |
> | 创建代码 | `debugfs_create_file("sched_features", 0644, NULL, …)` | `debugfs_create_file("features", 0644, debugfs_sched, …)` |
>
> v4.19 挂在 debugfs **根**（父节点 `NULL`），v7.2 挪进了 `sched/` 子目录并改名。
> 找调度器开关用 `/sys/kernel/debug/sched/features`（v7.2），
> 别照抄老教程里的 `/sys/kernel/debug/sched_features`。

> `rootfs/init`、`rootfs/applets/` 等看起来是「目录」而不是可执行文件 ——
> 这是 busybox `O=` 构建不完全独立，源码树被一起拷进来了。
> 内核 `execve("/init")` 失败后会 fallback 到 `/sbin/init`，**不影响启动**，
> 不是 bug。

---

# 4. defconfig 说明

`configs/qemu/<version>/juno_defconfig` 是在 arm64 默认 defconfig 基础上**大幅裁剪**
过的版本，只留 QEMU/Juno 上真正用得上的东西。

`v7.2` (lean) 的实测裁剪幅度：

| | 选项行 | `=y` | `=m` | Image |
| --- | --- | --- | --- | --- |
| v7.2 原始 `arch/arm64/configs/defconfig` | 1971 | — | — | — |
| `v7.2` lean | **140** | 135 | 0 | 22.1 MB |
| `v7.2ext` 实验 | 147 | 141 | 0 | 26.1 MB |

`olddefconfig` 之后实际只剩 3 个模块（`ip_tunnel.ko`、`sit.ko`、`tunnel4.ko`）。

* **保留**：`virtio-blk` / `virtio-net` / `virtio-console`、`ext4`、`KVM`、
  `CONFIG_ARM64_VA_BITS_48`、`debugfs`、`ftrace` 全家桶
  (`FUNCTION_TRACER` / `DYNAMIC_FTRACE` / `FUNCTION_GRAPH_TRACER`)、
  `SCHEDSTATS`、`PROVE_LOCKING`、`DYNAMIC_DEBUG`、
  `CONFIG_ARCH_VEXPRESS=y`（Juno DTB 由它守卫，见 §6.2）。
* **裁掉**：一堆用不上的网卡/无线/GPU/PHY（`mlx5`、`ath10k/11k/12k`、`iwlwifi`、
  `nouveau`、`e1000e`、`r8169`…）、`UFS`、`NFC`、`BT`、USB gadget 等。
* **`v7.2ext` 额外加**：`SCHED_CLASS_EXT`、`DEBUG_INFO_BTF`、`CPUFREQ_DT`、`PM_OPP`。

> ⚠️ 别写 `CONFIG_DEBUG_INFO_REDUCED`。它与 `CONFIG_DEBUG_INFO_BTF` **互斥**，
> 而 `olddefconfig` 会**静默**丢弃后者，连带把 `SCHED_CLASS_EXT` 一起去掉 ——
> 不看 `.config` 完全发现不了。

> ⚠️ v7.x 里 `CONFIG_SCHED_TUNE`、`CONFIG_SCHED_DEBUG` 已不存在，defconfig 里写了会报错。

---

# 5. 验证脚本

`scripts/guest/` 下是**放进 guest rootfs 执行**的脚本，`scripts/` 下是 host 侧启动器。

| 脚本 | 位置 | 作用 |
| --- | --- | --- |
| `v72-boot-report.sh` | guest | v7.2 开机报告 + lean 性自检（断言无 `sched_ext`、无 BTF） |
| `sched-ext-test.sh` | guest | 验证 `scx_enabled()` 从 `disabled` 翻到 `enabled` |
| `test-sched-ext.sh` | host | 重新打包 rootfs + 起 QEMU |
| `setup-kernel.sh` | host | 按需拉取内核源码树 |
| `eas-report.sh` | guest | EAS 实验：切 governor + 逐条核对 5 个前置条件 + 打印 EM 功耗表 |
| `boot-eas.sh` | host | 用自建 EAS DTB 起 v7.2ext guest |
| `dtb/gen-eas-dtb.py` | host | 生成带 OPP/clock/capacity 的异构 DTB |

### 为什么脚本要放进 rootfs

**QEMU 的 stdin 管道不可靠**：guest 能正常启动到 shell，但管道里 `printf` 过去的
命令收不到。所以改成把脚本放进 rootfs、由 `/etc/profile` 触发。

触发是 **opt-in** 的，不污染常规开机：

```sh
# guest:/etc/profile 末尾
[ -f /usr/bin/.run-boot-report ] && /usr/bin/v72-boot-report.sh
```

### 手动跑一次

```sh
# 1. 放进 rootfs
cp scripts/guest/v72-boot-report.sh work/juno/v7.2/image/rootfs/usr/bin/
chmod +x work/juno/v7.2/image/rootfs/usr/bin/v72-boot-report.sh

# 2. 在 guest /etc/profile 加一行 opt-in 触发（见上）

# 3. 重新打包 + 启动
mkfs.ext4 -d work/juno/v7.2/image/rootfs work/juno/v7.2/image/rootfs.ext4 1024M
./run_qemu.sh v7.2
```

`v7.2` lean 的实测输出：

```
Linux (none) 7.2.0 #3 SMP PREEMPT_DYNAMIC aarch64
/dev/root on / type ext4 (rw,relatime)
possible: 0-1   online: 0-1   nr_cpus: 2
no /sys/kernel/sched_ext     ← lean 应无 ✓
no /sys/kernel/btf/vmlinux   ← lean 应无 ✓
BusyBox v1.36.0.git    tasks: 57
```

`v7.2ext` 加载 sched_ext 的实测输出：

```
sched_ext: BPF scheduler "simple" enabled
local=4  global=0
local=11 global=2
...
state(before): disabled  →  state(after): enabled
```

---

# 6. 已知坑

## 6.1 pahole 必须 >= 1.26 才能编 sched_ext

`KF_IMPLICIT_ARGS` 的 kfunc 需要 BTF 里有 `<name>_impl` 条目，由
`tools/bpf/resolve_btfids/main.c` 生成 —— 但它**依赖 pahole >= 1.26 的
`decl_tag_kfuncs` 特征**（`scripts/Makefile.btf` 里有版本门控）。

Ubuntu 自带 pahole 1.25 → 没有该特征 → `_impl` 条目全缺 → 加载报
`kernel function btf_id NNNNN does not have a valid func_proto`。

查特性要用专用选项，**`--help` 里查不到**：

```sh
$ pahole --supported_btf_features      # 1.27 独有
encode_force,var,float,decl_tag,type_tag,enum64,
optimized_func,consistent_func,decl_tag_kfuncs,reproducible_build
$ pahole-1.25 --supported_btf_features
unrecognized option
```

装 1.27（注意 `make install` 把 `libdwarves_*.so.1` 放在 `/usr/local/lib`，
那是**非标准 multiarch 路径**，ldconfig 缓存里没有，要手工软链）：

```sh
apt install -y libdw-dev
git clone --depth 1 --branch v1.27 https://git.kernel.org/pub/scm/devel/pahole/pahole.git
cd pahole && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local ..
make -j2 && sudo make install

mkdir -p /usr/local/lib/x86_64-linux-gnu
for l in emit reorganize; do
  sudo ln -sf /usr/local/libdwarves_$l.so.1.0.0 /usr/local/lib/x86_64-linux-gnu/
done
sudo ln -sf /usr/local/libdwarves.so.1.0.0 /usr/local/lib/x86_64-linux-gnu/
sudo ldconfig
```

## 6.2 Juno DTB 需要显式开 `CONFIG_ARCH_VEXPRESS`

`arch/arm64/boot/dts/arm/Makefile` 里 juno 的 dtb 由 `dtb-$(CONFIG_ARCH_VEXPRESS)`
守卫。不开就静默不生成 `juno-r1.dtb`。

## 6.3 `ARCH` 靠环境传，`O=` 不记得

见 §2.4。手动 `make O=$O olddefconfig` 会把 `.config` 重写成 **x86**，
然后开始编 `arch/x86/...`，并污染共享目录里已编译的 `.o`。
已经跑歪的话：

```sh
find $O -name '*.o' -newer $O/vmlinux.unstripped -delete
rm -rf $O/arch/x86
```

## 6.4 busybox `defconfig` 会交互阻塞

`make defconfig` 在遇到新选项时会提问 `(NEW)`，非交互环境下直接挂住。
构建系统已经加了 `</dev/null`（`build/mk/Makefile` 的 `busybox` 目标）。

## 6.5 guest 是静态环境

guest 里只有静态 busybox，**动态链接的 BPF 程序跑不起来**。交叉工具链产物需要
静态重链：

```sh
aarch64-linux-gnu-gcc -static -o scx_simple.static \
  <obj>/scx_simple.o <obj>/libbpf.a -lelf -lz -lzstd -lpthread
aarch64-linux-gnu-readelf -d scx_simple.static | grep -c NEEDED   # 必须是 0
```

## 6.6 `.gitignore` 的 `qemu/` 会吞掉 `configs/qemu/`

裸写 `qemu/` 在**任意层级**都匹配，会把 `configs/qemu/` 一起忽略，
`configs/qemu/v7.2ext/juno_defconfig` 因此进不了仓库。已锚定成 `/qemu/`。

验证 ignore 规则要用 `--no-index`（默认对**已跟踪**文件不报 ignore，会误判）：

```sh
git check-ignore -v --no-index qemu/readme.md                 # 应命中 /qemu/
git check-ignore -v --no-index configs/qemu/v7.2/juno_defconfig  # 应无命中
```

## 6.7 v7.2 的 sched_ext 没有 debugfs 接口

`/sys/kernel/debug/scx/{stats,switch_stats}` 在 v7.2 **不存在**，
`CONFIG_DEBUG_FS=y` 也没用 —— 内核侧根本没实现，不是配置问题。

v7.2 可用的观测面：

* `/sys/kernel/sched_ext/{state,enable_seq,hotplug_seq,nr_rejected,switch_all}`
* BPF 侧自己的 map（`scx_simple` 的 `stats`，`local=`/`global=` 就是它）
* 内核日志 `sched_ext: BPF scheduler "X" enabled/disabled`

> scx 的可观测性接口**跨版本变动很大**，写实验脚本不能照抄别的版本。

---

## 6.8 `-smp` 加不上去？问题在 `CONFIG_NR_CPUS`，不在 DTB

QEMU `virt` 机器**自己生成 DTB**，而且核数**跟着 `-smp` 变**（实测 `-smp 4/8/16`
→ DTB 里 4/8/16 个 `cpu` 节点）。`run_qemu.sh` **没有传 `-dtb`**，所以 DTB 是对的。

真正剪掉 CPU 的是**内核自己**：

```
[    0.000000] Number of cores (4) exceeds configured maximum of 2 - clipping
[    0.317036] smp: Brought up 1 node, 2 CPUs
```

剪枝发生在 `arch/arm64/kernel/smp.c:760`：

```c
if (cpu_count > nr_cpu_ids)
        pr_warn("Number of cores (%d) exceeds configured maximum of %u - clipping\n",
                cpu_count, nr_cpu_ids);
...
for (i = 1; i < nr_cpu_ids; i++) {   /* ← 循环边界也是 nr_cpu_ids */
```

而 `nr_cpu_ids` 来自 `CONFIG_NR_CPUS`。原来的 defconfig 写的是 `=2`。

### 为什么 boot 参数救不了

| 参数 | 行为 | 能否加大 |
| --- | --- | --- |
| `nr_cpus=N` | `kernel/smp.c:995` 要求 `N < nr_cpu_ids` 才 `set_nr_cpu_ids(N)` | ❌ 只能调小 |
| `maxcpus=N` | 改的是 `setup_max_cpus`，但 arm64 走 DT 路径，循环边界是 `nr_cpu_ids` | ❌ 不生效 |

⇒ **只能改 `CONFIG_NR_CPUS` 重编**，改完 `make vmlinux KERNEL_VERSION=<ver>`。

### 怎么确认自己踩到了

```sh
# 1. 看有没有剪枝警告（决定性证据）
grep "exceeds configured maximum" boot.log

# 2. guest 里核对（scripts/guest/v72-cpu-report.sh）
nproc; cat /sys/devices/system/cpu/possible
```

当前两个 defconfig 都是 `CONFIG_NR_CPUS=8`，`SMP` 默认 4 —— 想上 8 核直接
`SMP=8 ./run_qemu.sh v7.2` 即可，不用重编。超过 8 才需要再改 config。

> 顺带一提：`juno-r1.dtb`（板级 DTB，本仓库构建时会拷进 `image/`）里只有
> **2 个 A57 + 4 个 A53**，而且 `run_qemu.sh` 根本没把它传给 QEMU。
> 它只对 **riscv `fw_jump`** 那条启动路径有意义（`build/mk/Makefile:201`
> 的 `FW_PAYLOAD_FDT_PATH`）。arm64 + `-kernel` 路径用的是 QEMU 自生成 DTB。

# 7. 目录结构

```
configs/
  qemu/
    kernel-versions.mk       # 版本 -> 源码树/defconfig 映射
    <ver>/juno_defconfig     # 每个版本一份精简 defconfig
    busybox_defconfig        # busybox 配置
    fstab_ext                # 带外部盘启动时的 fstab
  busybox_arm64_config       # busybox 补充配置（关掉与新头文件冲突的 applet）
rootfs/
  busybox/                   # busybox 源码
  root_qemu/                 # 叠加到 rootfs 的 etc/ (fstab / inittab / rcS / profile)
build/mk/Makefile            # 主构建逻辑（busybox -> vmlinux -> rootfs -> 打包）
scripts/
  setup-kernel.sh            # 按需拉取内核源码树
  test-sched-ext.sh          # host 侧：打包 + 起 QEMU
  boot-eas.sh                # host 侧：用自建 EAS DTB 起 v7.2ext
  dtb/gen-eas-dtb.py         # 生成异构 DTB（OPP + clock + capacity）
  guest/                     # 放进 guest rootfs 执行的脚本
run_qemu.sh                  # 启动脚本
kernel/common                # 仓库内 v4.19 源码树
kernel/<version>             # 其它版本（不入 git，脚本拉取）
work/juno/<version>/         # 构建产物，按版本隔离
```

---

# 8. TODO

- [x] ~~修 QEMU 只起 2 核~~ → 是 `CONFIG_NR_CPUS=2` 剪的，不是 DTB 问题，见 §6.8
- [x] ~~经 DT OPP + `cpufreq-dt` 造 energy model~~ → 5 个前置全部 OK，见 §9
- [ ] 更多 sched_ext 调度器（`scx_flatcg` / `scx_pair` / `scx_central` 等）

---

# 9. EAS 实验（v7.2ext）

用自建 DTB 在 QEMU 上让 **EAS（Energy Aware Scheduler）真正生效**，并逐条核对
`kernel/sched/topology.c:403-410` 列出的 5 个前置条件。

## 9.1 为什么必须自建 DTB

QEMU `virt` 自带的 DTB 有三个硬伤：

| 问题 | 依据 |
| --- | --- |
| `cpu@N` 没有 `clocks` | `cpufreq-dt.c` 的 `cpufreq_init()` 在 `clk_get()` 失败时直接 return |
| 没有 `operating-points-v2` | 建不出 OPP 表 → 无 policy → 无 energy model |
| 不支持异构 `-cpu` | `qemu-system-aarch64 -cpu cortex-a57,cortex-a53` 直接报错 |

而且 QEMU 生成的 DTB **每次启动都重算**（跟着 `-smp` 变），手改不可复现。
所以流程是：dump 出基线 → 脚本打补丁。

```sh
# 生成（2 little + 2 big，含 OPP / clock / capacity）
python3 scripts/dtb/gen-eas-dtb.py -o work/dtb/eas-virt-4.dtb -s 4

# 起 guest（自动带上 -dtb 并触发 guest 侧报告）
./scripts/boot-eas.sh
```

## 9.2 DTB 里的两个坑（都踩过，都已修）

**坑 1：clock 必须是 `fixed-factor-clock` + `clock-mult`/`clock-div`**

不是 `fixed-clock`，也不能用裸 `mult`/`div`。依据 `drivers/clk/clk-fixed-factor.c:331`：

```c
if (of_property_read_u32(node, "clock-div", &div)) {
        pr_err("%s Fixed factor clock <%pOFn> must have a clock-div property\n", ...);
        return ERR_PTR(-EIO);
}
```

写错属性名的后果是**静默的连锁失败**：

```
时钟注册失败 → OPP 的 clk_get() 返回 -EPROBE_DEFER
             → 建不出 OPP 表 → 无 cpufreq policy → 无 energy model
```

dmesg 里只看得到两条弱线索：

```
_of_fixed_factor_clk_setup Fixed factor clock <cpu_little_clk> must have a clock-div property
platform cpufreq-dt: deferred probe pending: (reason unknown)
```

第二句之所以是 `(reason unknown)`，是因为 `dev_err_probe()` 对 `-EPROBE_DEFER`
**故意不打印**（`drivers/opp/core.c:1625`）。先用裸 `mult`/`div` 写了，就是被这个坑卡住。

> 为什么是 `fixed-factor` 而不是 `fixed-rate`：`clk-fixed-rate.c` 只有
> `.recalc_rate`，没有 `.set_rate`；而 cpufreq 的 `set_target()` 会调
> `clk_set_rate()`。`clk-fixed-factor.c:73` 的 `clk_factor_set_rate()` 无条件
> `return 0`（注释说明 `clk_factor_determine_rate` 保证这是 no-op），正是需要的。

**坑 2：OPP 共享靠节点指针，不是 `cpus` phandle**

`drivers/opp/of.c` 根本不解析 `cpus` 属性。`dev_pm_opp_of_get_sharing_cpus()` 是：

```c
if (np == tmp_np)
        cpumask_set_cpu(cpu, cpumask);   /* 比的是节点指针 */
```

所以同一 cluster 共享 policy 的办法是：所有 cpu 节点指向**同一个**
带 `opp-shared` 的 opp-table 节点。

## 9.3 energy model 靠什么注册

`drivers/opp/of.c` 的 `dev_pm_opp_of_register_em()` 只有两条路：

| 路径 | 条件 | 本项目 |
| --- | --- | --- |
| `power`（微瓦） | `dev_pm_opp_get_power()` 累加 `opp->supplies[i].u_watt`，来自 regulator | ❌ `CONFIG_REGULATOR=n`，恒为 0 |
| `dynamic-power-coefficient` | cpu 节点有这个属性 + `opp-microvolt` | ✅ 走这条 |

**注意**：`energy-costs` 在 v7.2 **全树零命中**（`git grep -c energy-costs` = 0），
该属性早已移除，不要再用。DTB 里留着只是给讲义做对照。

## 9.4 EAS 前置条件 #4：必须切 schedutil

`kernel/sched/topology.c:210` 的整块代码被这个 guard 包着：

```c
#if defined(CONFIG_ENERGY_MODEL) && defined(CONFIG_CPU_FREQ_GOV_SCHEDUTIL)
```

而 `cpufreq_ready_for_eas()`（`drivers/cpufreq/cpufreq.c`）明确要求 schedutil：

```c
/* Do not attempt EAS if schedutil is not being used. */
if (!cpufreq_policy_is_good_for_eas(cpu)) { ... return false; }
```

defconfig 默认是 `performance`，所以 guest 脚本先切：

```sh
echo schedutil > /sys/devices/system/cpu/cpufreq/policy*/scaling_governor
```

**不用重编**：`CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y` 已在，`schedutil_gov_init` 在 vmlinux 里。

> 一个容易误判的现象：EAS 不可行时 `/proc/sys/kernel/sched_energy_aware`
> **不是缺失，而是读出空字符串** —— `topology.c:286` 的 handler 在
> `sched_is_eas_possible()` 为 false 时 `*lenp = 0`。

## 9.5 实测结果（`-smp 4`，v7.2ext）

5 个前置条件全部 OK，`sched_energy_aware = 1`：

```
  1. Energy Model available ........... OK
  2. SD_ASYM_CPUCAPACITY .............. OK
  3. no SMT (cortex-a57, no threads) .... OK
  4. schedutil on all policies ........ OK
  5. freq invariance (arm64 generic) ... OK
```

**energy model 功耗表**（`/sys/kernel/debug/energy_model/`）：

| cluster | 频率 | power (uW) | cost | performance |
| --- | --- | --- | --- | --- |
| little (cpu0-1) | 300M | 19200 | 2909 | 66 |
| little | 600M | 43350 | 3259 | 133 |
| little | 900M | 72900 | 3663 | 199 |
| little | 1200M | 108300 | 4071 | 266 |
| big (cpu2-3) | 600M | 78030 | 2288 | 341 |
| big | 1200M | 194940 | 2858 | 682 |
| big | 1800M | 357210 | 3488 | 1024 |

cost 交叉点就是 EAS 要解的题：**big 在 ~1.1GHz 以上每单位算力更省电**，
所以这不是编出来的假 trade-off。

`SD_ASYM_CPUCAPACITY`（+`_FULL`）出现在每个 cpu 的 `domain1`（根域）；
`cpu_capacity` = 266（little）/ 1024（big）。little 的 266 是 DT 里写的 400
被 1200/1800 时钟比缩放后的结果（`capacity_freq_ref`，`arch_topology.c:252`），**符合预期**。

`/proc/pressure/`：`cpu some avg10=3.69`、`irq full avg10=9.87`。memory 全 0 ——
这是预期结果：QEMU `virt` 没有真实 stall 源去驱动 `topology_update_hw_pressure()`。

## 9.6 已知噪声

每次运行时切 governor 都会触发一串 lockdep splat：

```
WARNING: kernel/cpu.c:527 at lockdep_assert_cpus_held
  rebuild_sched_domains_energy -> partition_sched_domains_locked
```

原因是 kworker 跑 `rebuild_sd_workfn` 时没持 `cpus_lock`，而内核开了
`CONFIG_PROVE_LOCKING`。与 DTB 无关，对实验无害，但提前知道免得白查。

## 9.7 下一步可做的 A/B

最干净的验证是改 `/proc/sys/kernel/sched_energy_aware`（写 0 关、写 1 开），
对比 `sched:sched_compute_energy` tracepoint —— 该 tracepoint 只在 EAS
真正参与放置时触发，是「EAS 确实在工作」的最强证据。