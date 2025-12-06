--- 
layout: post
title:  "struct - thread_info history"
author: fuqiang
date:   2025-11-25 11:00:00 +0800
categories: [task mgmt]
tags: [kernel, task_mgmt]
---

## no thread info

在早期的实现中(`v2.5.4-pre2`-), 并没有`thread_info` 数据结构，所有的信息
均存放在`task_struct`中, `task_struct` 末尾 位于栈顶部.

内存分配
```sh
do_fork
=> alloc_task_struct()
   (#define alloc_task_struct() ((struct task_struct *) __get_free_pages(GFP_KERNEL,1)))
```

> NOTE
>
> `__get_free_pages(, )`第二个参数是`order`大人，而并非page_number, 为此，我这纠
> 结了快一个小时

可以看到order为1，也就是分配两个PAGE. 为`THREAD_SIZE` 大小
```cpp
#define THREAD_SIZE (2*PAGE_SIZE)
```

而栈底则存放`pt_regs`, 我们来看下`copy_thread`函数

```sh
do_fork
=> copy_thread
   ## 第二个页的顶部
   => childregs = ((struct pt_regs *) (THREAD_SIZE + (unsigned long) p)) - 1;
   => struct_cpy(childregs, regs);
   => childregs->eax = 0;
   => childregs->esp = esp;
   => p->thread.eip = (unsigned long) ret_from_fork;
   ...
```

其copy了 pt_regs 的所有内容，并且比较关键的是, 赋值 eax 为`0`!, 这也就是
子进程`fork()`返回为0的原因. 另外, `p->thread.eip`赋值为`ret_from_fork`
这也就意味着, 当调度系统调度到新创建的子进程时，其直接从 `ret_from_fork`
执行并返回用户态.

需要注意的是，这里为什么要重新赋值esp呢? 原因是 sys_clone 支持重新设置esp:
```cpp
asmlinkage int sys_clone(struct pt_regs regs)
{
    unsigned long clone_flags;
    unsigned long newsp;

    clone_flags = regs.ebx;
    //here
    newsp = regs.ecx;
    if (!newsp)
        newsp = regs.esp;
    return do_fork(clone_flags, newsp, &regs, 0);
}
```

好了，关于这块我们暂时就记录这些，将在另外一篇文章中详细解释.

用下图总结下, 此版本`task_struct`, `pt_regs` 在 栈中的位置:

```
     +--------------+------------------
     | PT_REGS      |               P
     |              |               A
     +--------------+               G
     |              |               E
     |              |
     |              |               S
     |              |               I
     |              |               Z
     |              |               E
     |              |
     +--------------+-----------------
     |              |               P
     |              |               A
     |              |               G
     |              |               E
     |              |
     |              |               S
     +--------------+               I
     |              |               Z
     | TASK_STRUCT  |               E
     |              |
     +--------------+------------------  HIGH ADDRESS
```

## SPLIT task_struct && thread_info

在commit `9b10610a79a thread information block`中, 作者将task_struct
用slab进行分配, 而将另一个数据结构`thread_info`放在栈底部.

### page_alloc VS slab

使用slab有下面的几个好处:
1. 节省内核栈空间
2. 可以使用slab的缓存角色技术. (这个我个人认为是 作者想要用slab的主要原因)

缓存角色是为object加了一个偏移量，让不同的object落在不同的cacheline中，
非常适合同时访问多个object。

我们来看下之前的分配方式有什么问题。首先回忆下组相连的cache 原理。

**组相连cache原理:**
```
+------------------+---------+----------+
|tag               |set_index|tag_index |
+------------------+---------+----------+
```

* `set_index` bitsize 由`cache way`的数量决定.
* `tag_index`bitsize 由 一路中 cacheline 的数量决定

所以`set_index`, `tag_index`的总的bitsize由 
```
cache way * one way total cache size
```
也就是cache 的大小决定。

如果按照x86的`PAGE_SIZE(4096)`，如果cache大小小于4K，其必冲突。所以`slab`
不仅可以减少内存碎片，也非常适合同时访问多个小的object的场景，避免
cacheline冲突。

而对于`task_struct` 来说, 经常会有同时访问多个 `task_struct`的场景, 例如:
*  进程创建(`dup task_struct`)
*  进程调度

**相关改动**:

**task_struct 使用slab进行分配代码: (但是其拆分出一个thread_info数据结构)**
```diff
@@ -585,12 +624,10 @@ int do_fork(unsigned long clone_flags, unsigned long stack_start,
        }

        retval = -ENOMEM;
-       p = alloc_task_struct();
+       p = dup_task_struct(current);
        if (!p)
                goto fork_out;

-       *p = *current;
+#define alloc_thread_info() ((struct thread_info *) __get_free_pages(GFP_KERNEL,1))
+struct task_struct *dup_task_struct(struct task_struct *orig)
+{
+       struct task_struct *tsk;
+       struct thread_info *ti;
+
+       //thread_info 替代 task_struct 于栈底
+       ti = alloc_thread_info();
+       if (!ti) return NULL;
+
+       //task_struct 使用slab分配
+       tsk = kmem_cache_alloc(task_struct_cachep,GFP_ATOMIC);
+       if (!tsk) {
+               free_thread_info(ti);
+               return NULL;
+       }
+
+       //copy thread_info
+       *ti = *orig->thread_info;
+
+       //copy task_struct
+       *tsk = *orig;
+
+       tsk->thread_info = ti;
+       ti->task = tsk;
+       atomic_set(&tsk->usage,1);
+
+       return tsk;
+}
```

而在内核堆栈中，`task_struct`被另一个更为精简的数据结构 -- `thread_info` 替代,
该数据结构也非常简单, 除了`task_struct` 外，还有:
* **exec_domain**: execution domain(母鸡)
* **flags**: TIF
* **cpu**: 该进程目前所运行的cpu
* **addr_limit**: (母鸡)

```diff
+struct thread_info {
+       struct task_struct      *task;          /* main task structure */
+       struct exec_domain      *exec_domain;   /* execution domain */
+       __u32                   flags;          /* low level flags */
+       __u32                   cpu;            /* current CPU */
+
+       mm_segment_t            addr_limit;     /* thread address space:
+                                                  0-0xBFFFFFFF for user-thead
+                                                  0-0xFFFFFFFF for kernel-thread
+                                               */
+
+       __u8                    supervisor_stack[0];
+};
```

`thread_info`仅提供了少量的成员. 我们思考两个问题:

* 既然slab这么好用，为什么不将`thread_info` 也放到`task_struct`中
* 应该将什么样的数据结单独放到`thread_info`中

### why need thread_info NECESSARY

先说答案，为了省寄存器。

当cpu调度到该进程时，需要有个位置来保存`task_struct`的地址，否则
当上下文从用户态切到内核态时，内核空间找不到该数据结构。

该位置有以下需求:
* 位置固定
* per-cpu

寄存器恰好满足上面两个要求.

而

## TODO
- [ ] 在另外一篇文章中解释进程创建时，上下文情况

## 相关commit
1. v2.5.4-pre2-> v2.5.4-pre3, 将task_struct 和 thread_info 分离
   + [PATCH] thread information block
   + https://www.kernel.org/pub/linux/kernel/v2.5/ChangeLog-2.5.4
   + commit 9b10610a79a288a4dbac366b32970573405c4ed1
   + Author: David Howells <dhowells@redhat.com>
   + Date:   Wed Feb 6 22:56:27 2002 -0800

2. `task_struct`和`thread_info` 合并:
   ```
   commit c65eacbe290b8141554c71b2c94489e73ade8c8d
   Author: Andy Lutomirski <luto@kernel.org>
   Date:   Tue Sep 13 14:29:24 2016 -0700
   
       sched/core: Allow putting thread_info into task_struct
   ```

## 相关链接
1. [Linux Kernel: Threading vs Process - task_struct vs thread_info](https://stackoverflow.com/questions/21360524/linux-kernel-threading-vs-process-task-struct-vs-thread-info)
