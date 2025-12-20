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
   > Note
   >
   > 为了加快编译速度，可以只编译x86_64
   > ```
   > --target-list=x86_64-softmmu
   > ```

4. <font color=red size=4> 这里问题忘记记录了, 之后测试在记录</font>

   解决方法: 增加 `--enable-splice`

综合下来，执行configure的参数配置如下:
```
./configure --extra-cflags="-g -Wno-maybe-uninitialized  \
   -Wno-dangling-pointer -Wno-enum-int-mismatch" --enable-spice  \
   --disable-werror --target-list-exclude=loongarch64-softmmu
```

fedora 38 缺少依赖:
```
ninja-build
glib2-devel
pixman-devel
spice-server-devel
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
ide_init_drive
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

> 为了方便后续调试
>
> 我们将代码暂时做下面的微调:
> ```
> @@ -2525,6 +2527,7 @@ int ide_init_drive(IDEState *s, BlockBackend *blk, IDEDriveKind kind,
>      uint64_t nb_sectors;
> 
>      s->blk = blk;
> +    kind=1;
>      s->drive_kind = kind;
> ```


> !!!!!
>
> 2024-10-14在另外一台机器上测试不再复现!!!!
{: .prompt-warning}

## 子进程异常退出，产生僵尸进程

上面的测试虽然在`2024-10-14`在另一台机器上无法复现，但是暴露了另一个问题，
子进程异常退出后，似乎父进程没有回收到子进程资源，从而导致子进程变为僵尸
进程。该僵尸进程会在父进程迁移成功后，随着父进程退出，僵尸进程消失。

但是, 从需求上来说，还是应该尽量避免僵尸进程产生，此问题是一个BUG().


### 模拟测试
我们修改代码, 模拟下子进程异常退出:
```diff
@@ -47,6 +47,8 @@ int main(int argc, char **argv)

 int main(int argc, char **argv, char **envp)
 {
+    printf("NOLY FOR test, exit!!!\n");
+    return -1;
     qemu_init(argc, argv, envp);
     qemu_log("qemu enter main_loop\n");
     qemu_main_loop();

```
我们让其在main函数开始，退出子进程.

执行`cpr-exec`相关命令
```
(qemu) migrate file:/tmp/file.txt
NOLY FOR test, exit!!!
qemu-system-x86_64: write ptoc eventnotifier failed
```
查看相关进程:
```
fedora :: ~/qemu_test/build % ps aux |grep qemu
wang      492077  5.0  0.1 3474956 43948 pts/12  Sl+  16:09   0:04 ./qemu-system-x86_64 -machine type=q35 -object memory-backend-memfd,size=2G,id=ram0,share=on -m 2G -monitor stdio -migrate-mode-enable cpr-exec -numa node,memdev=ram0 -nographic --serial telnet:localhost:6666,server,nowait
wang      496565  0.1  0.0      0     0 pts/12   Z+   16:10   0:00 [qemu-system-x86] <defunct>
```

### 问题原因
在下面流程中:
```cpp
qmp_migrate
  => if (strstart(uri, "file:", &p))
  {
     ...
     cpr_exec();
     if (fork > 0) {
        ...
        父进程动作:
        ...
     } else {
        execvp();
     }
    
  }
```

父进程在fork后，没有获取子进程pid，也就没有wait()子进程. 我们需要添加该流程,
增加如下 PATCH

<details markdown=1>
<summary>patch代码折叠</summary>

```diff
diff --git a/include/sysemu/sysemu.h b/include/sysemu/sysemu.h
index 3e58f9cbaf..5fa7b01551 100644
--- a/include/sysemu/sysemu.h
+++ b/include/sysemu/sysemu.h
@@ -18,6 +18,7 @@ extern GStrv exec_argv;
 extern int eventnotifier_ptoc[2];
 extern int eventnotifier_ctop[2];
 extern RunState vm_run_state;
+extern pid_t cpr_exec_child;

 void qemu_add_exit_notifier(Notifier *notify);
 void qemu_remove_exit_notifier(Notifier *notify);
diff --git a/migration/migration.c b/migration/migration.c
index d878d512b9..22b8641676 100644
--- a/migration/migration.c
+++ b/migration/migration.c
@@ -2567,6 +2567,7 @@ void qmp_migrate(const char *uri, bool has_blk, bool blk,
     Error *local_err = NULL;
     MigrationState *s = migrate_get_current();
     const char *p = NULL;
+    pid_t child_pid;

     if (!migrate_prepare(s, has_blk && blk, has_inc && inc,
                          has_resume && resume, errp)) {
@@ -2603,9 +2604,11 @@ void qmp_migrate(const char *uri, bool has_blk, bool blk,
         cpr_preserve_fds();
         cpr_exec();
         vm_run_state = runstate_get();
-        if (fork() > 0) {
+        child_pid=fork();
+        if (child_pid > 0) {
             close(eventnotifier_ptoc[0]);
             close(eventnotifier_ctop[1]);
+            cpr_exec_child = child_pid;
             while (read(eventnotifier_ctop[0], &data, sizeof(data)) < 0) {
                 if (errno == EINTR)
                     continue;
diff --git a/softmmu/globals.c b/softmmu/globals.c
index 4f940bd7f3..29118f7313 100644
--- a/softmmu/globals.c
+++ b/softmmu/globals.c
@@ -75,3 +75,4 @@ bool cpr_exec_migrating = false;
 int eventnotifier_ptoc[2] = {-1, -1};
 int eventnotifier_ctop[2] = {-1, -1};
 RunState vm_run_state;
+pid_t cpr_exec_child = -1;
diff --git a/softmmu/runstate.c b/softmmu/runstate.c
index 4496ed564b..f365894a47 100644
--- a/softmmu/runstate.c
+++ b/softmmu/runstate.c
@@ -749,6 +749,8 @@ static bool main_loop_should_exit(void)
 {
     RunState r;
     ShutdownCause request;
+    int status;
+    pid_t child_pid;

     if (qemu_debug_requested()) {
         vm_stop(RUN_STATE_DEBUG);
@@ -768,6 +770,8 @@ static bool main_loop_should_exit(void)
             } while (ret < 0 && errno == EINTR);
             if (ret <= 0) {
                 error_report("write ptoc eventnotifier failed");
+                child_pid = waitpid(cpr_exec_child, &status, WNOHANG);
+                error_report("child process %d exit, status %d\n", child_pid, status);
                 MigrationState *s = migrate_get_current();
                 bdrv_invalidate_cache_all(&err);
                 exec_argv = NULL;
```

</details>

简单测试:

执行测试命令:
```
(qemu) migrate file:/tmp/file.txt
NOLY FOR test, exit!!!
qemu-system-x86_64: write ptoc eventnotifier failed
qemu-system-x86_64: child process 568774 exit, status 65280  # 回收到子进程
(qemu)
```

查看是否有僵尸进程:
```
fedora :: ~/qemu_test/build % ps aux |grep qemu |grep -v grep
wang      568716  4.1  0.1 3474956 45052 pts/3   Sl+  16:33   0:04 ./qemu-system-x86_64 -machine type=q35 -object memory-backend-memfd,size=2G,id=ram0,share=on -m 2G -monitor stdio -migrate-mode-enable cpr-exec -numa node,memdev=ram0 -nographic --serial telnet:localhost:6666,server,nowait
```

可以发现该patch，规避了这个问题.

<!--
## unwarranted ide0-hd0

### tmp
```
115│ static void pc_q35_init(MachineState *machine)
116│ {
         ...
290│     if (pcms->sata_enabled) {
291│         /* ahci and SATA device, for q35 1 ahci controller is built-in */
292│         ahci = pci_create_simple_multifunction(host_bus,
293│                                                PCI_DEVFN(ICH9_SATA1_DEV,
294│                                                          ICH9_SATA1_FUNC),
295│                                                true, "ich9-ahci");
296│         idebus[0] = qdev_get_child_bus(&ahci->qdev, "ide.0");
297│         idebus[1] = qdev_get_child_bus(&ahci->qdev, "ide.1");
298│         g_assert(MAX_SATA_PORTS == ahci_get_num_ports(ahci));
299│         ide_drive_get(hd, ahci_get_num_ports(ahci));
300├───────> ahci_ide_create_devs(ahci, hd);
301│     } else {
302│         idebus[0] = idebus[1] = NULL;
303│     }
```
-->

## 参考链接

[openEuler_pull]: https://gitee.com/openEuler/qemu/pulls/569/commits

[cpr-exec][]

[bilibili视频]: https://www.bilibili.com/video/BV1gB4y1o7WF/?spm_id_from=333.999.0.0&vd_source=7b6e9d67dce90e6019e7489e4a65411d

[cpr-reboot]: https://www.qemu.org/docs/master/devel/migration/CPR.html
