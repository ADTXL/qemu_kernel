## 1. 下载
从qemu官网或者使用命令

```
wget https://download.qemu.org/qemu-5.0.0.tar.xz
```

## 2. 安装

1.安装依赖包

```
sudo apt-get install git libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev
```

2. 编译安装

其中，`--prefix`为qemu installed dir

```
tar xvJf qemu-5.0.0.tar.xz
cd qemu-5.0.0
./configure --target-list=arm-softmmu,arm-linux-user,aarch64-softmmu,aarch64-linux-user --prefix=/home/user/txl/project/qemu_kernel/qemu  --enable-virglrenderer
make -j6
make install

```

3. 测试版本

安装完成后测试版本

```
user@b10fa2:~/txl/project/qemu_kernel/qemu/bin$ ./qemu-system-arm --version 
QEMU emulator version 5.0.0

```
