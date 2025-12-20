## 


## 相关commit
* `v2.5.4-pre2-> v2.5.4-pre3`, 将task_struct 和 thread_info 分离
  + https://www.kernel.org/pub/linux/kernel/v2.5/ChangeLog-2.5.4
  + commit 9b10610a79a288a4dbac366b32970573405c4ed1
  Author: David Howells <dhowells@redhat.com>
  Date:   Wed Feb 6 22:56:27 2002 -0800
  
      [PATCH] thread information block

* `task_struct`和`thread_info` 合并:
  ```
  commit c65eacbe290b8141554c71b2c94489e73ade8c8d
  Author: Andy Lutomirski <luto@kernel.org>
  Date:   Tue Sep 13 14:29:24 2016 -0700
  
      sched/core: Allow putting thread_info into task_struct
  ```
