# qemu_kernel — 在 QEMU 上学 Linux kernel

用 QEMU(arm64 virt) 搭一个最小可跑的环境，学习内核的启动、内存管理、调度、驱动与调试。

支持多个内核版本，源码树按需拉取，不塞进 git 仓库：

| 版本 | 源码树 | defconfig | 说明 |
| --- | --- | --- | --- |
| `v4.19` (默认) | `kernel/common` | `juno_defconfig` | 仓库内历史版本 |
| `v7.2` | `kernel/v7.2` | `juno_defconfig` | `scripts/setup-kernel.sh` 按需拉取 |
| `v7.3` | `kernel/v7.3` | `juno_defconfig` | 可选，约定同上 |

版本映射见 `configs/qemu/kernel-versions.mk`。

---

# 1. 准备环境

## 1.1 编译安装 qemu

参考 `qemu/readme.md`。也可以用系统自带的：

```
sudo apt install qemu-system-arm
```

`run_qemu.sh` / `make boot-test` 会优先用 `qemu/bin/qemu-system-aarch64`，
找不到再回退到系统 `qemu-system-aarch64`（也可用 `QEMU=/path/to/qemu` 指定）。

## 1.2 安装 toolchain

arm64 的 toolchain 有些文件大于 100M，不好直接上传，只上传了 arm32 的。
没有版本要求可以直接装：

```
# 32 bit
sudo apt-get install gcc-arm-linux-gnueabihf
# 64 bit
sudo apt install gcc-aarch64-linux-gnu
```

## 1.3 其它依赖

缺什么装什么，这是我编译时需要的：

```
sudo apt install bison flex openssl libssl-dev bc \
                 e2fsprogs qemu-system-arm
```

> `e2fsprogs` 提供 `mkfs.ext4`，打包 rootfs 和 `make boot-test` 都要用它。

---

# 2. 编译

## 2.1 获取内核源码树（v4.19 除外）

`v4.19` 已随仓库提供（`kernel/common`），其它版本要先拉源码：

```
# 从 torvalds/linux 拉指定 tag 到 kernel/<version>
scripts/setup-kernel.sh v7.2

# 或链接一个已有的本地内核树
scripts/setup-kernel.sh v7.2 --link /path/to/linux
```

## 2.2 编译

```
make                        # 打印可用的 target
make qemu-juno              # 默认版本 v4.19
make qemu-juno KERNEL_VERSION=v7.2
```

产物在 `work/juno/<version>/image/`：`Image`、`juno-r1.dtb`、`rootfs/`、
`rootfs.ext4`、`package/image.tar.gz`。

### 内存受限的机器

内核编译是内存大户。本机若内存紧张（例如 8G 机器上 swap 已满），
4 路并发很容易被 cgroup OOM killer 静默杀掉，表现为**编译中途无故退出**。
这时降低并发：

```
make qemu-juno KERNEL_VERSION=v7.2 JOBS=2
```

## 2.3 运行

用脚本：

```
./run_qemu.sh v7.2
```

或直接用 Makefile 的 `boot-test`（自动 `mkfs.ext4` + 起 QEMU，进 shell 后
`Ctrl-a x` 退出；`BOOT_TIMEOUT`/`SMP`/`MEM`/`QEMU_CPU` 可调）：

```
make boot-test KERNEL_VERSION=v7.2 BOOT_TIMEOUT=90
```

正常启动到 shell 长这样：

```
[    2.760162] virtio_blk virtio1: [vda] 2097152 512-byte logical blocks (1.07 GB/1.00 GiB)
[    4.364807] EXT4-fs (vda): mounted filesystem ... r/w with ordered data mode.
[    4.367556] VFS: Mounted root (ext4 filesystem) on device 254:0.
[    4.377808] VFS: Pivoted into new rootfs
[    4.462454] Run /sbin/init as init process

Processing /etc/profile... Done

~ #
```

退出：`Ctrl + a`，再按 `x`。

---

# 3. defconfig 说明

`configs/qemu/<version>/juno_defconfig` 是在 arm64 默认 defconfig 基础上**大幅裁剪**
过的精简版，只留 QEMU/Juno 上真正用得上的东西：

* **保留**：`virtio-blk` / `virtio-net` / `virtio-console`、`ext4`、`KVM`、
  `CONFIG_ARM64_VA_BITS_48`、`debugfs`、`ftrace` 全家桶
  (`FUNCTION_TRACER` / `DYNAMIC_FTRACE` / `FUNCTION_GRAPH_TRACER`)、
  `SCHEDSTATS`、`PROVE_LOCKING`、`DYNAMIC_DEBUG`。
* **裁掉**：一堆用不上的网卡/无线/GPU/PHY（`mlx5`、`ath10k/11k/12k`、`iwlwifi`、
  `nouveau`、`e1000e`、`r8169`…）、`UFS`、`NFC`、`BT`、USB gadget 等。

效果：选项约 511 → 157，模块 434 → 3，内核 `Image` 约 30M → 22M，编译明显更快。

需要改配置时：

```
make -C build/mk target=qemu-juno menuconfig KERNEL_VERSION=v7.2
```

# 4. 目录结构说明

```
configs/
  qemu/
    kernel-versions.mk     # 版本 -> 源码树/defconfig 映射
    fstab_ext              # 带外部盘启动时的 fstab
    v7.2/juno_defconfig    # 精简 defconfig
    busybox_defconfig      # busybox 配置
rootfs/
  busybox/                 # busybox 源码
  root_qemu/               # 叠加到 rootfs 的 etc/ (fstab / inittab / rcS / profile)
build/mk/Makefile          # 主构建逻辑（busybox -> vmlinux -> rootfs -> 打包）
scripts/setup-kernel.sh    # 按需拉取内核源码树
run_qemu.sh                # 启动脚本
kernel/common              # 仓库内 v4.19 源码树
kernel/<version>           # 其它版本（不入 git，脚本拉取）
work/juno/<version>/       # 构建产物
```

TODO
