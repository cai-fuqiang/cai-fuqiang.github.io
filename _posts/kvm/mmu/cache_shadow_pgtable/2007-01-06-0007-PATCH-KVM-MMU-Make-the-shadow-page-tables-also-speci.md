---
layout:     post
title:      "[PATCH 07/33] [PATCH] KVM: MMU: Make the shadow page tables also special-case pae"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:41 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From aef3d3fe1314f2a130f5ccc7114df20865ba784f Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:41 -0800
Subject: [PATCH 07/33] [PATCH] KVM: MMU: Make the shadow page tables also
 special-case pae

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/paging_tmpl.h | 11 +++++++----
 1 file changed, 7 insertions(+), 4 deletions(-)

diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index 3ade9445ab23..7af49ae80e5a 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -170,6 +170,11 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 
 	shadow_addr = vcpu->mmu.root_hpa;
 	level = vcpu->mmu.shadow_root_level;
+	if (level == PT32E_ROOT_LEVEL) {
+		shadow_addr = vcpu->mmu.pae_root[(addr >> 30) & 3];
+		shadow_addr &= PT64_BASE_ADDR_MASK;
+		--level;
+	}
 
 	for (; ; level--) {
 		u32 index = SHADOW_PT_INDEX(addr, level);
@@ -202,10 +207,8 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 		shadow_addr = kvm_mmu_alloc_page(vcpu, shadow_ent);
 		if (!VALID_PAGE(shadow_addr))
 			return ERR_PTR(-ENOMEM);
-		shadow_pte = shadow_addr | PT_PRESENT_MASK;
-		if (vcpu->mmu.root_level > 3 || level != 3)
-			shadow_pte |= PT_ACCESSED_MASK
-				| PT_WRITABLE_MASK | PT_USER_MASK;
+		shadow_pte = shadow_addr | PT_PRESENT_MASK | PT_ACCESSED_MASK
+			| PT_WRITABLE_MASK | PT_USER_MASK;
 		*shadow_ent = shadow_pte;
 		prev_shadow_ent = shadow_ent;
 	}
-- 
2.42.0

```