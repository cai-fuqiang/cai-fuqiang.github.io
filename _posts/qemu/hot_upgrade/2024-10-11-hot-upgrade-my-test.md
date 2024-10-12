--- 
layout: post
title:  "qemu hot update my test"
author: fuqiang
date:   2024-10-11 19:27:00 +0800
categories: [qemu,hot_upgrade]
tags: [qemu_hot_upgrade]
---


## cpr-reboot test (upstream已经合入, 直接用上游测试)

测试过程如下:

<details markdown=1 open>
<summary>测试过程</summary>

```sh
# org process
./qemu-system-x86_64 -machine type=q35 -object memory-backend-memfd,size=2G,id=ram0 -m 2G -monitor stdio
~/qemu-hotupdate> sh run.sh
QEMU 8.2.50 monitor - type 'help' for more information
(qemu) info status
VM status: running
(qemu) migrate_set_parameter mode cpr-reboot
(qemu) migrate_set_capability x-ignore-shared on
(qemu) migrate -d file:vm.state
(qemu) info status
VM status: paused (postmigrate)
(qemu) (qemu) quit
unknown command: '(qemu)'
(qemu) quit

# incoming
~/qemu-hotupdate> ./qemu-system-x86_64 -machine type=q35 -m 2G -incoming defer -monitor stdio
QEMU 8.2.50 monitor - type 'help' for more information
(qemu) info status
VM status: paused (inmigrate)
(qemu) migrate_set_parameter mode cpr-reboot
(qemu) migrate_set_capability x-ignore-shared on
(qemu) migrate_incoming file:vm.state
(qemu) info status
VM status: running
(qemu)

~/qemu-hotupdate> ls -lh |grep state
-rw------- 1 wang wang 5.9M Oct 11 22:00 vm.state ## 文件中保存的信息很少
```
</details>

## cpr-exec
## 编译问题

1. Werror 相关问题
   ```
   /home/wang/workspace/qemu/openEuler/qemu/include/qapi/qmp/qobject.h:49:17:
   error: ‘subqdict’ may be used uninitialized [-Werror=maybe-uninitialized]
   ```
   问题原因: 代码没写好

   解决方法: 增加`--extra-cflags="--disable-werror"`

2. 未定义符号`bpf_program__set_socket_filter`
   ```
   /home/wang/workspace/qemu/openEuler/qemu/build/../ebpf/ebpf_rss.c:52: undefined
   reference to `bpf_program__set_socket_filter'
   ```
   问题原因: `libbpf`和当前qemu版本不兼容

   解决方法: 直接注释

3. loongarch 相关代码编译不通过
   ```
   ../hw/loongarch/larch_3a.c:344:8: error: variable ‘ls3a5k_cpucfgs’ has initializer but incomplete type
     344 | struct kvm_cpucfg ls3a5k_cpucfgs = {
         |        ^~~~~~~~~~
   ../hw/loongarch/larch_3a.c:345:6: error: ‘struct kvm_cpucfg’ has no member named ‘cpucfg’
     345 |     .cpucfg[LOONGARCH_CPUCFG0] = CPUCFG0_3A5000_PRID,
         |      ^~~~~~
   ```

   问题原因: 不知道

   解决方法: 越过loongarch 编译，增加 `--targe-list-exclude=loongarch64-softmmu`

4. <font color=red size=4> 这里问题忘记记录了, 之后测试在记录</font>

   解决方法: 增加 `--enable-splice`

综合下来，执行configure的参数配置如下:
```
./configure --extra-cflags="-g -Wno-maybe-uninitialized  \
   -Wno-dangling-pointer -Wno-enum-int-mismatch" --enable-spice  \
   --disable-werror --target-list-exclude=loongarch64-softmmu
```

## 简单测试
执行下面命令启动虚拟机:
```sh
./qemu-system-x86_64 -machine type=q35 \
 -object memory-backend-memfd,size=2G,id=ram0,share=on \
 -m 2G -monitor stdio \
 -migrate-mode-enable cpr-exec  \
 -numa node,memdev=ram0 "
```

在monitor中依次执行下面命令，做`cpr-exec migrate`

```
migrate_set_parameter mode cpr-exec
migrate_set_parameter cpr-exec-args ./qemu-system-x86_64 -machine type=q35  -object memory-backend-memfd,size=2G,id=ram0,share=on -m 2G -monitor tcp::12345,server,nowait -migrate-mode-enable cpr-exec -numa node,memdev=ram0 -incoming defer
migrate file:/tmp/a.txt
```

测试发现 `monitor`中有如下报错:
```
(qemu) migrate file:/tmp/a.txt
configure accelerator pc-q35-6.2 start
QEMU 6.2.0 monitor - type 'help' for more information
(qemu) machine init start
qemu-system-x86_64: Device needs media, but drive is empty
qemu-system-x86_64: write ptoc eventnotifier failed
```

查看qemu相关进程

```sh
~/qemu-hotupdate> ps -o ppid,pid,comm -x |grep qemu
 212311  212312 qemu-system-x86
 212312  212488 qemu-system-x86 <defunct>
```

这表示子进程变成僵尸进程。我们来调试下问题原因。

## 调试

这里有一行报错
```
qemu-system-x86_64: Device needs media, but drive is empty
```
查看代码:
```
  1 hw/ide/core.c|2548 col 31| error_setg(errp, "Device needs media, but drive is empty");
  3 hw/scsi/scsi-disk.c|2387 col 27| error_setg(errp, "Device needs media, but drive is empty");
  5 hw/block/virtio-blk.c|1173 col 27| error_setg(errp, "Device needs media, but drive is empty");
```

目前在3个地方都打上断点, 断点断在:
```
(gdb) f 0
#0  ide_init_drive (s=s@entry=0x55eaaf05c030, blk=0x55eaae695c40, kind=kind@entry=IDE_HD, version=0x0, serial=0x0, model=0x0, wwn=0, cylinders=2, heads=16,
    secs=63, chs_trans=1, errp=0x7fffb4999a70) at ../hw/ide/core.c:2547
2547            if (!blk_is_inserted(s->blk)) {
```
查看设备:
```
(gdb) p s->blk->name
$4 = 0x55eaae695350 "ide0-hd0"
```

查看qtree
```
bus: main-system-bus
  dev: q35-pcihost, id ""
    bus: pcie.0
      dev: ich9-ahci, id ""
        bus: ide.2
          type IDE
          dev: ide-cd, id ""
            drive = "ide2-cd0"
        bus: ide.1
          type IDE
        bus: ide.0
          type IDE
```
继续执行:
```
(gdb) c
Continuing.
[Thread 0x7f78456186c0 (LWP 217603) exited]
[Thread 0x7f7845ffb6c0 (LWP 217602) exited]
[Thread 0x7f7846ffd6c0 (LWP 217600) exited]
[Thread 0x7f78477fe6c0 (LWP 217599) exited]
[Thread 0x7f7847fff6c0 (LWP 217598) exited]
[Thread 0x7f784cd1e6c0 (LWP 217597) exited]
[Thread 0x7f784cd21d40 (LWP 217596) exited]
[Thread 0x7f78467fc6c0 (LWP 217601) exited]
[New process 217596]
[Inferior 2 (process 217596) exited with code 01]
```

继续调试`ide_init_drive`
```
(gdb) n
ide_init_drive (s=s@entry=0x555f8349a4a0, blk=0x555f82ad53a0, kind=kind@entry=IDE_HD, version=0x0, serial=0x0, model=0x0, wwn=0, cylinders=2, heads=16, secs=63,
    chs_trans=1, errp=0x7fffae243680) at ../hw/ide/core.c:2548
2548                error_setg(errp, "Device needs media, but drive is empty");
(gdb) p s->blk->root
$9 = (BdrvChild *) 0x0
```
## 结合源端调试
使用下面命令进行调试:
```sh
cgdb ./build/qemu-system-x86_64 \
    -ex 'set args -m 2G \
    -machine type=q35' \
    -ex 'b ide_init_drive'
```

发现仅有一次断住, 打印如下:

```sh
(gdb) p s->blk->name
$1 = 0x555556b177b0 "ide2-cd0"
(gdb) p s->blk->dev->parent_bus->name
$2 = 0x55555754d7f0 "ide.2"
(gdb) p s->blk->dev->parent_bus->parent->parent_bus->name
$3 = 0x555556bce3c0 "pcie.0"
```

而调试目的端时, 我们在qemu进程启动后，使用gdb attach, 同样在`ide_init_driver`,
设置断点.
发现第一次断到了这里（和上面也提到的一样)
```sh
(gdb) p s->blk->name
$1 = 0x5614bc254ee0 "ide0-hd0"
(gdb) p s->blk->dev->parent_bus->name
$2 = 0x5614bcc7ec20 "ide.0"
(gdb) p s->blk->dev->parent_bus->parent->parent_bus->name
$3 = 0x5614bc2711f0 "pcie.0"
(gdb) p kind
$4 = IDE_HD
```

此时我们如果不修改kind值，则会在:
```sh
ide_init_driver
  => if kind != IDE_CD:
       blk_is_inserted return true
     
     if return true 
       error_setg("Device needs media, but drive is empty")
       return -1
```

错误退出，这里，我们暂时修改下kind, 修改为`IDE_CD`
```
(gdb) set kind=1
(gdb) p kind
$6 = IDE_CD
```
修改完之后，执行`c`
```
(gdb) p s->blk->name
$2 = 0x557c8942f4e0 "ide2-cd0"
(gdb) p s->blk->dev->parent_bus->name
$3 = 0x557c89dab350 "ide.2"
(gdb) p s->blk->dev->parent_bus->parent->parent_bus->name
$4 = 0x557c89421580 "pcie.0"
```
继续执行`c`
qemu-monitor打印
```
(qemu) machine init start
add rom file: vga.rom
add rom file: e1000e.rom
device init start
reset all devices
qemu enter main_loop
```
似乎这步成功了, 我们看下qemu进程状态:
```
~/qemu-hotupdate> ps -o ppid,pid,comm,state -x |grep qemu
279886  279887 qemu-system-x86 S
279887  280102 qemu-system-x86 S
```
父子进程都正常：

进入source monitor, 执行下面命令:
```
(qemu) info status
VM status: paused (inmigrate)
```

进入dest monitor 执行下面命令:
```
(qemu) info status
info status
VM status: paused (inmigrate)
(qemu) migrate_incoming file:/tmp/a.txt
migrate_incoming file:/tmp/a.txt
(qemu) info status
info status
VM status: running
```
source端monitor退出，qemu子进程 变为daemon
```
~/qemu-hotupdate> ps -o ppid,pid,comm,state -x |grep qemu
      1  280102 qemu-system-x86 S
```

迁移成功
我们在看下qtree
```
bus: main-system-bus
  dev: q35-pcihost, id ""
    bus: pcie.0
      dev: ich9-ahci, id ""
        bus: ide.1
          type IDE
        bus: ide.2
          type IDE
          dev: ide-cd, id ""
            drive = "ide2-cd0"
        bus: ide.0
          type IDE
          dev: ide-hd, id ""
            drive = "ide0-hd0"
```
发现dst端，居然多了一个`bus: ide.0`，上居然多添加了一个`ide0-hd0` device

## unwarranted ide0-hd0

## 参考链接

[openEuler_pull]: https://gitee.com/openEuler/qemu/pulls/569/commits

[cpr-exec][]

[bilibili视频]: https://www.bilibili.com/video/BV1gB4y1o7WF/?spm_id_from=333.999.0.0&vd_source=7b6e9d67dce90e6019e7489e4a65411d

[cpr-reboot]: https://www.qemu.org/docs/master/devel/migration/CPR.html
