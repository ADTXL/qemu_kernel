# 1. 简介
学习kenel,使用qemu搭建环境

# 2. 使用说明

## 2.1 编译安装qemu

参考qemu/readme.md

## 2.2 安装toolchain

本来打算把toolchain也直接上传的，arm64的toolchain有些文件大于100M,不太好直接上传，只上传了arm32的toolchain.
如果对版本没有要求可以直接使用命令安装,

```
# 32 bit
sudo apt-get install gcc-arm-linux-gnueabihf
# 64 bit
sudo apt install gcc-aarch64-linux-gnu
```

## 2.3 编译

以编译和运行arm64为例

### 2.3.1  修改路径

运行脚本时需要修改脚本run_qemu中和路径"qemuBinPath"和"KernelRootPath"为真实的存在路径


### 2.3.2 编译

有些包没有的可能需要安装下，还有些缺少的根据编译报错安装即可，下面是我编译时需要的包

```
sudo apt install bison
sudo apt install flex
sudo apt install openssl
sudo apt install libssl-dev
sudo apt install bc
```

然后编译

```
user@ubuntu:~/txl/project/qemu_kernel$ make 
help       qemu-juno  
user@ubuntu:~/txl/project/qemu_kernel$ make qemu-juno 

```

### 2.3.3 运行

使用如下命令

```
 ./run_qemu.sh
```

如下所示：

```
user@ubuntu:~/txl/project/qemu_kernel$ ./run_qemu.sh 
run qemu without external filesystem
mke2fs 1.44.1 (24-Mar-2018)
创建一般文件 /home/user/txl/project/qemu_kernel/work/juno/image/rootfs.ext4
创建含有 512000 个块（每块 1k）和 128016 个inode的文件系统
文件系统UUID：1622ffcc-31cb-4170-82c6-8d6cdaafdbfe
超级块的备份存储于下列块： 
	8193, 24577, 40961, 57345, 73729, 204801, 221185, 401409

正在分配组表： 完成                            
正在写入inode表： 完成                            
创建日志（8192 个块） 完成
将文件复制到设备： 完成
写入超级块和文件系统账户统计信息： 已完成

[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x411fd070]
[    0.000000] Linux version 4.19.176 (user@ubuntu) (gcc version 7.5.0 (Ubuntu/Linaro 7.5.0-3ubuntu1~18.04), GNU ld (GNU Binutils for Ubuntu) 2.30) #1 SMP PREEMPT Wed Jun 29 05:23:10 PDT 2022
[    0.000000] Machine model: linux,dummy-virt
[    0.000000] Memory limited to 512MB
[    0.000000] efi: Getting EFI parameters from FDT:
[    0.000000] efi: UEFI not found.
[    0.000000] cma: Reserved 32 MiB at 0x000000005e000000
[    0.000000] NUMA: No NUMA configuration found
[    0.000000] NUMA: Faking a node at [mem 0x0000000040000000-0x000000005fffffff]
[    0.000000] NUMA: NODE_DATA [mem 0x5dfd9b80-0x5dfdb37f]
[    0.000000] Zone ranges:
[    0.000000]   DMA32    [mem 0x0000000040000000-0x000000005fffffff]
[    0.000000]   Normal   empty
[    0.000000] Movable zone start for each node
[    0.000000] Early memory node ranges
[    0.000000]   node   0: [mem 0x0000000040000000-0x000000005fffffff]
[    0.000000] Initmem setup node 0 [mem 0x0000000040000000-0x000000005fffffff]

......
[    2.074775] VFS: Mounted root (ext4 filesystem) on device 254:0.
[    2.085599] devtmpfs: mounted
[    2.260584] Freeing unused kernel memory: 768K
[    2.274304] Run /sbin/init as init process
mount: mounting tmpfs on /tmp failed: Invalid argument
mount: mounting sdcardfs on /sdcard failed: No such device
[    2.480362] EXT4-fs (vda): re-mounted. Opts: (null)

Processing /etc/profile... Done

~ # 
~ # ls
Makefile                findutils               printutils
applets                 home                    proc
archival                include                 procps
bin                     include2                root
busybox                 init                    runit
busybox.links           klibc-utils             sbin
busybox_unstripped      lib                     scripts
busybox_unstripped.map  libbb                   sdcard
busybox_unstripped.out  libpwdgrp               selinux
console-tools           linuxrc                 shell
coreutils               loginutils              sys
debianutils             lost+found              sysklogd
dev                     mailutils               system
docs                    miscutils               tmp
e2fsprogs               mnt                     usr
editors                 modutils                util-linux
etc                     networking              var
~ # 


```

如果想退出，按`Ctrl +a,然后再按x`即可。

# 3. 目录结构说明

TODO


