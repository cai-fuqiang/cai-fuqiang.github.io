---
layout:     post
title:      "[PATCH 14/19] kasan: enable stack instrumentation"
author:     "fuqiang"
date:       "Fri, 13 Feb 2015 14:39:59 -0800"
categories: [kasan]
tags:       [kasan_org_patch]
---

```diff
From c420f167db8c799d69fe43a801c58a7f02e9d57c Mon Sep 17 00:00:00 2001
From: Andrey Ryabinin <a.ryabinin@samsung.com>
Date: Fri, 13 Feb 2015 14:39:59 -0800
Subject: [PATCH 14/19] kasan: enable stack instrumentation

Stack instrumentation allows to detect out of bounds memory accesses for
variables allocated on stack.  Compiler adds redzones around every
variable on stack and poisons redzones in function's prologue.

Such approach significantly increases stack usage, so all in-kernel stacks
size were doubled.

Signed-off-by: Andrey Ryabinin <a.ryabinin@samsung.com>
Cc: Dmitry Vyukov <dvyukov@google.com>
Cc: Konstantin Serebryany <kcc@google.com>
Cc: Dmitry Chernenkov <dmitryc@google.com>
Signed-off-by: Andrey Konovalov <adech.fo@gmail.com>
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
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 arch/x86/include/asm/page_64_types.h | 12 +++++++++---
 arch/x86/kernel/Makefile             |  2 ++
 arch/x86/mm/kasan_init_64.c          | 11 +++++++++--
 include/linux/init_task.h            |  8 ++++++++
 mm/kasan/kasan.h                     |  9 +++++++++
 mm/kasan/report.c                    |  6 ++++++
 scripts/Makefile.kasan               |  1 +
 7 files changed, 44 insertions(+), 5 deletions(-)

diff --git a/arch/x86/include/asm/page_64_types.h b/arch/x86/include/asm/page_64_types.h
index 75450b2c7be4..4edd53b79a81 100644
--- a/arch/x86/include/asm/page_64_types.h
+++ b/arch/x86/include/asm/page_64_types.h
@@ -1,17 +1,23 @@
 #ifndef _ASM_X86_PAGE_64_DEFS_H
 #define _ASM_X86_PAGE_64_DEFS_H
 
-#define THREAD_SIZE_ORDER	2
+#ifdef CONFIG_KASAN
+#define KASAN_STACK_ORDER 1
+#else
+#define KASAN_STACK_ORDER 0
+#endif
+
+#define THREAD_SIZE_ORDER	(2 + KASAN_STACK_ORDER)
 #define THREAD_SIZE  (PAGE_SIZE << THREAD_SIZE_ORDER)
 #define CURRENT_MASK (~(THREAD_SIZE - 1))
 
-#define EXCEPTION_STACK_ORDER 0
+#define EXCEPTION_STACK_ORDER (0 + KASAN_STACK_ORDER)
 #define EXCEPTION_STKSZ (PAGE_SIZE << EXCEPTION_STACK_ORDER)
 
 #define DEBUG_STACK_ORDER (EXCEPTION_STACK_ORDER + 1)
 #define DEBUG_STKSZ (PAGE_SIZE << DEBUG_STACK_ORDER)
 
-#define IRQ_STACK_ORDER 2
+#define IRQ_STACK_ORDER (2 + KASAN_STACK_ORDER)
 #define IRQ_STACK_SIZE (PAGE_SIZE << IRQ_STACK_ORDER)
 
 #define DOUBLEFAULT_STACK 1
diff --git a/arch/x86/kernel/Makefile b/arch/x86/kernel/Makefile
index b13b70634124..cdb1b70ddad0 100644
--- a/arch/x86/kernel/Makefile
+++ b/arch/x86/kernel/Makefile
@@ -17,6 +17,8 @@ CFLAGS_REMOVE_early_printk.o = -pg
 endif
 
 KASAN_SANITIZE_head$(BITS).o := n
+KASAN_SANITIZE_dumpstack.o := n
+KASAN_SANITIZE_dumpstack_$(BITS).o := n
 
 CFLAGS_irq.o := -I$(src)/../include/asm/trace
 
diff --git a/arch/x86/mm/kasan_init_64.c b/arch/x86/mm/kasan_init_64.c
index 3e4d9a1a39fa..53508708b7aa 100644
--- a/arch/x86/mm/kasan_init_64.c
+++ b/arch/x86/mm/kasan_init_64.c
@@ -189,11 +189,18 @@ void __init kasan_init(void)
 		if (map_range(&pfn_mapped[i]))
 			panic("kasan: unable to allocate shadow!");
 	}
-
 	populate_zero_shadow(kasan_mem_to_shadow((void *)PAGE_OFFSET + MAXMEM),
-				(void *)KASAN_SHADOW_END);
+			kasan_mem_to_shadow((void *)__START_KERNEL_map));
+
+	vmemmap_populate((unsigned long)kasan_mem_to_shadow(_stext),
+			(unsigned long)kasan_mem_to_shadow(_end),
+			NUMA_NO_NODE);
+
+	populate_zero_shadow(kasan_mem_to_shadow((void *)MODULES_VADDR),
+			(void *)KASAN_SHADOW_END);
 
 	memset(kasan_zero_page, 0, PAGE_SIZE);
 
 	load_cr3(init_level4_pgt);
+	init_task.kasan_depth = 0;
 }
diff --git a/include/linux/init_task.h b/include/linux/init_task.h
index d3d43ecf148c..696d22312b31 100644
--- a/include/linux/init_task.h
+++ b/include/linux/init_task.h
@@ -175,6 +175,13 @@ extern struct task_group root_task_group;
 # define INIT_NUMA_BALANCING(tsk)
 #endif
 
+#ifdef CONFIG_KASAN
+# define INIT_KASAN(tsk)						\
+	.kasan_depth = 1,
+#else
+# define INIT_KASAN(tsk)
+#endif
+
 /*
  *  INIT_TASK is used to set up the first task table, touch at
  * your own risk!. Base=0, limit=0x1fffff (=2MB)
@@ -250,6 +257,7 @@ extern struct task_group root_task_group;
 	INIT_RT_MUTEXES(tsk)						\
 	INIT_VTIME(tsk)							\
 	INIT_NUMA_BALANCING(tsk)					\
+	INIT_KASAN(tsk)							\
 }
 
 
diff --git a/mm/kasan/kasan.h b/mm/kasan/kasan.h
index 5b052ab40cf9..1fcc1d81a9cf 100644
--- a/mm/kasan/kasan.h
+++ b/mm/kasan/kasan.h
@@ -12,6 +12,15 @@
 #define KASAN_KMALLOC_REDZONE   0xFC  /* redzone inside slub object */
 #define KASAN_KMALLOC_FREE      0xFB  /* object was freed (kmem_cache_free/kfree) */
 
+/*
+ * Stack redzone shadow values
+ * (Those are compiler's ABI, don't change them)
+ */
+#define KASAN_STACK_LEFT        0xF1
+#define KASAN_STACK_MID         0xF2
+#define KASAN_STACK_RIGHT       0xF3
+#define KASAN_STACK_PARTIAL     0xF4
+
 
 struct kasan_access_info {
 	const void *access_addr;
diff --git a/mm/kasan/report.c b/mm/kasan/report.c
index 2760edb4d0a8..866732ef3db3 100644
--- a/mm/kasan/report.c
+++ b/mm/kasan/report.c
@@ -64,6 +64,12 @@ static void print_error_description(struct kasan_access_info *info)
 	case 0 ... KASAN_SHADOW_SCALE_SIZE - 1:
 		bug_type = "out of bounds access";
 		break;
+	case KASAN_STACK_LEFT:
+	case KASAN_STACK_MID:
+	case KASAN_STACK_RIGHT:
+	case KASAN_STACK_PARTIAL:
+		bug_type = "out of bounds on stack";
+		break;
 	}
 
 	pr_err("BUG: KASan: %s in %pS at addr %p\n",
diff --git a/scripts/Makefile.kasan b/scripts/Makefile.kasan
index 7acd6faa0335..2163b8cc446e 100644
--- a/scripts/Makefile.kasan
+++ b/scripts/Makefile.kasan
@@ -9,6 +9,7 @@ CFLAGS_KASAN_MINIMAL := -fsanitize=kernel-address
 
 CFLAGS_KASAN := $(call cc-option, -fsanitize=kernel-address \
 		-fasan-shadow-offset=$(CONFIG_KASAN_SHADOW_OFFSET) \
+		--param asan-stack=1 \
 		--param asan-instrumentation-with-call-threshold=$(call_threshold))
 
 ifeq ($(call cc-option, $(CFLAGS_KASAN_MINIMAL) -Werror),)
-- 
2.42.0

```
