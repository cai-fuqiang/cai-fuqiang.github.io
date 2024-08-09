---
layout:     post
title:      "[PATCH 07/19] mm: slub: share object_err function"
author:     "fuqiang"
date:       "Fri, 13 Feb 2015 14:39:35 -0800"
categories: [kasan]
tags:       [kasan_org_patch]
---

```diff
From 75c66def8d815201aa0386ecc7c66a5c8dbca1ee Mon Sep 17 00:00:00 2001
From: Andrey Ryabinin <a.ryabinin@samsung.com>
Date: Fri, 13 Feb 2015 14:39:35 -0800
Subject: [PATCH 07/19] mm: slub: share object_err function

Remove static and add function declarations to linux/slub_def.h so it
could be used by kernel address sanitizer.

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
 include/linux/slub_def.h | 3 +++
 mm/slub.c                | 2 +-
 2 files changed, 4 insertions(+), 1 deletion(-)

diff --git a/include/linux/slub_def.h b/include/linux/slub_def.h
index db7d5de00c5f..33885118523c 100644
--- a/include/linux/slub_def.h
+++ b/include/linux/slub_def.h
@@ -126,4 +126,7 @@ static inline void *virt_to_obj(struct kmem_cache *s,
 	return (void *)x - ((x - slab_page) % s->size);
 }
 
+void object_err(struct kmem_cache *s, struct page *page,
+		u8 *object, char *reason);
+
 #endif /* _LINUX_SLUB_DEF_H */
diff --git a/mm/slub.c b/mm/slub.c
index 783505ba2052..6833b73ef6b3 100644
--- a/mm/slub.c
+++ b/mm/slub.c
@@ -629,7 +629,7 @@ static void print_trailer(struct kmem_cache *s, struct page *page, u8 *p)
 	dump_stack();
 }
 
-static void object_err(struct kmem_cache *s, struct page *page,
+void object_err(struct kmem_cache *s, struct page *page,
 			u8 *object, char *reason)
 {
 	slab_bug(s, "%s", reason);
-- 
2.42.0

```
