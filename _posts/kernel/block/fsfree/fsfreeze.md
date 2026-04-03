## freeze

```sh
ioctl_fsfreeze
=> freeze_super
```

## freeze_super comment

```cpp
/**
 * freeze_super - lock the filesystem and force it into a consistent state
 * @sb: the super to lock
 *
 * Syncs the super to make sure the filesystem is consistent and calls the fs's
 * freeze_fs.  Subsequent calls to this without first thawing the fs will return
 * -EBUSY.
 *
 * During this function, sb->s_writers.frozen goes through these values:
 *
 * SB_UNFROZEN: File system is normal, all writes progress as usual.
 *
 * SB_FREEZE_WRITE: The file system is in the process of being frozen.  New
 * writes should be blocked, though page faults are still allowed. We wait for
 * all writes to complete and then proceed to the next stage.
 *
 * SB_FREEZE_PAGEFAULT: Freezing continues. Now also page faults are blocked
 * but internal fs threads can still modify the filesystem (although they
 * should not dirty new pages or inodes), writeback can run etc. After waiting
 * for all running page faults we sync the filesystem which will clean all
 * dirty pages and inodes (no new dirty pages or inodes can be created when
 * sync is running).
 *
 * SB_FREEZE_FS: The file system is frozen. Now all internal sources of fs
 * modification are blocked (e.g. XFS preallocation truncation on inode
 * reclaim). This is usually implemented by blocking new transactions for
 * filesystems that have them and need this additional guard. After all
 * internal writers are finished we call ->freeze_fs() to finish filesystem
 * freezing. Then we transition to SB_FREEZE_COMPLETE state. This state is
 * mostly auxiliary for filesystems to verify they do not modify frozen fs.
 *
 * sb->s_writers.frozen is protected by sb->s_umount.
 */
```

freeze_super - 锁定文件系统并强制其进入一致状态

* 这个函数会同步超级块以确保文件系统的一致性，并调用文件系统的freeze_fs。在没
  有先解冻文件系统的情况下，后续对此函数的调用将返回 -EBUSY。

在这个函数中，sb->s_writers.frozen 会经历以下几个值：

* SB_UNFROZEN: 文件系统正常运行，所有写入操作都可以正常进行。
* SB_FREEZE_WRITE: 文件系统正在被冻结。新写入操作应该被阻止，但页面错误仍然被允许。
  我们等待所有写入操作完成后再进入下一阶段。
* SB_FREEZE_PAGEFAULT:

  冻结过程继续。现在，页面错误也被阻止了，但内部文件系统线程仍然可以修改文件系统
  （尽管它们不应该弄脏新的页面或索引节点），写回可以运行等。等待所有正在运行的
  页面错误后，我们同步文件系统，这将清除所有脏页面和索引节点（当同步运行时，不能创
  建新的脏页面或索引节点）。

* SB_FREEZE_FS:

  文件系统已被冻结。现在，所有内部的文件系统修改源都被阻止了（例如，对于需要这个
  额外保护的文件系统，XFS 在索引节点回收时的预分配截断）。这通常通过阻止新事务来
  实现。等待所有内部写入者完成后，我们调用 ->freeze_fs() 来完成文件系统的冻结。
  然后我们转换到 SB_FREEZE_COMPLETE 状态。这个状态主要是为了让文件系统验证它们不会修
  改冻结的文件系统。

  sb->s_writers.frozen 是由 sb->s_umount 保护的。
