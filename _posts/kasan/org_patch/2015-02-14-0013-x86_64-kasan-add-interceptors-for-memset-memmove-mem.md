---
layout:     post
title:      "[PATCH 13/19] x86_64: kasan: add interceptors for memset/memmove/memcpy functions"
author:     "fuqiang"
date:       "Fri, 13 Feb 2015 14:39:56 -0800"
categories: [kasan]
tags:       [kasan_org_patch]
---

```diff
From 393f203f5fd54421fddb1e2a263f64d3876eeadb Mon Sep 17 00:00:00 2001
From: Andrey Ryabinin <a.ryabinin@samsung.com>
Date: Fri, 13 Feb 2015 14:39:56 -0800
Subject: [PATCH 13/19] x86_64: kasan: add interceptors for
 memset/memmove/memcpy functions

Recently instrumentation of builtin functions calls was removed from GCC
5.0.  To check the memory accessed by such functions, userspace asan
always uses interceptors for them.

So now we should do this as well.  This patch declares
memset/memmove/memcpy as weak symbols.  In mm/kasan/kasan.c we have our
own implementation of those functions which checks memory before accessing
it.

Default memset/memmove/memcpy now now always have aliases with '__'
prefix.  For files that built without kasan instrumentation (e.g.
mm/slub.c) original mem* replaced (via #define) with prefixed variants,
cause we don't want to check memory accesses there.

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
 arch/x86/boot/compressed/eboot.c       |  3 +--
 arch/x86/boot/compressed/misc.h        |  1 +
 arch/x86/include/asm/string_64.h       | 18 +++++++++++++++-
 arch/x86/kernel/x8664_ksyms_64.c       | 10 +++++++--
 arch/x86/lib/memcpy_64.S               |  6 ++++--
 arch/x86/lib/memmove_64.S              |  4 ++++
 arch/x86/lib/memset_64.S               | 10 +++++----
 drivers/firmware/efi/libstub/efistub.h |  4 ++++
 mm/kasan/kasan.c                       | 29 ++++++++++++++++++++++++++
 9 files changed, 74 insertions(+), 11 deletions(-)

diff --git a/arch/x86/boot/compressed/eboot.c b/arch/x86/boot/compressed/eboot.c
index 92b9a5f2aed6..ef17683484e9 100644
--- a/arch/x86/boot/compressed/eboot.c
+++ b/arch/x86/boot/compressed/eboot.c
@@ -13,8 +13,7 @@
 #include <asm/setup.h>
 #include <asm/desc.h>
 
-#undef memcpy			/* Use memcpy from misc.c */
-
+#include "../string.h"
 #include "eboot.h"
 
 static efi_system_table_t *sys_table;
diff --git a/arch/x86/boot/compressed/misc.h b/arch/x86/boot/compressed/misc.h
index 24e3e569a13c..04477d68403f 100644
--- a/arch/x86/boot/compressed/misc.h
+++ b/arch/x86/boot/compressed/misc.h
@@ -7,6 +7,7 @@
  * we just keep it from happening
  */
 #undef CONFIG_PARAVIRT
+#undef CONFIG_KASAN
 #ifdef CONFIG_X86_32
 #define _ASM_X86_DESC_H 1
 #endif
diff --git a/arch/x86/include/asm/string_64.h b/arch/x86/include/asm/string_64.h
index 19e2c468fc2c..e4661196994e 100644
--- a/arch/x86/include/asm/string_64.h
+++ b/arch/x86/include/asm/string_64.h
@@ -27,11 +27,12 @@ static __always_inline void *__inline_memcpy(void *to, const void *from, size_t
    function. */
 
 #define __HAVE_ARCH_MEMCPY 1
+extern void *__memcpy(void *to, const void *from, size_t len);
+
 #ifndef CONFIG_KMEMCHECK
 #if (__GNUC__ == 4 && __GNUC_MINOR__ >= 3) || __GNUC__ > 4
 extern void *memcpy(void *to, const void *from, size_t len);
 #else
-extern void *__memcpy(void *to, const void *from, size_t len);
 #define memcpy(dst, src, len)					\
 ({								\
 	size_t __len = (len);					\
@@ -53,9 +54,11 @@ extern void *__memcpy(void *to, const void *from, size_t len);
 
 #define __HAVE_ARCH_MEMSET
 void *memset(void *s, int c, size_t n);
+void *__memset(void *s, int c, size_t n);
 
 #define __HAVE_ARCH_MEMMOVE
 void *memmove(void *dest, const void *src, size_t count);
+void *__memmove(void *dest, const void *src, size_t count);
 
 int memcmp(const void *cs, const void *ct, size_t count);
 size_t strlen(const char *s);
@@ -63,6 +66,19 @@ char *strcpy(char *dest, const char *src);
 char *strcat(char *dest, const char *src);
 int strcmp(const char *cs, const char *ct);
 
+#if defined(CONFIG_KASAN) && !defined(__SANITIZE_ADDRESS__)
+
+/*
+ * For files that not instrumented (e.g. mm/slub.c) we
+ * should use not instrumented version of mem* functions.
+ */
+
+#undef memcpy
+#define memcpy(dst, src, len) __memcpy(dst, src, len)
+#define memmove(dst, src, len) __memmove(dst, src, len)
+#define memset(s, c, n) __memset(s, c, n)
+#endif
+
 #endif /* __KERNEL__ */
 
 #endif /* _ASM_X86_STRING_64_H */
diff --git a/arch/x86/kernel/x8664_ksyms_64.c b/arch/x86/kernel/x8664_ksyms_64.c
index 040681928e9d..37d8fa4438f0 100644
--- a/arch/x86/kernel/x8664_ksyms_64.c
+++ b/arch/x86/kernel/x8664_ksyms_64.c
@@ -50,13 +50,19 @@ EXPORT_SYMBOL(csum_partial);
 #undef memset
 #undef memmove
 
+extern void *__memset(void *, int, __kernel_size_t);
+extern void *__memcpy(void *, const void *, __kernel_size_t);
+extern void *__memmove(void *, const void *, __kernel_size_t);
 extern void *memset(void *, int, __kernel_size_t);
 extern void *memcpy(void *, const void *, __kernel_size_t);
-extern void *__memcpy(void *, const void *, __kernel_size_t);
+extern void *memmove(void *, const void *, __kernel_size_t);
+
+EXPORT_SYMBOL(__memset);
+EXPORT_SYMBOL(__memcpy);
+EXPORT_SYMBOL(__memmove);
 
 EXPORT_SYMBOL(memset);
 EXPORT_SYMBOL(memcpy);
-EXPORT_SYMBOL(__memcpy);
 EXPORT_SYMBOL(memmove);
 
 #ifndef CONFIG_DEBUG_VIRTUAL
diff --git a/arch/x86/lib/memcpy_64.S b/arch/x86/lib/memcpy_64.S
index 56313a326188..89b53c9968e7 100644
--- a/arch/x86/lib/memcpy_64.S
+++ b/arch/x86/lib/memcpy_64.S
@@ -53,6 +53,8 @@
 .Lmemcpy_e_e:
 	.previous
 
+.weak memcpy
+
 ENTRY(__memcpy)
 ENTRY(memcpy)
 	CFI_STARTPROC
@@ -199,8 +201,8 @@ ENDPROC(__memcpy)
 	 * only outcome...
 	 */
 	.section .altinstructions, "a"
-	altinstruction_entry memcpy,.Lmemcpy_c,X86_FEATURE_REP_GOOD,\
+	altinstruction_entry __memcpy,.Lmemcpy_c,X86_FEATURE_REP_GOOD,\
 			     .Lmemcpy_e-.Lmemcpy_c,.Lmemcpy_e-.Lmemcpy_c
-	altinstruction_entry memcpy,.Lmemcpy_c_e,X86_FEATURE_ERMS, \
+	altinstruction_entry __memcpy,.Lmemcpy_c_e,X86_FEATURE_ERMS, \
 			     .Lmemcpy_e_e-.Lmemcpy_c_e,.Lmemcpy_e_e-.Lmemcpy_c_e
 	.previous
diff --git a/arch/x86/lib/memmove_64.S b/arch/x86/lib/memmove_64.S
index 65268a6104f4..9c4b530575da 100644
--- a/arch/x86/lib/memmove_64.S
+++ b/arch/x86/lib/memmove_64.S
@@ -24,7 +24,10 @@
  * Output:
  * rax: dest
  */
+.weak memmove
+
 ENTRY(memmove)
+ENTRY(__memmove)
 	CFI_STARTPROC
 
 	/* Handle more 32 bytes in loop */
@@ -220,4 +223,5 @@ ENTRY(memmove)
 		.Lmemmove_end_forward-.Lmemmove_begin_forward,	\
 		.Lmemmove_end_forward_efs-.Lmemmove_begin_forward_efs
 	.previous
+ENDPROC(__memmove)
 ENDPROC(memmove)
diff --git a/arch/x86/lib/memset_64.S b/arch/x86/lib/memset_64.S
index 2dcb3808cbda..6f44935c6a60 100644
--- a/arch/x86/lib/memset_64.S
+++ b/arch/x86/lib/memset_64.S
@@ -56,6 +56,8 @@
 .Lmemset_e_e:
 	.previous
 
+.weak memset
+
 ENTRY(memset)
 ENTRY(__memset)
 	CFI_STARTPROC
@@ -147,8 +149,8 @@ ENDPROC(__memset)
          * feature to implement the right patch order.
 	 */
 	.section .altinstructions,"a"
-	altinstruction_entry memset,.Lmemset_c,X86_FEATURE_REP_GOOD,\
-			     .Lfinal-memset,.Lmemset_e-.Lmemset_c
-	altinstruction_entry memset,.Lmemset_c_e,X86_FEATURE_ERMS, \
-			     .Lfinal-memset,.Lmemset_e_e-.Lmemset_c_e
+	altinstruction_entry __memset,.Lmemset_c,X86_FEATURE_REP_GOOD,\
+			     .Lfinal-__memset,.Lmemset_e-.Lmemset_c
+	altinstruction_entry __memset,.Lmemset_c_e,X86_FEATURE_ERMS, \
+			     .Lfinal-__memset,.Lmemset_e_e-.Lmemset_c_e
 	.previous
diff --git a/drivers/firmware/efi/libstub/efistub.h b/drivers/firmware/efi/libstub/efistub.h
index 2be10984a67a..47437b16b186 100644
--- a/drivers/firmware/efi/libstub/efistub.h
+++ b/drivers/firmware/efi/libstub/efistub.h
@@ -5,6 +5,10 @@
 /* error code which can't be mistaken for valid address */
 #define EFI_ERROR	(~0UL)
 
+#undef memcpy
+#undef memset
+#undef memmove
+
 void efi_char16_printk(efi_system_table_t *, efi_char16_t *);
 
 efi_status_t efi_open_volume(efi_system_table_t *sys_table_arg, void *__image,
diff --git a/mm/kasan/kasan.c b/mm/kasan/kasan.c
index dc83f070edb6..799c52b9826c 100644
--- a/mm/kasan/kasan.c
+++ b/mm/kasan/kasan.c
@@ -255,6 +255,35 @@ static __always_inline void check_memory_region(unsigned long addr,
 	kasan_report(addr, size, write, _RET_IP_);
 }
 
+void __asan_loadN(unsigned long addr, size_t size);
+void __asan_storeN(unsigned long addr, size_t size);
+
+#undef memset
+void *memset(void *addr, int c, size_t len)
+{
+	__asan_storeN((unsigned long)addr, len);
+
+	return __memset(addr, c, len);
+}
+
+#undef memmove
+void *memmove(void *dest, const void *src, size_t len)
+{
+	__asan_loadN((unsigned long)src, len);
+	__asan_storeN((unsigned long)dest, len);
+
+	return __memmove(dest, src, len);
+}
+
+#undef memcpy
+void *memcpy(void *dest, const void *src, size_t len)
+{
+	__asan_loadN((unsigned long)src, len);
+	__asan_storeN((unsigned long)dest, len);
+
+	return __memcpy(dest, src, len);
+}
+
 void kasan_alloc_pages(struct page *page, unsigned int order)
 {
 	if (likely(!PageHighMem(page)))
-- 
2.42.0

```
