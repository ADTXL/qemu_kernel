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
cd buildroot/linux/qemu/arm
make -j6
```

### 2.3.3 运行

使用如下命令

```
cd buildroot/linux/qemu/arm
 ./run_qemu.sh
```

如下所示：

```
user@b10fa2dc8f66:~/txl/project/qemu_kernel/buildroot/linux/qemu/arm$ ./run_qemu.sh 
run qemu without external filesystem
mke2fs 1.44.1 (24-Mar-2018)
Creating regular file /home/user/txl/project/qemu_kernel/work/linux-qemu-arm-4_19/image/rootfs.ext4
Creating filesystem with 512000 1k blocks and 128016 inodes
Filesystem UUID: 61e2e1d6-dbfb-4068-a749-eba9e5bbfe54
Superblock backups stored on blocks: 
	8193, 24577, 40961, 57345, 73729, 204801, 221185, 401409

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (8192 blocks): done
Copying files into the device: done
Writing superblocks and filesystem accounting information: 
......
[    0.794850] devtmpfs: mounted
[    0.969362] Freeing unused kernel memory: 768K
[    0.971016] Run /sbin/init as init process
mount: mounting tmpfs on /tmp failed: Invalid argument
mount: mounting sdcardfs on /sdcard failed: No such device
[    1.102253] EXT4-fs (vda): re-mounted. Opts: (null)

Processing /etc/profile... Done

/ # ls
bin         home        lost+found  root        sys         usr
dev         lib         mnt         sbin        system      var
etc         linuxrc     proc        sdcard      tmp

```

如果想退出，按`Ctrl +a,然后再按x`即可。

# 3. 目录结构说明

TODO


