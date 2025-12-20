--- 
layout: post
title:  "qemu hot_upgrade org patch"
author: fuqiang
date:   2024-10-11 19:27:00 +0800
categories: [qemu,hot_upgrade]
tags: [qemu_hot_upgrade]
---

## patch link

https://patchew.org/QEMU/1658851843-236870-1-git-send-email-steven.sistare@oracle.com/

## commit message 
This version of the live update patch series integrates live update into the
live migration framework.  The new interfaces are:
> integrates: 集成，融合
  * mode (migration parameter)
  * cpr-exec-args (migration parameter)
  * file (migration URI)
  * migrate-mode-enable (command-line argument)
  * only-cpr-capable (command-line argument)

Provide the cpr-exec and cpr-reboot migration modes for live update.  These
save and restore VM state, with minimal guest pause time, so that qemu may be
updated to a new version in between.  The caller sets the mode parameter
before invoking the migrate or migrate-incoming commands.

> 提供 cpr-exec 和 cpr-reboot 迁移模式用于实时更新。这些模式可以保存和恢复虚拟机
> 的状态，并将客户机的暂停时间降至最低，从而允许在此期间更新 QEMU 到新版本。
> 调用者在调用 migrate 或 migrate-incoming command 之前设置mode 参数。

In cpr-reboot mode, the migrate command saves state to a file, allowing
one to quit qemu, reboot to an updated kernel, start an updated version of
qemu, and resume via the migrate-incoming command.  The caller must specify
a migration URI that writes to and reads from a file.  Unlike normal mode,
the use of certain local storage options does not block the migration, but
the caller must not modify guest block devices between the quit and restart.
The guest RAM memory-backend must be shared, and the @x-ignore-shared
migration capability must be set, to avoid saving it to the file.  Guest RAM
must be non-volatile across reboot, which can be achieved by backing it with
a dax device, or /dev/shm PKRAM as proposed in
https://lore.kernel.org/lkml/1617140178-8773-1-git-send-email-anthony.yznaga@oracle.com
but this is not enforced.  The restarted qemu arguments must match those used
to initially start qemu, plus the -incoming option.

> 在 cpr-reboot 模式下，migrate 命令将状态保存到文件中，从而允许用户退出 QEMU，
> 重启到更新后的内核，启动更新后的 QEMU 版本，并通过 migrate-incoming 命令恢复。
> 调用者必须指定一个迁移 URI，该 URI 用于读写文件。与正常模式不同，某些本地存储\
> 选项的使用不会阻止迁移，但调用者在退出和重启之间不得修改客户机块设备。客户机的 
> RAM 内存后端必须是共享的，并且必须设置 @x-ignore-shared 迁移能力，以避免将其
> 保存到文件中。客户机的 RAM 必须在重启后保持非易失性，这可以通过使用 DAX 设备
> 或提议的 /dev/shm PKRAM 来实现，具体请参见 该链接，
>
> https://......
>
> 但这并不是强制性的。重启后的 QEMU 参数必须与最初启动 QEMU 时使用的参数匹配，
> 并加上 -incoming 选项。

The reboot mode supports vfio devices if the caller first suspends the guest,
such as by issuing guest-suspend-ram to the qemu guest agent.  The guest
drivers' suspend methods flush outstanding requests and re-initialize the
devices, and thus there is no device state to save and restore.  After
issuing migrate-incoming, the caller must issue a system_wakeup command to
resume.

> reboot 模式支持 VFIO 设备，前提是调用者首先暂停客户机，例如通过向 QEMU 
> 客户机代理发出 guest-suspend-ram 命令。客户机驱动程序的暂停方法会刷新未完成
> 的请求并重新初始化设备，因此无需保存和恢复设备状态。在发出 migrate-incoming
> 之后，调用者必须发出 system_wakeup 命令以恢复。

In cpr-exec mode, the migrate command saves state to a file and directly
exec's a new version of qemu on the same host, replacing the original process
while retaining its PID.  The caller must specify a migration URI that writes
to and reads from a file, and resumes execution via the migrate-incoming
command.  Arguments for the new qemu process are taken from the cpr-exec-args
migration parameter, and must include the -incoming option.

> 在 cpr-exec 模式下，migrate 命令将状态保存到文件中，并在同一主机上直接执行新版本
> 的 QEMU，替换原始进程，同时保留其 PID。调用者必须指定一个迁移 URI，该
> URI 用于读写文件，并通过 migrate-incoming 命令恢复执行。新 QEMU
> 进程的参数来自 cpr-exec-args 迁移参数，并且必须包含 -incoming 选项。

Guest RAM must be backed by a memory backend with share=on, but cannot be
memory-backend-ram.  The memory is re-mmap'd in the updated process, so guest
ram is efficiently preserved in place, albeit with new virtual addresses.
In addition, the '-migrate-mode-enable cpr-exec' option is required.  This
causes secondary guest ram blocks (those not specified on the command line)
to be allocated by mmap'ing a memfd.  The memfds are kept open across exec,
their values are saved in special cpr state which is retrieved after exec,
and they are re-mmap'd.  Since guest RAM is not copied, and storage blocks
are not migrated, the caller must disable all capabilities related to page
and block copy.  The implementation ignores all related parameters.

> 客户机 RAM 必须由一个共享内存后端支持（share=on），但不能是 memory-backend-ram。
> 内存在更新后的进程中会重新映射，因此客户机 RAM 在原地有效保存，
> 尽管会使用新的虚拟地址。此外，必须使用 -migrate-mode-enable cpr-exec 
> 选项。这将导致secondary guest RAM blocks（未在命令行中指定的那些）通过映射一个 
> memfd 来分配。memfd 在执行期间保持打开，其值保存在特殊的 CPR 状态中，
> 该状态在执行后被检索，并重新映射。由于客户机 RAM 不会被复制，存储块也
> 不会迁移，因此调用者必须禁用所有与页面和块复制相关的功能。实现将忽略所
> 有相关参数。

The exec mode supports vfio devices by preserving the vfio container, group,
device, and event descriptors across the qemu re-exec, and by updating DMA
mapping virtual addresses using VFIO_DMA_UNMAP_FLAG_VADDR and
VFIO_DMA_MAP_FLAG_VADDR as defined in
  https://lore.kernel.org/kvm/1611939252-7240-1-git-send-email-steven.sistare@oracle.com
and integrated in Linux kernel 5.12.

> 执行模式支持 VFIO 设备，通过在 QEMU 再次执行时保留 VFIO 容器、组、设备和事件描述符，
> 并使用 VFIO_DMA_UNMAP_FLAG_VADDR 和 VFIO_DMA_MAP_FLAG_VADDR 更新 DMA 映射的虚拟地址。
> 这些标志的定义可以在以下位置找到：
>
> https://......
>
> 并且合入到 Linux kernel 5.12

Here is an example of updating qemu from v7.0.50 to v7.0.51 using exec mode.
The software update is performed while the guest is running to minimize
downtime.

> 以下是使用执行模式将 QEMU 从 v7.0.50 更新到 v7.0.51 的示例。软件更新是在客
> 户机运行时进行的，以最小化停机时间。
```
window 1                                        | window 2
                                                |
# qemu-system-$arch ...                         |
  -migrate-mode-enable cpr-exec                 |
QEMU 7.0.50 monitor - type 'help' ...           |
(qemu) info status                              |
VM status: running                              |
                                                | # yum update qemu
(qemu) migrate_set_parameter mode cpr-exec      |
(qemu) migrate_set_parameter cpr-exec-args      |
  qemu-system-$arch ... -incoming defer         |
(qemu) migrate -d file:/tmp/qemu.sav            |
QEMU 7.0.51 monitor - type 'help' ...           |
(qemu) info status                              |
VM status: paused (inmigrate)                   |
(qemu) migrate_incoming file:/tmp/qemu.sav      |
(qemu) info status                              |
VM status: running                              |
```

Here is an example of updating the host kernel using reboot mode.
```

window 1                                        | window 2
                                                |
# qemu-system-$arch ... mem-path=/dev/dax0.0    |
  -migrate-mode-enable cpr-reboot               |
QEMU 7.0.50 monitor - type 'help' ...           |
(qemu) info status                              |
VM status: running                              |
                                                | # yum update kernel-uek
(qemu) migrate_set_parameter mode cpr-reboot    |
(qemu) migrate -d file:/tmp/qemu.sav            |
(qemu) quit                                     |
                                                |
# systemctl kexec                               |
kexec_core: Starting new kernel                 |
...                                             |
                                                |
# qemu-system-$arch mem-path=/dev/dax0.0 ...    |
  -incoming defer                               |
QEMU 7.0.51 monitor - type 'help' ...           |
(qemu) info status                              |
VM status: paused (inmigrate)                   |
(qemu) migrate_incoming file:/tmp/qemu.sav      |
(qemu) info status                              |
VM status: running                              |
```

