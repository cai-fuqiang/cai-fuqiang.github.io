---
layout:     post
title:      "[PATCH 06/19] mm: slub: introduce virt_to_obj function"
author:     "fuqiang"
date:       "Fri, 13 Feb 2015 14:39:31 -0800"
categories: [kasan]
tags:       [kasan_org_patch]
---

```diff
From 912f5fbf1d3060f25d6994aed0265c55b974b2e9 Mon Sep 17 00:00:00 2001
From: Andrey Ryabinin <a.ryabinin@samsung.com>
Date: Fri, 13 Feb 2015 14:39:31 -0800
Subject: [PATCH 06/19] mm: slub: introduce virt_to_obj function

virt_to_obj takes kmem_cache address, address of slab page, address x
pointing somewhere inside slab object, and returns address of the
beginning of object.

Signed-off-by: Andrey Ryabinin <a.ryabinin@samsung.com>
Acked-by: Christoph Lameter <cl@linux.com>
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
Cc: Pekka Enberg <penberg@kernel.org>
Cc: David Rientjes <rientjes@google.com>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 include/linux/slub_def.h | 16 ++++++++++++++++
 1 file changed, 16 insertions(+)

diff --git a/include/linux/slub_def.h b/include/linux/slub_def.h
index 9abf04ed0999..db7d5de00c5f 100644
--- a/include/linux/slub_def.h
+++ b/include/linux/slub_def.h
@@ -110,4 +110,20 @@ static inline void sysfs_slab_remove(struct kmem_cache *s)
 }
 #endif
 
+
+/**
+ * virt_to_obj - returns address of the beginning of object.
+ * @s: object's kmem_cache
+ * @slab_page: address of slab page
+ * @x: address within object memory range
+ *
+ * Returns address of the beginning of object
+ */
+static inline void *virt_to_obj(struct kmem_cache *s,
+				const void *slab_page,
+				const void *x)
+{
+	return (void *)x - ((x - slab_page) % s->size);
+}
+
 #endif /* _LINUX_SLUB_DEF_H */
-- 
2.42.0

```
