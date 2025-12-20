--- 
layout: post
title:  "task_struct & thread_info history"
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


另外, `task_struct` 包含了另外一个和架构相关强项关的数据结构`thread_struct`,
该数据结构主要用于在进程切换前保存进程的上下文信息(主要是CPU上下文(寄存器))

用下图总结下, 此版本`task_struct`, `pt_regs` 在 栈中的位置:

```
     +--------------+-----                          arch information
     | PT_REGS      |   P                           +-------------+
     |              |   A                      +----+thread_struct|
     +--------------+   G                      |    +-------------+
     |              |   E       ||    S        |    | esp0,eip,esp|
     |              |           ||    T        |    +-------------+
     |              |   S       ||    A        |    | fs,gs       |
     |              |   I       ||    C        |    +-------------+
     |              |   Z       ||    K        |    | ...         |
     |              |   E       ||             |    +-------------+
     |              |           ||    G        |
     +--------------+-----      ||    R        |
     |              |   P       ||    O        |
     |              |   A       ||    W        |
     |              |   G       ||    T        |
     |              |   E       ||    H        |
     |              |          \  /            |
     |              |   S       \/             |
     +--------------+   I                      |
     |              |   Z                      |
     | TASK_STRUCT  |   E                      |
     |              |                          |
     |              +--------------------------+
     |              |
     +--------------+------  HIGH ADDRESS
```

这样的一个好处是，在汇编代码中, 能通过简单的几行指令, 访问`task_struct`成员:

例如下面代码，访问`task_struct->addr_limit`:
```
.globl __get_user_1
__get_user_1:
	movl %esp,%edx
	andl $0xffffe000,%edx
	cmpl addr_limit(%edx),%eax
	jae bad_get_user
1:	movzbl (%eax),%edx
	xorl %eax,%eax
	ret
```
简单来说就是通过esp 做一些对齐偏移操作, 就很方便的锁定到`task_struct`的地址,
然后再加上数据结构成员在task_struct 偏移. 就可以得到该成员的地址了。

## SPLIT task_struct && thread_info

在commit `9b10610a79a thread information block`中, 作者将task_struct
用slab进行分配, 而将另一个数据结构`thread_info`放在栈底部. 修改如下:

```
     +------------------+---                      task_struct alloc by slab
     | PT_REGS          |  P                           +-------------+
     |                  |  A                      +----+TASK_STRUCT  |
     +------------------+  G                      |    +-------------+
     |                  |  E       ||    S        |    | esp0,eip,esp|
     |                  |          ||    T        |    +-------------+
     |                  |  S       ||    A        |    | fs,gs       |
     |                  |  I       ||    C        |    +-------------+
     |                  |  Z       ||    K        |    | ...         |
     |                  |  E       ||             |    +-------------+
     |                  |          ||    G        |
     +------------------+----      ||    R        |
     |                  |  P       ||    O        |
     |                  |  A       ||    W        |
     |                  |  G       ||    T        |
     |                  |  E       ||    H        |
     |                  |         \  /            |
     |                  |  S       \/             |
     +------------------+  I                      |
     |THREAD_INFO       |  Z                      |
     +------------------+  E                      |
     |task_struct *     +-------------------------+
     +------------------+
     |exec_domain       |
     +------------------+
     |flags,cpu         |
     +------------------+
     |addr_limit        |
     +------------------+
     |supervisor_stack[]|
     +------------------+------  HIGH ADDRESS
```

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

一个物理地址可以分为上面三部分:
* **_tag_**: 标记该cacheline 的所属物理地址.(同一cacheline可以存储多个地址, tag
    同set index, tag index 可以唯一标识一个地址)
* **_set_index_**:  标记该地址cache 所属的way, bitsize 由`cache way`的数量决定.
* **_tag_index_** : 表示该地址cache 所属的way中的index, bitsize 由 一路中 cacheline 的数量决定

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
* **addr_limit**: **TODO**

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

## why need thread_info NECESSARY

先说答案，为了省寄存器。

当cpu调度到该进程时，需要有个位置来保存`task_struct`的地址，否则
当上下文从用户态切到内核态时，内核空间找不到该数据结构。

该位置有以下需求:
* 位置固定
* per-cpu

寄存器恰好满足上面两个要求. 那要不要单独分配一个寄存器保存`task_struct` ?
这个因架构来说，在i386架构上，寄存器资源还是不太富裕。所以，大佬们想,
还是放到堆栈里, 将`thread_info`保存在栈底. 在`thread_info`中 引用`task_struct`,
这样通过通用的 `sp` 寄存器 就可以找到`task_struct`

> NOTE
>
> 用户态到内核态 经过 intel 门机制，将硬件将某些上下文保存在了内核栈上。
> (pt_regs)的顶部. 那问题来了，内核栈的地址硬件是如何获取的呢？
>
> 难道程序位于用户态时，还有一个单独的寄存器保存内核栈的地址？
> (关于这个问题这里不去介绍 见 **TODO**)

## x86_64 introduce pda(split kernelstack)

在commit <sup>3</sup> 中引入了`x86_64`架构. `x86_64`为64位架构, `x86_64` 引入了
中断专用栈, irqstack独立于 kernel stack. 所以不能在用 `sp & MASK` 的方式
获取`thread_info` 进而获取 `task_struct`. 所以, 大佬们在`x86_64`搞出了一个
`pda`的机制，全称为`Per processor datastructure`. 数据结构如下:
```cpp
/* Per processor datastructure. %gs points to it while the kernel runs */
/* To use a new field with the *_pda macros it needs to be added to tools/offset.c */
struct x8664_pda {
    struct x8664_pda *me;
    unsigned long kernelstack;  /* TOS for current process */
    unsigned long oldrsp;       /* user rsp for system call */
    unsigned long irqrsp;       /* Old rsp for interrupts. */
    struct task_struct *pcurrent;   /* Current process */
        int irqcount;           /* Irq nesting counter. Starts with -1 */
    int cpunumber;          /* Logical CPU number */
    /* XXX: could be a single list */
    unsigned long *pgd_quick;
    unsigned long *pmd_quick;
    unsigned long *pte_quick;
    unsigned long pgtable_cache_sz;
    char *irqstackptr;
    unsigned int __softirq_pending;
    unsigned int __local_irq_count;
    unsigned int __local_bh_count;
    unsigned int __nmi_count;   /* arch dependent */
    struct task_struct * __ksoftirqd_task; /* waitqueue is too large */
    char irqstack[16 * 1024];   /* Stack used by interrupts */
} ____cacheline_aligned;
```

该数据结构在kernel中是硬编码了一个数组, 也是非常豪横:
```cpp
struct x8664_pda cpu_pda[NR_CPUS] __cacheline_aligned;
```

在初始化时, 将该 对应cpu的数组成员地址存放到该cpu的gs寄存器:

> `x86_64` 架构新增了 `GS`, `FS` 段寄存器，手册中如下描述:
>
> ```
> In 64-bit mode, segmentation is generally (but not completely) disabled,
> creating a flat 64-bit linear-address space. The processor treats the segment
> base of CS, DS, ES, SS as zero, creating a linear address that is equal to the
> effective address. The FS and GS segments are exceptions. These segment
> registers (which hold the segment base) can be used as additional base
> registers in linear address calculations. They facilitate addressing local
> data and certain operating system data structures.
> ```
>
> 大概的意思是，在`64-bit mode`, 段映射一般被disable, 因此一般情况下会构造了
> 一个 `64-bit`flat 地址空间。处理器处理`CS, DS, ES, SS`时，当作zero处理。所以
> 线性地址等于物理地址。
>
> 但是`GS, FS` 两个寄存器比较特殊，其可以作为一个base register，用于寻址
> local data...!

于是大佬们就用`gs`寄存器来索引该cpu所属的 `cpu_pda`  地址:

```sh
pda_init:
=> asm volatile("movl %0,%%gs ; movl %0,%%fs" :: "r" (0));·
=> wrmsrl(MSR_GS_BASE, cpu_pda + cpu);
```

至此，`current` 宏则展开为:
```cpp
#define current get_current()
static inline struct task_struct *get_current(void)
{
    struct task_struct *t = read_pda(pcurrent);
    return t;
}
```

不再依赖 `rsp` 寄存器了!

而`thread_info`呢? 仍然保留在内核栈的顶部。现在他的作用不再是作为间接
访问`task_struct`的载体，而是肩负着, 能够在汇编代码中 **方便, 快速的** 访
问某些数据成员, 所以其仍然保留了通过rsp访问的方式。但是，在`x86_64`架构
中，引入了`interrupt stack`, 简单来说，在内核态收到中断后，会将栈切换
到另一个专门用于处理中断的栈.(关注各种栈，见 **TODO**)

然而在开启抢占的情况下, 有可能在中断栈中访问`thread_info`成员 -- `preempt_count`:

所以get thread_info 函数如下:
```cpp
#ifdef CONFIG_PREEMPT
/* Preemptive kernels need to access this from interrupt context too. */
static inline struct thread_info *current_thread_info(void)
{
    struct thread_info *ti;
    ti = (void *)read_pda(kernelstack) + PDA_STACKOFFSET - THREAD_SIZE;
    return ti;
}
#else
/* On others go for a minimally cheaper way. */
static inline struct thread_info *current_thread_info(void)
{
    struct thread_info *ti;
    __asm__("andq %%rsp,%0; ":"=r" (ti) : "0" (~8191UL));
    return ti;
}
#endif
```

两种方式，显然是后者更加`cheaper`,第一种方式显然要访存一次。而后者则不需要.

在不配置抢占的情况下, `current_thread_info()`的调用仅发生在内核栈, 所以其可以
使用 `rsp + offset` 直接获取到`thread_info`, 而配置抢占的情况下, `current_thread_info()`
可能由`preempt_xxx()` 调用(例如 `preempt_enable`)，而`preempt_enable()` 可能在
中断栈中执行。所以，其需要 通过`pda(kernelstack)` 来间接寻址。

> NOTE
>
> 但是, 个人感觉这里有种一颗老鼠屎坏了一锅粥的感觉，为什么不将`preempt_count`
> 放到per-cpu 变量，或者将整个的thread_info 放到 per-cpu变量呢 ?
>
> 设想下，如果将thread_info 中的成员全部放到per-cpu 变量中，获取到这些成员的地址
> 也只需要访问一次内存。代价是类似的。
{: .prompt-tip}

## vmap kernel stack

而随后，为了加强对于内核栈溢出的检测，将内核栈不再以`alloc_page/kmalloc`的方式分
配, 而是采用`vmalloc()`, 其相当于分配了一个内核的虚拟地址空间，然后按需为这个
区间分配物理页，其在栈顶多保留了一个 页大小的内存空间，当访问到该页时，触发
double fault, 从而检测栈溢出。

在该系列patch中，cleanup `thread_info`, 将 `thread_info` 部分成员放到了其他地方,
(下面会讲具体位置), 并将该数据结构, 存放到了`task_struct` 中. 作者的本意如果
用了`CONFIG_THREAD_INFO_IN_TASK`, 尽量 cleanup `thread_info`,  将`thread_info`
变为一个和架构无关的数据结构. 在该patch中，只有x86 用了`CONFIG_THREAD_INFO_IN_TASK`,
只有如果有其他架构也想用该编译项，也得做类似的改动。

但是, 其他架构搞的并不顺利。下面会说到。

```diff
 struct task_struct {
+#ifdef CONFIG_THREAD_INFO_IN_TASK
+       /*
+        * For reasons of header soup (see current_thread_info()), this
+        * must be the first element of task_struct.
+        */
+       struct thread_info thread_info;
+#endif
```

还记得前面提到过，通过堆栈访问 `thread_info`是非常cheaper的。而作者也认为
访问`thread_info` 是一个非常频繁的行为，于是将`thread_info`放到了
`task_struct`的首个成员, 这样在汇编优化时可能将下面语句:

```diff
+#ifdef CONFIG_THREAD_INFO_IN_TASK
+
+static inline struct thread_info *task_thread_info(struct task_struct *task)
+{
+       return &task->thread_info;
+}
```

直接优化成不计算偏移.(不知道作者是否基于此考虑)

至此, `thread_info` 和`task_struct` 彻底融为一体:

```
+-------------------------+         +------------------+
|task_struct              |   +-----+thread_info       |
+-------------------------+   |     +------------------+
|thead_info::thread_info  +---+     |flags             |
|...                      |         |                  |
|thread::thread_struct    |         +------------------+
+-------------------------+
```

来看下`thread_info`中的成员被移动到了哪里，基于什么考虑:

在该patch合入之前，x86_64 中的 `thread_info`中的成员就剩余几个:

```cpp
struct thread_info {
        struct task_struct	*task;		/* main task structure */
        __u32			flags;		/* low level flags */
        __u32                   status;         /* thread synchronous flags */
        __u32                   cpu;            /* current CPU */
        mm_segment_t            addr_limit;
        unsigned int            sig_on_uaccess_error:1;
        unsigned int            uaccess_err:1;  /* uaccess failed */
};
```

> `preempt_count`在该系列之前就被 PeterZ 移走了:
>
> ```
> commit c2daa3bed53a81171cf8c1a36db798e82b91afe8
> sched, x86: Provide a per-cpu preempt_count implementation
> ```

除了task_struct, 我们来看下这些成员的归宿:

| name                 | move to     |
|----------------------|-------------|
| flags                | NO move     |
| cpu                  | task_struct |
| status               | thread_info |
| addr_limit           | thread_info |
| sig_on_uaccess_error | thread_info |
| uaccess_err          | thread_info |

* 架构相关的结构都移动到`thread_info`中
* cpu: 这个和架构不相关，但是作者想尽量保证`thread_info`干净, 将其移动到`task_struct`
* flags: 这个比较特殊，这个访问很频繁, 作者将其保留在`thread_info`，尽量保证其改动不会
        造成性能衰退(_个人理解_)

> **TODO**
>
> * 关于内核检测内核栈溢出机制，在另一篇文章中讲述
{: .prompt-warning}

## other change for thread_info

后续又有种种原因，向`thread_info`中添加成员, 包括:

* Make struct thread_info arch specific again for x86
  + 什么? x86 首先盯不住了? 将 `thread_info` 不再是通用架构的，变成了特定架构的.
    原因在于在 arm,powerpc 适配`CONFIG_THREAD_INFO_IN_TASK` 其需要在`thread_info`中
    包含`preempt_count`, 但是，目前通用的`thread_info`中没有该成员，因为x86将
    该成员搞成了`per-cpu val`, 所以, x86成特殊的了。。

    为了方便，作者直接将`thread_info`变成了特定架构，通用架构的`thread_info`又
    消失在历史长河。

* 性能问题: status
  + luto 认为, `TS_COMPAT`访问非常热, 并且访问它时大概率也会访问, `thread_info::
      flags`, 基于缓存局部性，提升缓存命中的目的，作者将`status` 放回
      `thread_info`
* 其他:
  + 功能引入: syscall_work **TODO**
  + 编译问题: cpu **TODO**


## TODO
- [ ] 在另外一篇文章中解释进程创建时，上下文情况
- [ ] 在另外一篇文章中介绍Linux 用户态到内核态切换

## 参考
### A. 相关commit
1. v2.5.4-pre2-> v2.5.4-pre3, 将task_struct 和 thread_info 分离
   + [PATCH] thread information block
   + https://www.kernel.org/pub/linux/kernel/v2.5/ChangeLog-2.5.4
   + commit 9b10610a79a288a4dbac366b32970573405c4ed1
   + Author: David Howells <dhowells@redhat.com>
   + Date:   Wed Feb 6 22:56:27 2002 -0800

2. 引入x86_64
   + [PATCH] x86_64 merge: arch + asm
   + commit 0457d99a336be658cea1a5bdb689de5adb3b382d
   + Author: Andi Kleen <ak@muc.de>
   + Date:   Tue Feb 12 20:17:35 2002 -0800

3. 引入per-cpu 管理current
   + commit 9af45651f1f7c89942e016a1a00a7ebddfa727f8
   + Author: Brian Gerst <brgerst@gmail.com>
   + Date:   Mon Jan 19 00:38:58 2009 +0900
4. vmap kernel stack
   + tag: v4.9-rc1
   + commit
     + ba14a194a434ccc8f733e263ad2ce941e35e5787
     + fork: Add generic vmalloced stack support
     + move thread_info
       + `sig_on_uaccess_err` & `uaccess_err`
         + move to `thread_struct`
         + dfa9a942fd7951c8f333cf3f377dde51ebd21685
         + x86/uaccess: Move thread_info::uaccess_err and thread_info::sig_on_uaccess_err to thread_struct
       + `addr_limit`
         + move to `thread_struct`
         + 13d4ea097d18b419ad2a2b696063d44bf59acec0
         + x86/uaccess: Move thread_info::addr_limit to thread_struct
       + `status`
         + move to `thread_struct`
         + b9d989c7218ac922185d82ad46f3e58b27a4bea9
         + x86/asm: Move the thread_info::status field to thread_struct
       + `cpu` & `task`
         + move `cpu` to `task_struct`, move `task` to `NULL :)`
         + 15f4eae70d365bba26854c90b6002aaabb18c8aa
         + x86: Move thread_info into task_struct
   + https://lwn.net/Articles/694348/
   + https://docs.kernel.org/mm/vmalloced-kernel-stacks.html
   + https://lore.kernel.org/all/cover.1468270393.git.luto@kernel.org/
5. move some thread_struct.member to thread_info bak
   + let thread_info be arch
     + sched/core, x86: Make struct thread_info arch specific again
     + commit c8061485a0d7569a865a3cc3c63347b0f42b3765
     + Author: Heiko Carstens <hca@linux.ibm.com>
     + Date:   Wed Oct 19 19:28:11 2016 +0100
     + [mail](https://lore.kernel.org/all/20161024101242.GC15620@leverpostej/)
   + move `status` bak
     + x86/asm: Move 'status' from thread_struct to thread_info
       + 37a8f7c38339b22b69876d6f5a0ab851565284e3
       + commit 37a8f7c38339b22b69876d6f5a0ab851565284e3
       + Author: Andy Lutomirski <luto@kernel.org>
       + Date:   Sun Jan 28 10:38:50 2018 -0800
   + add syscall_work in thread_info
     + b4581a52caff79eab1ea6caaaa4e08526ce2782b
     + [mail](https://lore.kernel.org/all/20201116174206.2639648-1-krisman@collabora.com/)
   + move cpu
     + x86: add CPU field to struct thread_info
       + commit 5443f98fb9e06e765e24f9d894bf028accad8f71
       + Author: Ard Biesheuvel <ardb@kernel.org>
       + Date:   Tue Sep 14 14:10:30 2021 +0200
     + [mail](https://lore.kernel.org/all/20210930125813.197418-1-ardb@kernel.org/#r)

## B. 相关链接
1. [Linux Kernel: Threading vs Process - task_struct vs thread_info](https://stackoverflow.com/questions/21360524/linux-kernel-threading-vs-process-task-struct-vs-thread-info)
