---
layout:     post
title:      "[PATCH 23/33] [PATCH] KVM: MMU: If an empty shadow page is not empty, report more info"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:50 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 139bdb2d9e410d448281057a37b53770324ccac8 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:50 -0800
Subject: [PATCH 23/33] [PATCH] KVM: MMU: If an empty shadow page is not empty,
 report more info

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c | 12 ++++++++----
 1 file changed, 8 insertions(+), 4 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index b9ba240144b7..8cf3688f7e70 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -305,12 +305,16 @@ static void rmap_write_protect(struct kvm *kvm, u64 gfn)
 
 static int is_empty_shadow_page(hpa_t page_hpa)
 {
-	u32 *pos;
-	u32 *end;
-	for (pos = __va(page_hpa), end = pos + PAGE_SIZE / sizeof(u32);
+	u64 *pos;
+	u64 *end;
+
+	for (pos = __va(page_hpa), end = pos + PAGE_SIZE / sizeof(u64);
 		      pos != end; pos++)
-		if (*pos != 0)
+		if (*pos != 0) {
+			printk(KERN_ERR "%s: %p %llx\n", __FUNCTION__,
+			       pos, *pos);
 			return 0;
+		}
 	return 1;
 }
 
-- 
2.42.0

```