---
layout:     post
title:      "[PATCH 19/19] kasan: enable instrumentation of global variables"
author:     "fuqiang"
date:       "Fri, 13 Feb 2015 14:40:17 -0800"
categories: [kasan]
tags:       [kasan_org_patch]
---

```diff
From bebf56a1b176c2e1c9efe44e7e6915532cc682cf Mon Sep 17 00:00:00 2001
From: Andrey Ryabinin <a.ryabinin@samsung.com>
Date: Fri, 13 Feb 2015 14:40:17 -0800
Subject: [PATCH 19/19] kasan: enable instrumentation of global variables

This feature let us to detect accesses out of bounds of global variables.
This will work as for globals in kernel image, so for globals in modules.
Currently this won't work for symbols in user-specified sections (e.g.
__init, __read_mostly, ...)

The idea of this is simple.  Compiler increases each global variable by
redzone size and add constructors invoking __asan_register_globals()
function.  Information about global variable (address, size, size with
redzone ...) passed to __asan_register_globals() so we could poison
variable's redzone.

This patch also forces module_alloc() to return 8*PAGE_SIZE aligned
address making shadow memory handling (
kasan_module_alloc()/kasan_module_free() ) more simple.  Such alignment
guarantees that each shadow page backing modules address space correspond
to only one module_alloc() allocation.

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
 Documentation/kasan.txt       |  2 +-
 arch/x86/kernel/module.c      | 12 +++++++-
 arch/x86/mm/kasan_init_64.c   |  2 +-
 include/linux/compiler-gcc4.h |  4 +++
 include/linux/compiler-gcc5.h |  2 ++
 include/linux/kasan.h         | 10 +++++++
 kernel/module.c               |  2 ++
 lib/Kconfig.kasan             |  1 +
 mm/kasan/kasan.c              | 52 +++++++++++++++++++++++++++++++++++
 mm/kasan/kasan.h              | 25 +++++++++++++++++
 mm/kasan/report.c             | 22 +++++++++++++++
 scripts/Makefile.kasan        |  2 +-
 12 files changed, 132 insertions(+), 4 deletions(-)

diff --git a/Documentation/kasan.txt b/Documentation/kasan.txt
index f0645a8a992f..092fc10961fe 100644
--- a/Documentation/kasan.txt
+++ b/Documentation/kasan.txt
@@ -9,7 +9,7 @@ a fast and comprehensive solution for finding use-after-free and out-of-bounds
 bugs.
 
 KASan uses compile-time instrumentation for checking every memory access,
-therefore you will need a certain version of GCC >= 4.9.2
+therefore you will need a certain version of GCC > 4.9.2
 
 Currently KASan is supported only for x86_64 architecture and requires that the
 kernel be built with the SLUB allocator.
diff --git a/arch/x86/kernel/module.c b/arch/x86/kernel/module.c
index e830e61aae05..d1ac80b72c72 100644
--- a/arch/x86/kernel/module.c
+++ b/arch/x86/kernel/module.c
@@ -24,6 +24,7 @@
 #include <linux/fs.h>
 #include <linux/string.h>
 #include <linux/kernel.h>
+#include <linux/kasan.h>
 #include <linux/bug.h>
 #include <linux/mm.h>
 #include <linux/gfp.h>
@@ -83,13 +84,22 @@ static unsigned long int get_module_load_offset(void)
 
 void *module_alloc(unsigned long size)
 {
+	void *p;
+
 	if (PAGE_ALIGN(size) > MODULES_LEN)
 		return NULL;
-	return __vmalloc_node_range(size, 1,
+
+	p = __vmalloc_node_range(size, MODULE_ALIGN,
 				    MODULES_VADDR + get_module_load_offset(),
 				    MODULES_END, GFP_KERNEL | __GFP_HIGHMEM,
 				    PAGE_KERNEL_EXEC, 0, NUMA_NO_NODE,
 				    __builtin_return_address(0));
+	if (p && (kasan_module_alloc(p, size) < 0)) {
+		vfree(p);
+		return NULL;
+	}
+
+	return p;
 }
 
 #ifdef CONFIG_X86_32
diff --git a/arch/x86/mm/kasan_init_64.c b/arch/x86/mm/kasan_init_64.c
index 53508708b7aa..4860906c6b9f 100644
--- a/arch/x86/mm/kasan_init_64.c
+++ b/arch/x86/mm/kasan_init_64.c
@@ -196,7 +196,7 @@ void __init kasan_init(void)
 			(unsigned long)kasan_mem_to_shadow(_end),
 			NUMA_NO_NODE);
 
-	populate_zero_shadow(kasan_mem_to_shadow((void *)MODULES_VADDR),
+	populate_zero_shadow(kasan_mem_to_shadow((void *)MODULES_END),
 			(void *)KASAN_SHADOW_END);
 
 	memset(kasan_zero_page, 0, PAGE_SIZE);
diff --git a/include/linux/compiler-gcc4.h b/include/linux/compiler-gcc4.h
index d1a558239b1a..769e19864632 100644
--- a/include/linux/compiler-gcc4.h
+++ b/include/linux/compiler-gcc4.h
@@ -85,3 +85,7 @@
 #define __HAVE_BUILTIN_BSWAP16__
 #endif
 #endif /* CONFIG_ARCH_USE_BUILTIN_BSWAP */
+
+#if GCC_VERSION >= 40902
+#define KASAN_ABI_VERSION 3
+#endif
diff --git a/include/linux/compiler-gcc5.h b/include/linux/compiler-gcc5.h
index c8c565952548..efee493714eb 100644
--- a/include/linux/compiler-gcc5.h
+++ b/include/linux/compiler-gcc5.h
@@ -63,3 +63,5 @@
 #define __HAVE_BUILTIN_BSWAP64__
 #define __HAVE_BUILTIN_BSWAP16__
 #endif /* CONFIG_ARCH_USE_BUILTIN_BSWAP */
+
+#define KASAN_ABI_VERSION 4
diff --git a/include/linux/kasan.h b/include/linux/kasan.h
index d5310eef3e38..72ba725ddf9c 100644
--- a/include/linux/kasan.h
+++ b/include/linux/kasan.h
@@ -49,8 +49,15 @@ void kasan_krealloc(const void *object, size_t new_size);
 void kasan_slab_alloc(struct kmem_cache *s, void *object);
 void kasan_slab_free(struct kmem_cache *s, void *object);
 
+#define MODULE_ALIGN (PAGE_SIZE << KASAN_SHADOW_SCALE_SHIFT)
+
+int kasan_module_alloc(void *addr, size_t size);
+void kasan_module_free(void *addr);
+
 #else /* CONFIG_KASAN */
 
+#define MODULE_ALIGN 1
+
 static inline void kasan_unpoison_shadow(const void *address, size_t size) {}
 
 static inline void kasan_enable_current(void) {}
@@ -74,6 +81,9 @@ static inline void kasan_krealloc(const void *object, size_t new_size) {}
 static inline void kasan_slab_alloc(struct kmem_cache *s, void *object) {}
 static inline void kasan_slab_free(struct kmem_cache *s, void *object) {}
 
+static inline int kasan_module_alloc(void *addr, size_t size) { return 0; }
+static inline void kasan_module_free(void *addr) {}
+
 #endif /* CONFIG_KASAN */
 
 #endif /* LINUX_KASAN_H */
diff --git a/kernel/module.c b/kernel/module.c
index 82dc1f899e6d..8426ad48362c 100644
--- a/kernel/module.c
+++ b/kernel/module.c
@@ -56,6 +56,7 @@
 #include <linux/async.h>
 #include <linux/percpu.h>
 #include <linux/kmemleak.h>
+#include <linux/kasan.h>
 #include <linux/jump_label.h>
 #include <linux/pfn.h>
 #include <linux/bsearch.h>
@@ -1813,6 +1814,7 @@ static void unset_module_init_ro_nx(struct module *mod) { }
 void __weak module_memfree(void *module_region)
 {
 	vfree(module_region);
+	kasan_module_free(module_region);
 }
 
 void __weak module_arch_cleanup(struct module *mod)
diff --git a/lib/Kconfig.kasan b/lib/Kconfig.kasan
index 4d47d874335c..4fecaedc80a2 100644
--- a/lib/Kconfig.kasan
+++ b/lib/Kconfig.kasan
@@ -6,6 +6,7 @@ if HAVE_ARCH_KASAN
 config KASAN
 	bool "KASan: runtime memory debugger"
 	depends on SLUB_DEBUG
+	select CONSTRUCTORS
 	help
 	  Enables kernel address sanitizer - runtime memory debugger,
 	  designed to find out-of-bounds accesses and use-after-free bugs.
diff --git a/mm/kasan/kasan.c b/mm/kasan/kasan.c
index 799c52b9826c..78fee632a7ee 100644
--- a/mm/kasan/kasan.c
+++ b/mm/kasan/kasan.c
@@ -22,6 +22,7 @@
 #include <linux/memblock.h>
 #include <linux/memory.h>
 #include <linux/mm.h>
+#include <linux/module.h>
 #include <linux/printk.h>
 #include <linux/sched.h>
 #include <linux/slab.h>
@@ -395,6 +396,57 @@ void kasan_kfree_large(const void *ptr)
 			KASAN_FREE_PAGE);
 }
 
+int kasan_module_alloc(void *addr, size_t size)
+{
+	void *ret;
+	size_t shadow_size;
+	unsigned long shadow_start;
+
+	shadow_start = (unsigned long)kasan_mem_to_shadow(addr);
+	shadow_size = round_up(size >> KASAN_SHADOW_SCALE_SHIFT,
+			PAGE_SIZE);
+
+	if (WARN_ON(!PAGE_ALIGNED(shadow_start)))
+		return -EINVAL;
+
+	ret = __vmalloc_node_range(shadow_size, 1, shadow_start,
+			shadow_start + shadow_size,
+			GFP_KERNEL | __GFP_HIGHMEM | __GFP_ZERO,
+			PAGE_KERNEL, VM_NO_GUARD, NUMA_NO_NODE,
+			__builtin_return_address(0));
+	return ret ? 0 : -ENOMEM;
+}
+
+void kasan_module_free(void *addr)
+{
+	vfree(kasan_mem_to_shadow(addr));
+}
+
+static void register_global(struct kasan_global *global)
+{
+	size_t aligned_size = round_up(global->size, KASAN_SHADOW_SCALE_SIZE);
+
+	kasan_unpoison_shadow(global->beg, global->size);
+
+	kasan_poison_shadow(global->beg + aligned_size,
+		global->size_with_redzone - aligned_size,
+		KASAN_GLOBAL_REDZONE);
+}
+
+void __asan_register_globals(struct kasan_global *globals, size_t size)
+{
+	int i;
+
+	for (i = 0; i < size; i++)
+		register_global(&globals[i]);
+}
+EXPORT_SYMBOL(__asan_register_globals);
+
+void __asan_unregister_globals(struct kasan_global *globals, size_t size)
+{
+}
+EXPORT_SYMBOL(__asan_unregister_globals);
+
 #define DEFINE_ASAN_LOAD_STORE(size)				\
 	void __asan_load##size(unsigned long addr)		\
 	{							\
diff --git a/mm/kasan/kasan.h b/mm/kasan/kasan.h
index 1fcc1d81a9cf..4986b0acab21 100644
--- a/mm/kasan/kasan.h
+++ b/mm/kasan/kasan.h
@@ -11,6 +11,7 @@
 #define KASAN_PAGE_REDZONE      0xFE  /* redzone for kmalloc_large allocations */
 #define KASAN_KMALLOC_REDZONE   0xFC  /* redzone inside slub object */
 #define KASAN_KMALLOC_FREE      0xFB  /* object was freed (kmem_cache_free/kfree) */
+#define KASAN_GLOBAL_REDZONE    0xFA  /* redzone for global variable */
 
 /*
  * Stack redzone shadow values
@@ -21,6 +22,10 @@
 #define KASAN_STACK_RIGHT       0xF3
 #define KASAN_STACK_PARTIAL     0xF4
 
+/* Don't break randconfig/all*config builds */
+#ifndef KASAN_ABI_VERSION
+#define KASAN_ABI_VERSION 1
+#endif
 
 struct kasan_access_info {
 	const void *access_addr;
@@ -30,6 +35,26 @@ struct kasan_access_info {
 	unsigned long ip;
 };
 
+/* The layout of struct dictated by compiler */
+struct kasan_source_location {
+	const char *filename;
+	int line_no;
+	int column_no;
+};
+
+/* The layout of struct dictated by compiler */
+struct kasan_global {
+	const void *beg;		/* Address of the beginning of the global variable. */
+	size_t size;			/* Size of the global variable. */
+	size_t size_with_redzone;	/* Size of the variable + size of the red zone. 32 bytes aligned */
+	const void *name;
+	const void *module_name;	/* Name of the module where the global variable is declared. */
+	unsigned long has_dynamic_init;	/* This needed for C++ */
+#if KASAN_ABI_VERSION >= 4
+	struct kasan_source_location *location;
+#endif
+};
+
 void kasan_report_error(struct kasan_access_info *info);
 void kasan_report_user_access(struct kasan_access_info *info);
 
diff --git a/mm/kasan/report.c b/mm/kasan/report.c
index 866732ef3db3..680ceedf810a 100644
--- a/mm/kasan/report.c
+++ b/mm/kasan/report.c
@@ -23,6 +23,8 @@
 #include <linux/types.h>
 #include <linux/kasan.h>
 
+#include <asm/sections.h>
+
 #include "kasan.h"
 #include "../slab.h"
 
@@ -61,6 +63,7 @@ static void print_error_description(struct kasan_access_info *info)
 		break;
 	case KASAN_PAGE_REDZONE:
 	case KASAN_KMALLOC_REDZONE:
+	case KASAN_GLOBAL_REDZONE:
 	case 0 ... KASAN_SHADOW_SCALE_SIZE - 1:
 		bug_type = "out of bounds access";
 		break;
@@ -80,6 +83,20 @@ static void print_error_description(struct kasan_access_info *info)
 		info->access_size, current->comm, task_pid_nr(current));
 }
 
+static inline bool kernel_or_module_addr(const void *addr)
+{
+	return (addr >= (void *)_stext && addr < (void *)_end)
+		|| (addr >= (void *)MODULES_VADDR
+			&& addr < (void *)MODULES_END);
+}
+
+static inline bool init_task_stack_addr(const void *addr)
+{
+	return addr >= (void *)&init_thread_union.stack &&
+		(addr <= (void *)&init_thread_union.stack +
+			sizeof(init_thread_union.stack));
+}
+
 static void print_address_description(struct kasan_access_info *info)
 {
 	const void *addr = info->access_addr;
@@ -107,6 +124,11 @@ static void print_address_description(struct kasan_access_info *info)
 		dump_page(page, "kasan: bad access detected");
 	}
 
+	if (kernel_or_module_addr(addr)) {
+		if (!init_task_stack_addr(addr))
+			pr_err("Address belongs to variable %pS\n", addr);
+	}
+
 	dump_stack();
 }
 
diff --git a/scripts/Makefile.kasan b/scripts/Makefile.kasan
index 2163b8cc446e..631619b2b118 100644
--- a/scripts/Makefile.kasan
+++ b/scripts/Makefile.kasan
@@ -9,7 +9,7 @@ CFLAGS_KASAN_MINIMAL := -fsanitize=kernel-address
 
 CFLAGS_KASAN := $(call cc-option, -fsanitize=kernel-address \
 		-fasan-shadow-offset=$(CONFIG_KASAN_SHADOW_OFFSET) \
-		--param asan-stack=1 \
+		--param asan-stack=1 --param asan-globals=1 \
 		--param asan-instrumentation-with-call-threshold=$(call_threshold))
 
 ifeq ($(call cc-option, $(CFLAGS_KASAN_MINIMAL) -Werror),)
-- 
2.42.0

```
