---
layout:     post
title:      "[PATCH 08/19] mm: slub: introduce metadata_access_enable()/metadata_access_disable()"
author:     "fuqiang"
date:       "Fri, 13 Feb 2015 14:39:38 -0800"
categories: [kasan]
tags:       [kasan_org_patch]
---

```diff
From a79316c6178ca419e35feef47d47f50b4e0ee9f2 Mon Sep 17 00:00:00 2001
From: Andrey Ryabinin <a.ryabinin@samsung.com>
Date: Fri, 13 Feb 2015 14:39:38 -0800
Subject: [PATCH 08/19] mm: slub: introduce
 metadata_access_enable()/metadata_access_disable()

It's ok for slub to access memory that marked by kasan as inaccessible
(object's metadata).  Kasan shouldn't print report in that case because
these accesses are valid.  Disabling instrumentation of slub.c code is not
enough to achieve this because slub passes pointer to object's metadata
into external functions like memchr_inv().

We don't want to disable instrumentation for memchr_inv() because this is
quite generic function, and we don't want to miss bugs.

metadata_access_enable/metadata_access_disable used to tell KASan where
accesses to metadata starts/end, so we could temporarily disable KASan
reports.

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
 mm/slub.c | 25 +++++++++++++++++++++++++
 1 file changed, 25 insertions(+)

diff --git a/mm/slub.c b/mm/slub.c
index 6833b73ef6b3..37555ad8894d 100644
--- a/mm/slub.c
+++ b/mm/slub.c
@@ -20,6 +20,7 @@
 #include <linux/proc_fs.h>
 #include <linux/notifier.h>
 #include <linux/seq_file.h>
+#include <linux/kasan.h>
 #include <linux/kmemcheck.h>
 #include <linux/cpu.h>
 #include <linux/cpuset.h>
@@ -467,13 +468,31 @@ static int slub_debug;
 static char *slub_debug_slabs;
 static int disable_higher_order_debug;
 
+/*
+ * slub is about to manipulate internal object metadata.  This memory lies
+ * outside the range of the allocated object, so accessing it would normally
+ * be reported by kasan as a bounds error.  metadata_access_enable() is used
+ * to tell kasan that these accesses are OK.
+ */
+static inline void metadata_access_enable(void)
+{
+	kasan_disable_current();
+}
+
+static inline void metadata_access_disable(void)
+{
+	kasan_enable_current();
+}
+
 /*
  * Object debugging
  */
 static void print_section(char *text, u8 *addr, unsigned int length)
 {
+	metadata_access_enable();
 	print_hex_dump(KERN_ERR, text, DUMP_PREFIX_ADDRESS, 16, 1, addr,
 			length, 1);
+	metadata_access_disable();
 }
 
 static struct track *get_track(struct kmem_cache *s, void *object,
@@ -503,7 +522,9 @@ static void set_track(struct kmem_cache *s, void *object,
 		trace.max_entries = TRACK_ADDRS_COUNT;
 		trace.entries = p->addrs;
 		trace.skip = 3;
+		metadata_access_enable();
 		save_stack_trace(&trace);
+		metadata_access_disable();
 
 		/* See rant in lockdep.c */
 		if (trace.nr_entries != 0 &&
@@ -677,7 +698,9 @@ static int check_bytes_and_report(struct kmem_cache *s, struct page *page,
 	u8 *fault;
 	u8 *end;
 
+	metadata_access_enable();
 	fault = memchr_inv(start, value, bytes);
+	metadata_access_disable();
 	if (!fault)
 		return 1;
 
@@ -770,7 +793,9 @@ static int slab_pad_check(struct kmem_cache *s, struct page *page)
 	if (!remainder)
 		return 1;
 
+	metadata_access_enable();
 	fault = memchr_inv(end - remainder, POISON_INUSE, remainder);
+	metadata_access_disable();
 	if (!fault)
 		return 1;
 	while (end > fault && end[-1] == POISON_INUSE)
-- 
2.42.0

```
