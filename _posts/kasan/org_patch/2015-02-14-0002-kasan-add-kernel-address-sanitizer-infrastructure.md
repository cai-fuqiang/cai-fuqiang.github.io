---
layout:     post
title:      "[PATCH 02/19] kasan: add kernel address sanitizer infrastructure"
author:     "fuqiang"
date:       "Fri, 13 Feb 2015 14:39:17 -0800"
categories: [kasan]
tags:       [kasan_org_patch]
---

```diff
From 0b24becc810dc3be6e3f94103a866f214c282394 Mon Sep 17 00:00:00 2001
From: Andrey Ryabinin <a.ryabinin@samsung.com>
Date: Fri, 13 Feb 2015 14:39:17 -0800
Subject: [PATCH 02/19] kasan: add kernel address sanitizer infrastructure

Kernel Address sanitizer (KASan) is a dynamic memory error detector.  It
provides fast and comprehensive solution for finding use-after-free and
out-of-bounds bugs.

> comprehensive /ˌkɒmprɪˈhensɪv/ 综合的; 所有的;详尽的;全部的
>
> KASan 是一种动态内存错误检测器。它为查找使用后释放和越界错误提供了快速而全
> 面的解决方案。

KASAN uses compile-time instrumentation for checking every memory access,
therefore GCC > v4.9.2 required.  v4.9.2 almost works, but has issues with
putting symbol aliases into the wrong section, which breaks kasan
instrumentation of globals.

> KASAN 使用编译时检测来检查每个内存访问，因此需要 GCC > v4.9.2。v4.9.2 
> 几乎可以工作，但是在将符号别名放入错误的section，这会破坏 kasan  对全
> 局变量的检测。

This patch only adds infrastructure for kernel address sanitizer.  It's
not available for use yet.  The idea and some code was borrowed from [1].

> 此补丁仅添加了kernel address sanitizer 的基础结构。它尚未可用。该想法和一
> 些代码借鉴自[1]

Basic idea:

The main idea of KASAN is to use shadow memory to record whether each byte
of memory is safe to access or not, and use compiler's instrumentation to
check the shadow memory on each memory access.

> KASAN的主要思想是使用影子内存来记录每个内存字节是否可以安全访问，并使用
> 编译器的检测功能在每次内存访问时检查影子内存。

Address sanitizer uses 1/8 of the memory addressable in kernel for shadow
memory and uses direct mapping with a scale and offset to translate a
memory address to its corresponding shadow address.

> 地址清理器使用内核中可寻址内存的 1/8 作为影子内存，并使用带有比例和偏移的
> 直接映射将内存地址转换为其对应的影子地址。

Here is function to translate address to corresponding shadow address:

> 下面的function用来将 address 转换为相应的 shadow address

     unsigned long kasan_mem_to_shadow(unsigned long addr)
     {
                return (addr >> KASAN_SHADOW_SCALE_SHIFT) + KASAN_SHADOW_OFFSET;
     }

where KASAN_SHADOW_SCALE_SHIFT = 3.

So for every 8 bytes there is one corresponding byte of shadow memory.
The following encoding used for each shadow byte: 0 means that all 8 bytes
of the corresponding memory region are valid for access; k (1 <= k <= 7)
means that the first k bytes are valid for access, and other (8 - k) bytes
are not; Any negative value indicates that the entire 8-bytes are
inaccessible.  Different negative values used to distinguish between
different kinds of inaccessible memory (redzones, freed memory) (see
mm/kasan/kasan.h).

> 每8-byte 对应 1-byte shadow memory:
>
> shadow memory encoding:
>  * 0: 8-byte is valid
>  * k ( 1<= k <= 7): 
>    + [0, k] is valid
>    + (k, 7] is invaild
>  * negative: 8-byte is invalid
>  
>  不同的 负数用于区分不同类型的 inaccessible memory: e.g.:
>    + readzones
>    + freed memory

To be able to detect accesses to bad memory we need a special compiler.
Such compiler inserts a specific function calls (__asan_load*(addr),
__asan_store*(addr)) before each memory access of size 1, 2, 4, 8 or 16.

> 为了检测是否访问了 bad memory, 我们需要一个特殊的 compiler, 某些 compiler
> 在进行某些size(1,2,4,8 or 16) 的内存访问之前,插入了一个 特殊的 function 
> calls :
>   + __asan_load*(addr) 
>   + __asan_store*(addr)

These functions check whether memory region is valid to access or not by
checking corresponding shadow memory.  If access is not valid an error
printed.

> 这些functions通过检查相应的 shadow memory, 从而check 当前memory region 
> 是否可以合法访问

Historical background of the address sanitizer from Dmitry Vyukov:

> 关于 address sanitizer 的历史背景来自 Dmitry Vyukov

	"We've developed the set of tools, AddressSanitizer (Asan),
	ThreadSanitizer and MemorySanitizer, for user space. We actively use
	them for testing inside of Google (continuous testing, fuzzing,
	running prod services). To date the tools have found more than 10'000
	scary bugs in Chromium, Google internal codebase and various
	open-source projects (Firefox, OpenSSL, gcc, clang, ffmpeg, MySQL and
	lots of others): [2] [3] [4].
	The tools are part of both gcc and clang compilers.

	> continuous : 连续的, 持续的,反复的, 频繁的
	> prod: 戳; 督促; 捅; 催促; 提醒
	> to date: 迄今
	> scary [ˈskeəri]: 恐怖的;吓人的
	>
	> 我们为用户态开发了一组 tools, Asan, TSan, MSan. 我们实际上使用他们在Google
	> 内部做测试(持续的testing, fuzzing, running prod services). 迄今为止 这些
	> 工具已经在 chromium, Google internal codebase 和各种 open-source project 
	> (Firefox, OpenSSL, gcc, clang, ffmpeg, MySQL和大量其他的[2] [3] [4]发现了
	> 超过10'000  scary bugs.
	>
	> 这些工具是gcc和clang编译器的一部分。

	We have not yet done massive testing under the Kernel AddressSanitizer
	(it's kind of chicken and egg problem, you need it to be upstream to
	start applying it extensively). To date it has found about 50 bugs.
	Bugs that we've found in upstream kernel are listed in [5].
	We've also found ~20 bugs in out internal version of the kernel. Also
	people from Samsung and Oracle have found some.

	> massive /ˈmæsɪv/: 大量的
	>
	> 我们在 KASAN 下做大量的测试( 这是一个先有鸡还是先有蛋的问题, 你需要它
	> 处于上游，才能开始广泛应用它). 至今, 它发现了大约 50 bugs. 我们发现
	> 的upstream kernel 中的Bugs 列举在 [5].  我们在 kernel internal version 中
	> ~20 bugs. Samsung 和 Oracle 的人们也发现了一些.

	[...]

	As others noted, the main feature of AddressSanitizer is its
	performance due to inline compiler instrumentation and simple linear
	shadow memory. User-space Asan has ~2x slowdown on computational
	programs and ~2x memory consumption increase. Taking into account that
	kernel usually consumes only small fraction of CPU and memory when
	running real user-space programs, I would expect that kernel Asan will
	have ~10-30% slowdown and similar memory consumption increase (when we
	finish all tuning).

	> as others noted: 正如其他人指出的那样
	> computational(compute) : 计算
	> tuning /ˈtuːnɪŋ/: 调优
	> consumption /kənˈsʌmpʃn/: 消耗
	> take into account: 考虑到
	> frackt: /ˈfræk/ 小部分
	>
	> 正如其他人指出的那样, AddressSanitizer 的主要特点是其性能，这得受益于
	> 内联编译器检测和简单的线性影子内存。 User-space Asan 在 computational 
	> programs上有 ~2x slowdown 和 ~2x memory comsumption 增长. 考虑到 kernel
	> 当运行实际的 user-space program 时, 会消耗少量的 CPU 和 memory. 我们期望
	> kernel Asan 将会有 ~10-30% slowdown 和 相同的memory consumption increase
	> (当我们完成所有调优)

	I agree that Asan can well replace kmemcheck. We have plans to start
	working on Kernel MemorySanitizer that finds uses of unitialized
	memory. Asan+Msan will provide feature-parity with kmemcheck. As
	others noted, Asan will unlikely replace debug slab and pagealloc that
	can be enabled at runtime. Asan uses compiler instrumentation, so even
	if it is disabled, it still incurs visible overheads.

	> parity /ˈpærəti/: 相等的
	>
	> 我认为 Asan 可以很好的替代 kmemcheck. 我们计划开始研究, 用于查找 
	> unitialized memmory 的 Kernel MemorySanitizer. Asan + Msan 将会提供
	> 和 kmemcheck 相等的功能. 正如其他人所说, Asan 不会替代 可以在runtime 
	> enable的debug slab 和 pagealloc. Asan 使用 compiler instrumentation, 
	> 所以即使将他disable, 他仍然带来不可见的开销.

	Asan technology is easily portable to other architectures. Compiler
	instrumentation is fully portable. Runtime has some arch-dependent
	parts like shadow mapping and atomic operation interception. They are
	relatively easy to port."

	> portable: 便携式的; 手提的;轻便的
	>
	> Asan 技术可轻松移植到其他架构。编译器检测功能完全可移植。runtime
	> 有一些依赖于架构的部分，如阴影映射和原子操作拦截. 他们相对容易移植.

Comparison with other debugging features:
========================================

KMEMCHECK:

  - KASan can do almost everything that kmemcheck can.  KASan uses
    compile-time instrumentation, which makes it significantly faster than
    kmemcheck.  The only advantage of kmemcheck over KASan is detection of
    uninitialized memory reads.

    Some brief performance testing showed that kasan could be
    x500-x600 times faster than kmemcheck:

$ netperf -l 30
		MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to localhost (127.0.0.1) port 0 AF_INET
		Recv   Send    Send
		Socket Socket  Message  Elapsed
		Size   Size    Size     Time     Throughput
		bytes  bytes   bytes    secs.    10^6bits/sec

no debug:	87380  16384  16384    30.00    41624.72

kasan inline:	87380  16384  16384    30.00    12870.54

kasan outline:	87380  16384  16384    30.00    10586.39

kmemcheck: 	87380  16384  16384    30.03      20.23

  - Also kmemcheck couldn't work on several CPUs.  It always sets
    number of CPUs to 1.  KASan doesn't have such limitation.

DEBUG_PAGEALLOC:
	- KASan is slower than DEBUG_PAGEALLOC, but KASan works on sub-page
	  granularity level, so it able to find more bugs.

SLUB_DEBUG (poisoning, redzones):
	- SLUB_DEBUG has lower overhead than KASan.

	- SLUB_DEBUG in most cases are not able to detect bad reads,
	  KASan able to detect both reads and writes.

	- In some cases (e.g. redzone overwritten) SLUB_DEBUG detect
	  bugs only on allocation/freeing of object. KASan catch
	  bugs right before it will happen, so we always know exact
	  place of first bad read/write.

[1] https://code.google.com/p/address-sanitizer/wiki/AddressSanitizerForKernel
[2] https://code.google.com/p/address-sanitizer/wiki/FoundBugs
[3] https://code.google.com/p/thread-sanitizer/wiki/FoundBugs
[4] https://code.google.com/p/memory-sanitizer/wiki/FoundBugs
[5] https://code.google.com/p/address-sanitizer/wiki/AddressSanitizerForKernel#Trophies

Based on work by Andrey Konovalov.

Signed-off-by: Andrey Ryabinin <a.ryabinin@samsung.com>
Acked-by: Michal Marek <mmarek@suse.cz>
Signed-off-by: Andrey Konovalov <adech.fo@gmail.com>
Cc: Dmitry Vyukov <dvyukov@google.com>
Cc: Konstantin Serebryany <kcc@google.com>
Cc: Dmitry Chernenkov <dmitryc@google.com>
Cc: Yuri Gribov <tetra2005@gmail.com>
Cc: Konstantin Khlebnikov <koct9i@gmail.com>
Cc: Sasha Levin <sasha.levin@oracle.com>
Cc: Christoph Lameter <cl@linux.com>
Cc: Joonsoo Kim <iamjoonsoo.kim@lge.com>
Cc: Dave Hansen <dave.hansen@intel.com>
Cc: Andi Kleen <andi@firstfloor.org>
Cc: Ingo Molnar <mingo@elte.hu>
Cc: Thomas Gleixner <tglx@linutronix.de>
Cc: "H. Peter Anvin" <hpa@zytor.com>
Cc: Christoph Lameter <cl@linux.com>
Cc: Pekka Enberg <penberg@kernel.org>
Cc: David Rientjes <rientjes@google.com>
Cc: Stephen Rothwell <sfr@canb.auug.org.au>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 Documentation/kasan.txt               | 170 +++++++++++++++
 Makefile                              |   3 +-
 drivers/firmware/efi/libstub/Makefile |   1 +
 include/linux/kasan.h                 |  46 ++++
 include/linux/sched.h                 |   3 +
 lib/Kconfig.debug                     |   2 +
 lib/Kconfig.kasan                     |  43 ++++
 mm/Makefile                           |   1 +
 mm/kasan/Makefile                     |   8 +
 mm/kasan/kasan.c                      | 302 ++++++++++++++++++++++++++
 mm/kasan/kasan.h                      |  34 +++
 mm/kasan/report.c                     | 209 ++++++++++++++++++
 scripts/Makefile.kasan                |  24 ++
 scripts/Makefile.lib                  |  10 +
 14 files changed, 855 insertions(+), 1 deletion(-)
 create mode 100644 Documentation/kasan.txt
 create mode 100644 include/linux/kasan.h
 create mode 100644 lib/Kconfig.kasan
 create mode 100644 mm/kasan/Makefile
 create mode 100644 mm/kasan/kasan.c
 create mode 100644 mm/kasan/kasan.h
 create mode 100644 mm/kasan/report.c
 create mode 100644 scripts/Makefile.kasan

diff --git a/Documentation/kasan.txt b/Documentation/kasan.txt
new file mode 100644
index 000000000000..f0645a8a992f
--- /dev/null
+++ b/Documentation/kasan.txt
@@ -0,0 +1,170 @@
+Kernel address sanitizer
+================
+
+0. Overview
+===========
+
+Kernel Address sanitizer (KASan) is a dynamic memory error detector. It provides
+a fast and comprehensive solution for finding use-after-free and out-of-bounds
+bugs.
+
+KASan uses compile-time instrumentation for checking every memory access,
+therefore you will need a certain version of GCC >= 4.9.2
+
+Currently KASan is supported only for x86_64 architecture and requires that the
+kernel be built with the SLUB allocator.
+
+1. Usage
+=========
+
+To enable KASAN configure kernel with:
+
+	  CONFIG_KASAN = y
+
+and choose between CONFIG_KASAN_OUTLINE and CONFIG_KASAN_INLINE. Outline/inline
+is compiler instrumentation types. The former produces smaller binary the
+latter is 1.1 - 2 times faster. Inline instrumentation requires GCC 5.0 or
+latter.
+
+Currently KASAN works only with the SLUB memory allocator.
+For better bug detection and nicer report, enable CONFIG_STACKTRACE and put
+at least 'slub_debug=U' in the boot cmdline.
+
+To disable instrumentation for specific files or directories, add a line
+similar to the following to the respective kernel Makefile:
+
+        For a single file (e.g. main.o):
+                KASAN_SANITIZE_main.o := n
+
+        For all files in one directory:
+                KASAN_SANITIZE := n
+
+1.1 Error reports
+==========
+
+A typical out of bounds access report looks like this:
+
+==================================================================
+BUG: AddressSanitizer: out of bounds access in kmalloc_oob_right+0x65/0x75 [test_kasan] at addr ffff8800693bc5d3
+Write of size 1 by task modprobe/1689
+=============================================================================
+BUG kmalloc-128 (Not tainted): kasan error
+-----------------------------------------------------------------------------
+
+Disabling lock debugging due to kernel taint
+INFO: Allocated in kmalloc_oob_right+0x3d/0x75 [test_kasan] age=0 cpu=0 pid=1689
+ __slab_alloc+0x4b4/0x4f0
+ kmem_cache_alloc_trace+0x10b/0x190
+ kmalloc_oob_right+0x3d/0x75 [test_kasan]
+ init_module+0x9/0x47 [test_kasan]
+ do_one_initcall+0x99/0x200
+ load_module+0x2cb3/0x3b20
+ SyS_finit_module+0x76/0x80
+ system_call_fastpath+0x12/0x17
+INFO: Slab 0xffffea0001a4ef00 objects=17 used=7 fp=0xffff8800693bd728 flags=0x100000000004080
+INFO: Object 0xffff8800693bc558 @offset=1368 fp=0xffff8800693bc720
+
+Bytes b4 ffff8800693bc548: 00 00 00 00 00 00 00 00 5a 5a 5a 5a 5a 5a 5a 5a  ........ZZZZZZZZ
+Object ffff8800693bc558: 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b  kkkkkkkkkkkkkkkk
+Object ffff8800693bc568: 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b  kkkkkkkkkkkkkkkk
+Object ffff8800693bc578: 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b  kkkkkkkkkkkkkkkk
+Object ffff8800693bc588: 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b  kkkkkkkkkkkkkkkk
+Object ffff8800693bc598: 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b  kkkkkkkkkkkkkkkk
+Object ffff8800693bc5a8: 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b  kkkkkkkkkkkkkkkk
+Object ffff8800693bc5b8: 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b  kkkkkkkkkkkkkkkk
+Object ffff8800693bc5c8: 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b 6b a5  kkkkkkkkkkkkkkk.
+Redzone ffff8800693bc5d8: cc cc cc cc cc cc cc cc                          ........
+Padding ffff8800693bc718: 5a 5a 5a 5a 5a 5a 5a 5a                          ZZZZZZZZ
+CPU: 0 PID: 1689 Comm: modprobe Tainted: G    B          3.18.0-rc1-mm1+ #98
+Hardware name: QEMU Standard PC (i440FX + PIIX, 1996), BIOS rel-1.7.5-0-ge51488c-20140602_164612-nilsson.home.kraxel.org 04/01/2014
+ ffff8800693bc000 0000000000000000 ffff8800693bc558 ffff88006923bb78
+ ffffffff81cc68ae 00000000000000f3 ffff88006d407600 ffff88006923bba8
+ ffffffff811fd848 ffff88006d407600 ffffea0001a4ef00 ffff8800693bc558
+Call Trace:
+ [<ffffffff81cc68ae>] dump_stack+0x46/0x58
+ [<ffffffff811fd848>] print_trailer+0xf8/0x160
+ [<ffffffffa00026a7>] ? kmem_cache_oob+0xc3/0xc3 [test_kasan]
+ [<ffffffff811ff0f5>] object_err+0x35/0x40
+ [<ffffffffa0002065>] ? kmalloc_oob_right+0x65/0x75 [test_kasan]
+ [<ffffffff8120b9fa>] kasan_report_error+0x38a/0x3f0
+ [<ffffffff8120a79f>] ? kasan_poison_shadow+0x2f/0x40
+ [<ffffffff8120b344>] ? kasan_unpoison_shadow+0x14/0x40
+ [<ffffffff8120a79f>] ? kasan_poison_shadow+0x2f/0x40
+ [<ffffffffa00026a7>] ? kmem_cache_oob+0xc3/0xc3 [test_kasan]
+ [<ffffffff8120a995>] __asan_store1+0x75/0xb0
+ [<ffffffffa0002601>] ? kmem_cache_oob+0x1d/0xc3 [test_kasan]
+ [<ffffffffa0002065>] ? kmalloc_oob_right+0x65/0x75 [test_kasan]
+ [<ffffffffa0002065>] kmalloc_oob_right+0x65/0x75 [test_kasan]
+ [<ffffffffa00026b0>] init_module+0x9/0x47 [test_kasan]
+ [<ffffffff810002d9>] do_one_initcall+0x99/0x200
+ [<ffffffff811e4e5c>] ? __vunmap+0xec/0x160
+ [<ffffffff81114f63>] load_module+0x2cb3/0x3b20
+ [<ffffffff8110fd70>] ? m_show+0x240/0x240
+ [<ffffffff81115f06>] SyS_finit_module+0x76/0x80
+ [<ffffffff81cd3129>] system_call_fastpath+0x12/0x17
+Memory state around the buggy address:
+ ffff8800693bc300: fc fc fc fc fc fc fc fc fc fc fc fc fc fc fc fc
+ ffff8800693bc380: fc fc 00 00 00 00 00 00 00 00 00 00 00 00 00 fc
+ ffff8800693bc400: fc fc fc fc fc fc fc fc fc fc fc fc fc fc fc fc
+ ffff8800693bc480: fc fc fc fc fc fc fc fc fc fc fc fc fc fc fc fc
+ ffff8800693bc500: fc fc fc fc fc fc fc fc fc fc fc 00 00 00 00 00
+>ffff8800693bc580: 00 00 00 00 00 00 00 00 00 00 03 fc fc fc fc fc
+                                                 ^
+ ffff8800693bc600: fc fc fc fc fc fc fc fc fc fc fc fc fc fc fc fc
+ ffff8800693bc680: fc fc fc fc fc fc fc fc fc fc fc fc fc fc fc fc
+ ffff8800693bc700: fc fc fc fc fb fb fb fb fb fb fb fb fb fb fb fb
+ ffff8800693bc780: fb fb fb fb fb fb fb fb fb fb fb fb fb fb fb fb
+ ffff8800693bc800: fb fb fb fb fb fb fb fb fb fb fb fb fb fb fb fb
+==================================================================
+
+First sections describe slub object where bad access happened.
+See 'SLUB Debug output' section in Documentation/vm/slub.txt for details.
+
+In the last section the report shows memory state around the accessed address.
+Reading this part requires some more understanding of how KASAN works.
+
+Each 8 bytes of memory are encoded in one shadow byte as accessible,
+partially accessible, freed or they can be part of a redzone.
+We use the following encoding for each shadow byte: 0 means that all 8 bytes
+of the corresponding memory region are accessible; number N (1 <= N <= 7) means
+that the first N bytes are accessible, and other (8 - N) bytes are not;
+any negative value indicates that the entire 8-byte word is inaccessible.
+We use different negative values to distinguish between different kinds of
+inaccessible memory like redzones or freed memory (see mm/kasan/kasan.h).
+
+In the report above the arrows point to the shadow byte 03, which means that
+the accessed address is partially accessible.
+
+
+2. Implementation details
+========================
+
+From a high level, our approach to memory error detection is similar to that
+of kmemcheck: use shadow memory to record whether each byte of memory is safe
+to access, and use compile-time instrumentation to check shadow memory on each
+memory access.
+
+AddressSanitizer dedicates 1/8 of kernel memory to its shadow memory
+(e.g. 16TB to cover 128TB on x86_64) and uses direct mapping with a scale and
+offset to translate a memory address to its corresponding shadow address.
+
+Here is the function witch translate an address to its corresponding shadow
+address:
+
+static inline void *kasan_mem_to_shadow(const void *addr)
+{
+	return ((unsigned long)addr >> KASAN_SHADOW_SCALE_SHIFT)
+		+ KASAN_SHADOW_OFFSET;
+}
+
+where KASAN_SHADOW_SCALE_SHIFT = 3.
+
+Compile-time instrumentation used for checking memory accesses. Compiler inserts
+function calls (__asan_load*(addr), __asan_store*(addr)) before each memory
+access of size 1, 2, 4, 8 or 16. These functions check whether memory access is
+valid or not by checking corresponding shadow memory.
+
+GCC 5.0 has possibility to perform inline instrumentation. Instead of making
+function calls GCC directly inserts the code to check the shadow memory.
+This option significantly enlarges kernel but it gives x1.1-x2 performance
+boost over outline instrumented kernel.
diff --git a/Makefile b/Makefile
index 5fa2e3035509..33cb15efd257 100644
--- a/Makefile
+++ b/Makefile
@@ -423,7 +423,7 @@ export MAKE AWK GENKSYMS INSTALLKERNEL PERL PYTHON UTS_MACHINE
 export HOSTCXX HOSTCXXFLAGS LDFLAGS_MODULE CHECK CHECKFLAGS
 
 export KBUILD_CPPFLAGS NOSTDINC_FLAGS LINUXINCLUDE OBJCOPYFLAGS LDFLAGS
-export KBUILD_CFLAGS CFLAGS_KERNEL CFLAGS_MODULE CFLAGS_GCOV
+export KBUILD_CFLAGS CFLAGS_KERNEL CFLAGS_MODULE CFLAGS_GCOV CFLAGS_KASAN
 export KBUILD_AFLAGS AFLAGS_KERNEL AFLAGS_MODULE
 export KBUILD_AFLAGS_MODULE KBUILD_CFLAGS_MODULE KBUILD_LDFLAGS_MODULE
 export KBUILD_AFLAGS_KERNEL KBUILD_CFLAGS_KERNEL
@@ -781,6 +781,7 @@ ifeq ($(shell $(CONFIG_SHELL) $(srctree)/scripts/gcc-goto.sh $(CC)), y)
 	KBUILD_CFLAGS += -DCC_HAVE_ASM_GOTO
 endif
 
+include $(srctree)/scripts/Makefile.kasan
 include $(srctree)/scripts/Makefile.extrawarn
 
 # Add user supplied CPPFLAGS, AFLAGS and CFLAGS as the last assignments
diff --git a/drivers/firmware/efi/libstub/Makefile b/drivers/firmware/efi/libstub/Makefile
index 8902f52e0998..280bc0a63365 100644
--- a/drivers/firmware/efi/libstub/Makefile
+++ b/drivers/firmware/efi/libstub/Makefile
@@ -19,6 +19,7 @@ KBUILD_CFLAGS			:= $(cflags-y) \
 				   $(call cc-option,-fno-stack-protector)
 
 GCOV_PROFILE			:= n
+KASAN_SANITIZE			:= n
 
 lib-y				:= efi-stub-helper.o
 lib-$(CONFIG_EFI_ARMSTUB)	+= arm-stub.o fdt.o
diff --git a/include/linux/kasan.h b/include/linux/kasan.h
new file mode 100644
index 000000000000..9102fda60def
--- /dev/null
+++ b/include/linux/kasan.h
@@ -0,0 +1,46 @@
+#ifndef _LINUX_KASAN_H
+#define _LINUX_KASAN_H
+
+#include <linux/types.h>
+
+struct kmem_cache;
+struct page;
+
+#ifdef CONFIG_KASAN
+
+#define KASAN_SHADOW_SCALE_SHIFT 3
+#define KASAN_SHADOW_OFFSET _AC(CONFIG_KASAN_SHADOW_OFFSET, UL)
+
+#include <asm/kasan.h>
+#include <linux/sched.h>
+
+static inline void *kasan_mem_to_shadow(const void *addr)
+{
+	return (void *)((unsigned long)addr >> KASAN_SHADOW_SCALE_SHIFT)
+		+ KASAN_SHADOW_OFFSET;
+}
+
+/* Enable reporting bugs after kasan_disable_current() */
+static inline void kasan_enable_current(void)
+{
+	current->kasan_depth++;
+}
+
+/* Disable reporting bugs for current task */
+static inline void kasan_disable_current(void)
+{
+	current->kasan_depth--;
+}
+
+void kasan_unpoison_shadow(const void *address, size_t size);
+
+#else /* CONFIG_KASAN */
+
+static inline void kasan_unpoison_shadow(const void *address, size_t size) {}
+
+static inline void kasan_enable_current(void) {}
+static inline void kasan_disable_current(void) {}
+
+#endif /* CONFIG_KASAN */
+
+#endif /* LINUX_KASAN_H */
diff --git a/include/linux/sched.h b/include/linux/sched.h
index 048b91b983ed..41c60e5302d7 100644
--- a/include/linux/sched.h
+++ b/include/linux/sched.h
@@ -1664,6 +1664,9 @@ struct task_struct {
 	unsigned long timer_slack_ns;
 	unsigned long default_timer_slack_ns;
 
+#ifdef CONFIG_KASAN
+	unsigned int kasan_depth;
+#endif
 #ifdef CONFIG_FUNCTION_GRAPH_TRACER
 	/* Index of current stored address in ret_stack */
 	int curr_ret_stack;
diff --git a/lib/Kconfig.debug b/lib/Kconfig.debug
index 79a9bb67aeaf..ecb3516f6546 100644
--- a/lib/Kconfig.debug
+++ b/lib/Kconfig.debug
@@ -651,6 +651,8 @@ config DEBUG_STACKOVERFLOW
 
 source "lib/Kconfig.kmemcheck"
 
+source "lib/Kconfig.kasan"
+
 endmenu # "Memory Debugging"
 
 config DEBUG_SHIRQ
diff --git a/lib/Kconfig.kasan b/lib/Kconfig.kasan
new file mode 100644
index 000000000000..e5b3fbe5560f
--- /dev/null
+++ b/lib/Kconfig.kasan
@@ -0,0 +1,43 @@
+config HAVE_ARCH_KASAN
+	bool
+
+if HAVE_ARCH_KASAN
+
+config KASAN
+	bool "KASan: runtime memory debugger"
+	help
+	  Enables kernel address sanitizer - runtime memory debugger,
+	  designed to find out-of-bounds accesses and use-after-free bugs.
+	  This is strictly debugging feature. It consumes about 1/8
+	  of available memory and brings about ~x3 performance slowdown.
+	  For better error detection enable CONFIG_STACKTRACE,
+	  and add slub_debug=U to boot cmdline.
+
+config KASAN_SHADOW_OFFSET
+	hex
+
+choice
+	prompt "Instrumentation type"
+	depends on KASAN
+	default KASAN_OUTLINE
+
+config KASAN_OUTLINE
+	bool "Outline instrumentation"
+	help
+	  Before every memory access compiler insert function call
+	  __asan_load*/__asan_store*. These functions performs check
+	  of shadow memory. This is slower than inline instrumentation,
+	  however it doesn't bloat size of kernel's .text section so
+	  much as inline does.
+
+config KASAN_INLINE
+	bool "Inline instrumentation"
+	help
+	  Compiler directly inserts code checking shadow memory before
+	  memory accesses. This is faster than outline (in some workloads
+	  it gives about x2 boost over outline instrumentation), but
+	  make kernel's .text size much bigger.
+
+endchoice
+
+endif
diff --git a/mm/Makefile b/mm/Makefile
index 3548460ab7b6..930b52df4aca 100644
--- a/mm/Makefile
+++ b/mm/Makefile
@@ -49,6 +49,7 @@ obj-$(CONFIG_PAGE_POISONING) += debug-pagealloc.o
 obj-$(CONFIG_SLAB) += slab.o
 obj-$(CONFIG_SLUB) += slub.o
 obj-$(CONFIG_KMEMCHECK) += kmemcheck.o
+obj-$(CONFIG_KASAN)	+= kasan/
 obj-$(CONFIG_FAILSLAB) += failslab.o
 obj-$(CONFIG_MEMORY_HOTPLUG) += memory_hotplug.o
 obj-$(CONFIG_FS_XIP) += filemap_xip.o
diff --git a/mm/kasan/Makefile b/mm/kasan/Makefile
new file mode 100644
index 000000000000..bd837b8c2f41
--- /dev/null
+++ b/mm/kasan/Makefile
@@ -0,0 +1,8 @@
+KASAN_SANITIZE := n
+
+CFLAGS_REMOVE_kasan.o = -pg
+# Function splitter causes unnecessary splits in __asan_load1/__asan_store1
+# see: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=63533
+CFLAGS_kasan.o := $(call cc-option, -fno-conserve-stack -fno-stack-protector)
+
+obj-y := kasan.o report.o
diff --git a/mm/kasan/kasan.c b/mm/kasan/kasan.c
new file mode 100644
index 000000000000..6dc1aa7cefcc
--- /dev/null
+++ b/mm/kasan/kasan.c
@@ -0,0 +1,302 @@
+/*
+ * This file contains shadow memory manipulation code.
+ *
+ * Copyright (c) 2014 Samsung Electronics Co., Ltd.
+ * Author: Andrey Ryabinin <a.ryabinin@samsung.com>
+ *
+ * Some of code borrowed from https://github.com/xairy/linux by
+ *        Andrey Konovalov <adech.fo@gmail.com>
+ *
+ * This program is free software; you can redistribute it and/or modify
+ * it under the terms of the GNU General Public License version 2 as
+ * published by the Free Software Foundation.
+ *
+ */
+
+#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
+#define DISABLE_BRANCH_PROFILING
+
+#include <linux/export.h>
+#include <linux/init.h>
+#include <linux/kernel.h>
+#include <linux/memblock.h>
+#include <linux/mm.h>
+#include <linux/printk.h>
+#include <linux/sched.h>
+#include <linux/slab.h>
+#include <linux/stacktrace.h>
+#include <linux/string.h>
+#include <linux/types.h>
+#include <linux/kasan.h>
+
+#include "kasan.h"
+
+/*
+ * Poisons the shadow memory for 'size' bytes starting from 'addr'.
+ * Memory addresses should be aligned to KASAN_SHADOW_SCALE_SIZE.
+ */
+static void kasan_poison_shadow(const void *address, size_t size, u8 value)
+{
+	void *shadow_start, *shadow_end;
+
+	shadow_start = kasan_mem_to_shadow(address);
+	shadow_end = kasan_mem_to_shadow(address + size);
+
+	memset(shadow_start, value, shadow_end - shadow_start);
+}
+
+void kasan_unpoison_shadow(const void *address, size_t size)
+{
+	kasan_poison_shadow(address, size, 0);
+
+	if (size & KASAN_SHADOW_MASK) {
+		u8 *shadow = (u8 *)kasan_mem_to_shadow(address + size);
+		*shadow = size & KASAN_SHADOW_MASK;
+	}
+}
+
+
+/*
+ * All functions below always inlined so compiler could
+ * perform better optimizations in each of __asan_loadX/__assn_storeX
+ * depending on memory access size X.
+ */
+
+static __always_inline bool memory_is_poisoned_1(unsigned long addr)
+{
+	s8 shadow_value = *(s8 *)kasan_mem_to_shadow((void *)addr);
+
+	if (unlikely(shadow_value)) {
+		s8 last_accessible_byte = addr & KASAN_SHADOW_MASK;
+		return unlikely(last_accessible_byte >= shadow_value);
+	}
+
+	return false;
+}
+
+static __always_inline bool memory_is_poisoned_2(unsigned long addr)
+{
+	u16 *shadow_addr = (u16 *)kasan_mem_to_shadow((void *)addr);
+
+	if (unlikely(*shadow_addr)) {
+		if (memory_is_poisoned_1(addr + 1))
+			return true;
+
+		if (likely(((addr + 1) & KASAN_SHADOW_MASK) != 0))
+			return false;
+
+		return unlikely(*(u8 *)shadow_addr);
+	}
+
+	return false;
+}
+
+static __always_inline bool memory_is_poisoned_4(unsigned long addr)
+{
+	u16 *shadow_addr = (u16 *)kasan_mem_to_shadow((void *)addr);
+
+	if (unlikely(*shadow_addr)) {
+		if (memory_is_poisoned_1(addr + 3))
+			return true;
+
+		if (likely(((addr + 3) & KASAN_SHADOW_MASK) >= 3))
+			return false;
+
+		return unlikely(*(u8 *)shadow_addr);
+	}
+
+	return false;
+}
+
+static __always_inline bool memory_is_poisoned_8(unsigned long addr)
+{
+	u16 *shadow_addr = (u16 *)kasan_mem_to_shadow((void *)addr);
+
+	if (unlikely(*shadow_addr)) {
+		if (memory_is_poisoned_1(addr + 7))
+			return true;
+
+		if (likely(((addr + 7) & KASAN_SHADOW_MASK) >= 7))
+			return false;
+
+		return unlikely(*(u8 *)shadow_addr);
+	}
+
+	return false;
+}
+
+static __always_inline bool memory_is_poisoned_16(unsigned long addr)
+{
+	u32 *shadow_addr = (u32 *)kasan_mem_to_shadow((void *)addr);
+
+	if (unlikely(*shadow_addr)) {
+		u16 shadow_first_bytes = *(u16 *)shadow_addr;
+		s8 last_byte = (addr + 15) & KASAN_SHADOW_MASK;
+
+		if (unlikely(shadow_first_bytes))
+			return true;
+
+		if (likely(!last_byte))
+			return false;
+
+		return memory_is_poisoned_1(addr + 15);
+	}
+
+	return false;
+}
+
+static __always_inline unsigned long bytes_is_zero(const u8 *start,
+					size_t size)
+{
+	while (size) {
+		if (unlikely(*start))
+			return (unsigned long)start;
+		start++;
+		size--;
+	}
+
+	return 0;
+}
+
+static __always_inline unsigned long memory_is_zero(const void *start,
+						const void *end)
+{
+	unsigned int words;
+	unsigned long ret;
+	unsigned int prefix = (unsigned long)start % 8;
+
+	if (end - start <= 16)
+		return bytes_is_zero(start, end - start);
+
+	if (prefix) {
+		prefix = 8 - prefix;
+		ret = bytes_is_zero(start, prefix);
+		if (unlikely(ret))
+			return ret;
+		start += prefix;
+	}
+
+	words = (end - start) / 8;
+	while (words) {
+		if (unlikely(*(u64 *)start))
+			return bytes_is_zero(start, 8);
+		start += 8;
+		words--;
+	}
+
+	return bytes_is_zero(start, (end - start) % 8);
+}
+
+static __always_inline bool memory_is_poisoned_n(unsigned long addr,
+						size_t size)
+{
+	unsigned long ret;
+
+	ret = memory_is_zero(kasan_mem_to_shadow((void *)addr),
+			kasan_mem_to_shadow((void *)addr + size - 1) + 1);
+
+	if (unlikely(ret)) {
+		unsigned long last_byte = addr + size - 1;
+		s8 *last_shadow = (s8 *)kasan_mem_to_shadow((void *)last_byte);
+
+		if (unlikely(ret != (unsigned long)last_shadow ||
+			((last_byte & KASAN_SHADOW_MASK) >= *last_shadow)))
+			return true;
+	}
+	return false;
+}
+
+static __always_inline bool memory_is_poisoned(unsigned long addr, size_t size)
+{
+	if (__builtin_constant_p(size)) {
+		switch (size) {
+		case 1:
+			return memory_is_poisoned_1(addr);
+		case 2:
+			return memory_is_poisoned_2(addr);
+		case 4:
+			return memory_is_poisoned_4(addr);
+		case 8:
+			return memory_is_poisoned_8(addr);
+		case 16:
+			return memory_is_poisoned_16(addr);
+		default:
+			BUILD_BUG();
+		}
+	}
+
+	return memory_is_poisoned_n(addr, size);
+}
+
+
+static __always_inline void check_memory_region(unsigned long addr,
+						size_t size, bool write)
+{
+	struct kasan_access_info info;
+
+	if (unlikely(size == 0))
+		return;
+
+	if (unlikely((void *)addr <
+		kasan_shadow_to_mem((void *)KASAN_SHADOW_START))) {
+		info.access_addr = (void *)addr;
+		info.access_size = size;
+		info.is_write = write;
+		info.ip = _RET_IP_;
+		kasan_report_user_access(&info);
+		return;
+	}
+
+	if (likely(!memory_is_poisoned(addr, size)))
+		return;
+
+	kasan_report(addr, size, write, _RET_IP_);
+}
+
+#define DEFINE_ASAN_LOAD_STORE(size)				\
+	void __asan_load##size(unsigned long addr)		\
+	{							\
+		check_memory_region(addr, size, false);		\
+	}							\
+	EXPORT_SYMBOL(__asan_load##size);			\
+	__alias(__asan_load##size)				\
+	void __asan_load##size##_noabort(unsigned long);	\
+	EXPORT_SYMBOL(__asan_load##size##_noabort);		\
+	void __asan_store##size(unsigned long addr)		\
+	{							\
+		check_memory_region(addr, size, true);		\
+	}							\
+	EXPORT_SYMBOL(__asan_store##size);			\
+	__alias(__asan_store##size)				\
+	void __asan_store##size##_noabort(unsigned long);	\
+	EXPORT_SYMBOL(__asan_store##size##_noabort)
+
+DEFINE_ASAN_LOAD_STORE(1);
+DEFINE_ASAN_LOAD_STORE(2);
+DEFINE_ASAN_LOAD_STORE(4);
+DEFINE_ASAN_LOAD_STORE(8);
+DEFINE_ASAN_LOAD_STORE(16);
+
+void __asan_loadN(unsigned long addr, size_t size)
+{
+	check_memory_region(addr, size, false);
+}
+EXPORT_SYMBOL(__asan_loadN);
+
+__alias(__asan_loadN)
+void __asan_loadN_noabort(unsigned long, size_t);
+EXPORT_SYMBOL(__asan_loadN_noabort);
+
+void __asan_storeN(unsigned long addr, size_t size)
+{
+	check_memory_region(addr, size, true);
+}
+EXPORT_SYMBOL(__asan_storeN);
+
+__alias(__asan_storeN)
+void __asan_storeN_noabort(unsigned long, size_t);
+EXPORT_SYMBOL(__asan_storeN_noabort);
+
+/* to shut up compiler complaints */
+void __asan_handle_no_return(void) {}
+EXPORT_SYMBOL(__asan_handle_no_return);
diff --git a/mm/kasan/kasan.h b/mm/kasan/kasan.h
new file mode 100644
index 000000000000..648b9c006f3f
--- /dev/null
+++ b/mm/kasan/kasan.h
@@ -0,0 +1,34 @@
+#ifndef __MM_KASAN_KASAN_H
+#define __MM_KASAN_KASAN_H
+
+#include <linux/kasan.h>
+
+#define KASAN_SHADOW_SCALE_SIZE (1UL << KASAN_SHADOW_SCALE_SHIFT)
+#define KASAN_SHADOW_MASK       (KASAN_SHADOW_SCALE_SIZE - 1)
+
+struct kasan_access_info {
+	const void *access_addr;
+	const void *first_bad_addr;
+	size_t access_size;
+	bool is_write;
+	unsigned long ip;
+};
+
+void kasan_report_error(struct kasan_access_info *info);
+void kasan_report_user_access(struct kasan_access_info *info);
+
+static inline const void *kasan_shadow_to_mem(const void *shadow_addr)
+{
+	return (void *)(((unsigned long)shadow_addr - KASAN_SHADOW_OFFSET)
+		<< KASAN_SHADOW_SCALE_SHIFT);
+}
+
+static inline bool kasan_enabled(void)
+{
+	return !current->kasan_depth;
+}
+
+void kasan_report(unsigned long addr, size_t size,
+		bool is_write, unsigned long ip);
+
+#endif
diff --git a/mm/kasan/report.c b/mm/kasan/report.c
new file mode 100644
index 000000000000..5835d69563f5
--- /dev/null
+++ b/mm/kasan/report.c
@@ -0,0 +1,209 @@
+/*
+ * This file contains error reporting code.
+ *
+ * Copyright (c) 2014 Samsung Electronics Co., Ltd.
+ * Author: Andrey Ryabinin <a.ryabinin@samsung.com>
+ *
+ * Some of code borrowed from https://github.com/xairy/linux by
+ *        Andrey Konovalov <adech.fo@gmail.com>
+ *
+ * This program is free software; you can redistribute it and/or modify
+ * it under the terms of the GNU General Public License version 2 as
+ * published by the Free Software Foundation.
+ *
+ */
+
+#include <linux/kernel.h>
+#include <linux/mm.h>
+#include <linux/printk.h>
+#include <linux/sched.h>
+#include <linux/slab.h>
+#include <linux/stacktrace.h>
+#include <linux/string.h>
+#include <linux/types.h>
+#include <linux/kasan.h>
+
+#include "kasan.h"
+
+/* Shadow layout customization. */
+#define SHADOW_BYTES_PER_BLOCK 1
+#define SHADOW_BLOCKS_PER_ROW 16
+#define SHADOW_BYTES_PER_ROW (SHADOW_BLOCKS_PER_ROW * SHADOW_BYTES_PER_BLOCK)
+#define SHADOW_ROWS_AROUND_ADDR 2
+
+static const void *find_first_bad_addr(const void *addr, size_t size)
+{
+	u8 shadow_val = *(u8 *)kasan_mem_to_shadow(addr);
+	const void *first_bad_addr = addr;
+
+	while (!shadow_val && first_bad_addr < addr + size) {
+		first_bad_addr += KASAN_SHADOW_SCALE_SIZE;
+		shadow_val = *(u8 *)kasan_mem_to_shadow(first_bad_addr);
+	}
+	return first_bad_addr;
+}
+
+static void print_error_description(struct kasan_access_info *info)
+{
+	const char *bug_type = "unknown crash";
+	u8 shadow_val;
+
+	info->first_bad_addr = find_first_bad_addr(info->access_addr,
+						info->access_size);
+
+	shadow_val = *(u8 *)kasan_mem_to_shadow(info->first_bad_addr);
+
+	switch (shadow_val) {
+	case 0 ... KASAN_SHADOW_SCALE_SIZE - 1:
+		bug_type = "out of bounds access";
+		break;
+	}
+
+	pr_err("BUG: KASan: %s in %pS at addr %p\n",
+		bug_type, (void *)info->ip,
+		info->access_addr);
+	pr_err("%s of size %zu by task %s/%d\n",
+		info->is_write ? "Write" : "Read",
+		info->access_size, current->comm, task_pid_nr(current));
+}
+
+static void print_address_description(struct kasan_access_info *info)
+{
+	dump_stack();
+}
+
+static bool row_is_guilty(const void *row, const void *guilty)
+{
+	return (row <= guilty) && (guilty < row + SHADOW_BYTES_PER_ROW);
+}
+
+static int shadow_pointer_offset(const void *row, const void *shadow)
+{
+	/* The length of ">ff00ff00ff00ff00: " is
+	 *    3 + (BITS_PER_LONG/8)*2 chars.
+	 */
+	return 3 + (BITS_PER_LONG/8)*2 + (shadow - row)*2 +
+		(shadow - row) / SHADOW_BYTES_PER_BLOCK + 1;
+}
+
+static void print_shadow_for_address(const void *addr)
+{
+	int i;
+	const void *shadow = kasan_mem_to_shadow(addr);
+	const void *shadow_row;
+
+	shadow_row = (void *)round_down((unsigned long)shadow,
+					SHADOW_BYTES_PER_ROW)
+		- SHADOW_ROWS_AROUND_ADDR * SHADOW_BYTES_PER_ROW;
+
+	pr_err("Memory state around the buggy address:\n");
+
+	for (i = -SHADOW_ROWS_AROUND_ADDR; i <= SHADOW_ROWS_AROUND_ADDR; i++) {
+		const void *kaddr = kasan_shadow_to_mem(shadow_row);
+		char buffer[4 + (BITS_PER_LONG/8)*2];
+
+		snprintf(buffer, sizeof(buffer),
+			(i == 0) ? ">%p: " : " %p: ", kaddr);
+
+		kasan_disable_current();
+		print_hex_dump(KERN_ERR, buffer,
+			DUMP_PREFIX_NONE, SHADOW_BYTES_PER_ROW, 1,
+			shadow_row, SHADOW_BYTES_PER_ROW, 0);
+		kasan_enable_current();
+
+		if (row_is_guilty(shadow_row, shadow))
+			pr_err("%*c\n",
+				shadow_pointer_offset(shadow_row, shadow),
+				'^');
+
+		shadow_row += SHADOW_BYTES_PER_ROW;
+	}
+}
+
+static DEFINE_SPINLOCK(report_lock);
+
+void kasan_report_error(struct kasan_access_info *info)
+{
+	unsigned long flags;
+
+	spin_lock_irqsave(&report_lock, flags);
+	pr_err("================================="
+		"=================================\n");
+	print_error_description(info);
+	print_address_description(info);
+	print_shadow_for_address(info->first_bad_addr);
+	pr_err("================================="
+		"=================================\n");
+	spin_unlock_irqrestore(&report_lock, flags);
+}
+
+void kasan_report_user_access(struct kasan_access_info *info)
+{
+	unsigned long flags;
+
+	spin_lock_irqsave(&report_lock, flags);
+	pr_err("================================="
+		"=================================\n");
+	pr_err("BUG: KASan: user-memory-access on address %p\n",
+		info->access_addr);
+	pr_err("%s of size %zu by task %s/%d\n",
+		info->is_write ? "Write" : "Read",
+		info->access_size, current->comm, task_pid_nr(current));
+	dump_stack();
+	pr_err("================================="
+		"=================================\n");
+	spin_unlock_irqrestore(&report_lock, flags);
+}
+
+void kasan_report(unsigned long addr, size_t size,
+		bool is_write, unsigned long ip)
+{
+	struct kasan_access_info info;
+
+	if (likely(!kasan_enabled()))
+		return;
+
+	info.access_addr = (void *)addr;
+	info.access_size = size;
+	info.is_write = is_write;
+	info.ip = ip;
+	kasan_report_error(&info);
+}
+
+
+#define DEFINE_ASAN_REPORT_LOAD(size)                     \
+void __asan_report_load##size##_noabort(unsigned long addr) \
+{                                                         \
+	kasan_report(addr, size, false, _RET_IP_);	  \
+}                                                         \
+EXPORT_SYMBOL(__asan_report_load##size##_noabort)
+
+#define DEFINE_ASAN_REPORT_STORE(size)                     \
+void __asan_report_store##size##_noabort(unsigned long addr) \
+{                                                          \
+	kasan_report(addr, size, true, _RET_IP_);	   \
+}                                                          \
+EXPORT_SYMBOL(__asan_report_store##size##_noabort)
+
+DEFINE_ASAN_REPORT_LOAD(1);
+DEFINE_ASAN_REPORT_LOAD(2);
+DEFINE_ASAN_REPORT_LOAD(4);
+DEFINE_ASAN_REPORT_LOAD(8);
+DEFINE_ASAN_REPORT_LOAD(16);
+DEFINE_ASAN_REPORT_STORE(1);
+DEFINE_ASAN_REPORT_STORE(2);
+DEFINE_ASAN_REPORT_STORE(4);
+DEFINE_ASAN_REPORT_STORE(8);
+DEFINE_ASAN_REPORT_STORE(16);
+
+void __asan_report_load_n_noabort(unsigned long addr, size_t size)
+{
+	kasan_report(addr, size, false, _RET_IP_);
+}
+EXPORT_SYMBOL(__asan_report_load_n_noabort);
+
+void __asan_report_store_n_noabort(unsigned long addr, size_t size)
+{
+	kasan_report(addr, size, true, _RET_IP_);
+}
+EXPORT_SYMBOL(__asan_report_store_n_noabort);
diff --git a/scripts/Makefile.kasan b/scripts/Makefile.kasan
new file mode 100644
index 000000000000..7acd6faa0335
--- /dev/null
+++ b/scripts/Makefile.kasan
@@ -0,0 +1,24 @@
+ifdef CONFIG_KASAN
+ifdef CONFIG_KASAN_INLINE
+	call_threshold := 10000
+else
+	call_threshold := 0
+endif
+
+CFLAGS_KASAN_MINIMAL := -fsanitize=kernel-address
+
+CFLAGS_KASAN := $(call cc-option, -fsanitize=kernel-address \
+		-fasan-shadow-offset=$(CONFIG_KASAN_SHADOW_OFFSET) \
+		--param asan-instrumentation-with-call-threshold=$(call_threshold))
+
+ifeq ($(call cc-option, $(CFLAGS_KASAN_MINIMAL) -Werror),)
+        $(warning Cannot use CONFIG_KASAN: \
+            -fsanitize=kernel-address is not supported by compiler)
+else
+    ifeq ($(CFLAGS_KASAN),)
+        $(warning CONFIG_KASAN: compiler does not support all options.\
+            Trying minimal configuration)
+        CFLAGS_KASAN := $(CFLAGS_KASAN_MINIMAL)
+    endif
+endif
+endif
diff --git a/scripts/Makefile.lib b/scripts/Makefile.lib
index 511755200634..044eb4f89a91 100644
--- a/scripts/Makefile.lib
+++ b/scripts/Makefile.lib
@@ -119,6 +119,16 @@ _c_flags += $(if $(patsubst n%,, \
 		$(CFLAGS_GCOV))
 endif
 
+#
+# Enable address sanitizer flags for kernel except some files or directories
+# we don't want to check (depends on variables KASAN_SANITIZE_obj.o, KASAN_SANITIZE)
+#
+ifeq ($(CONFIG_KASAN),y)
+_c_flags += $(if $(patsubst n%,, \
+		$(KASAN_SANITIZE_$(basetarget).o)$(KASAN_SANITIZE)y), \
+		$(CFLAGS_KASAN))
+endif
+
 # If building the kernel in a separate objtree expand all occurrences
 # of -Idir to -I$(srctree)/dir except for absolute paths (starting with '/').
 
-- 
2.42.0

```
