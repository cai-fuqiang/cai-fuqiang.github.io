---
layout:     post
title:      "[PATCH 17/19] kernel: add support for .init_array.* constructors"
author:     "fuqiang"
date:       "Fri, 13 Feb 2015 14:40:10 -0800"
categories: [kasan]
tags:       [kasan_org_patch]
---

```diff
From 9ddf82521c86ae07af79dbe5a93c52890f2bab23 Mon Sep 17 00:00:00 2001
From: Andrey Ryabinin <a.ryabinin@samsung.com>
Date: Fri, 13 Feb 2015 14:40:10 -0800
Subject: [PATCH 17/19] kernel: add support for .init_array.* constructors

KASan uses constructors for initializing redzones for global variables.
Globals instrumentation in GCC 4.9.2 produces constructors with priority
(.init_array.00099)

Currently kernel ignores such constructors.  Only constructors with
default priority supported (.init_array)

This patch adds support for constructors with priorities.  For kernel
image we put pointers to constructors between __ctors_start/__ctors_end
and do_ctors() will call them on start up.  For modules we merge
.init_array.* sections into resulting .init_array.  Module code properly
handles constructors in .init_array section.

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
 include/asm-generic/vmlinux.lds.h | 1 +
 scripts/module-common.lds         | 3 +++
 2 files changed, 4 insertions(+)

diff --git a/include/asm-generic/vmlinux.lds.h b/include/asm-generic/vmlinux.lds.h
index bee5d683074d..ac78910d7416 100644
--- a/include/asm-generic/vmlinux.lds.h
+++ b/include/asm-generic/vmlinux.lds.h
@@ -478,6 +478,7 @@
 #define KERNEL_CTORS()	. = ALIGN(8);			   \
 			VMLINUX_SYMBOL(__ctors_start) = .; \
 			*(.ctors)			   \
+			*(SORT(.init_array.*))		   \
 			*(.init_array)			   \
 			VMLINUX_SYMBOL(__ctors_end) = .;
 #else
diff --git a/scripts/module-common.lds b/scripts/module-common.lds
index bec15f908fc6..73a2c7da0e55 100644
--- a/scripts/module-common.lds
+++ b/scripts/module-common.lds
@@ -16,4 +16,7 @@ SECTIONS {
 	__kcrctab_unused	0 : { *(SORT(___kcrctab_unused+*)) }
 	__kcrctab_unused_gpl	0 : { *(SORT(___kcrctab_unused_gpl+*)) }
 	__kcrctab_gpl_future	0 : { *(SORT(___kcrctab_gpl_future+*)) }
+
+	. = ALIGN(8);
+	.init_array		0 : { *(SORT(.init_array.*)) *(.init_array) }
 }
-- 
2.42.0

```
