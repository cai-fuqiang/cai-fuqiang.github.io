---
layout:     post
title:      "[PATCH 19/33] [PATCH] KVM: MMU: Remove release_pt_page_64()"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:48 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 73f7198e738004671b885c443eb6f88df021c07f Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:48 -0800
Subject: [PATCH 19/33] [PATCH] KVM: MMU: Remove release_pt_page_64()

Unused.

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c | 29 -----------------------------
 1 file changed, 29 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index b7b05c44399d..53c3643038bb 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -609,35 +609,6 @@ hpa_t gva_to_hpa(struct kvm_vcpu *vcpu, gva_t gva)
 	return gpa_to_hpa(vcpu, gpa);
 }
 
-
-static void release_pt_page_64(struct kvm_vcpu *vcpu, hpa_t page_hpa,
-			       int level)
-{
-	u64 *pos;
-	u64 *end;
-
-	ASSERT(vcpu);
-	ASSERT(VALID_PAGE(page_hpa));
-	ASSERT(level <= PT64_ROOT_LEVEL && level > 0);
-
-	for (pos = __va(page_hpa), end = pos + PT64_ENT_PER_PAGE;
-	     pos != end; pos++) {
-		u64 current_ent = *pos;
-
-		if (is_present_pte(current_ent)) {
-			if (level != 1)
-				release_pt_page_64(vcpu,
-						  current_ent &
-						  PT64_BASE_ADDR_MASK,
-						  level - 1);
-			else
-				rmap_remove(vcpu->kvm, pos);
-		}
-		*pos = 0;
-	}
-	kvm_mmu_free_page(vcpu, page_hpa);
-}
-
 static void nonpaging_new_cr3(struct kvm_vcpu *vcpu)
 {
 }
-- 
2.42.0

```