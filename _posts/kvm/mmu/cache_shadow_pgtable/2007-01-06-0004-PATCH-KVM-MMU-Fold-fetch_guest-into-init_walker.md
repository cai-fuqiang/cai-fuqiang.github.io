---
layout:     post
title:      "[PATCH 04/33] [PATCH] KVM: MMU: Fold fetch_guest() into init_walker()"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:40 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```
From ac79c978f173586ab3624427c89cd22b393cabd4 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:40 -0800
```

Subject: [PATCH 04/33] [PATCH] KVM: MMU: Fold fetch_guest() into init_walker()

It is never necessary to fetch a guest entry from an intermediate page table
level (except for large pages), so avoid some confusion by always descending
into the lowest possible level.

> ```
> intermediate /ˌɪntərˈmiːdiət/: 中间的
> descend /dɪˈsend/: 下降
> ```
> 从来没有必要从中间页表级别获取guest条目（大页除外），因此请始终下降到尽可能
> 低的级别，以避免一些混乱。

Rename init_walker() to walk_addr() as it is no longer restricted to
initialization.

> 将 init_walker() 重命名为 walk_addr()，因为它不再局限于初始化。

```diff
Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/paging_tmpl.h | 105 +++++++++++++++++---------------------
 1 file changed, 47 insertions(+), 58 deletions(-)

diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index 3a35c8067dec..963d80e2271f 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -54,14 +54,19 @@ struct guest_walker {
 	int level;
 	gfn_t table_gfn;
 	pt_element_t *table;
+	pt_element_t *ptep;
 	pt_element_t inherited_ar;
 };
 
-static void FNAME(init_walker)(struct guest_walker *walker,
-			       struct kvm_vcpu *vcpu)
+/*
+ * Fetch a guest pte for a guest virtual address
+ */
+static void FNAME(walk_addr)(struct guest_walker *walker,
+			     struct kvm_vcpu *vcpu, gva_t addr)
 {
 	hpa_t hpa;
 	struct kvm_memory_slot *slot;
+	pt_element_t *ptep;
 
 	walker->level = vcpu->mmu.root_level;
 	walker->table_gfn = (vcpu->cr3 & PT64_BASE_ADDR_MASK) >> PAGE_SHIFT;
@@ -75,6 +80,38 @@ static void FNAME(init_walker)(struct guest_walker *walker,
 	walker->table = (pt_element_t *)( (unsigned long)walker->table |
 		(unsigned long)(vcpu->cr3 & ~(PAGE_MASK | CR3_FLAGS_MASK)) );
 	walker->inherited_ar = PT_USER_MASK | PT_WRITABLE_MASK;
+
+	for (;;) {
+		int index = PT_INDEX(addr, walker->level);
+		hpa_t paddr;
+
+		ptep = &walker->table[index];
+		ASSERT(((unsigned long)walker->table & PAGE_MASK) ==
+		       ((unsigned long)ptep & PAGE_MASK));
+
+		/* Don't set accessed bit on PAE PDPTRs */
+		if (vcpu->mmu.root_level != 3 || walker->level != 3)
+			if ((*ptep & (PT_PRESENT_MASK | PT_ACCESSED_MASK))
+			    == PT_PRESENT_MASK)
+				*ptep |= PT_ACCESSED_MASK;
+
+		if (!is_present_pte(*ptep) ||
+		    walker->level == PT_PAGE_TABLE_LEVEL ||
+		    (walker->level == PT_DIRECTORY_LEVEL &&
+		     (*ptep & PT_PAGE_SIZE_MASK) &&
+		     (PTTYPE == 64 || is_pse(vcpu))))
+			break;
+
+		if (walker->level != 3 || is_long_mode(vcpu))
+			walker->inherited_ar &= walker->table[index];
+		walker->table_gfn = (*ptep & PT_BASE_ADDR_MASK) >> PAGE_SHIFT;
+		paddr = safe_gpa_to_hpa(vcpu, *ptep & PT_BASE_ADDR_MASK);
+		kunmap_atomic(walker->table, KM_USER0);
+		walker->table = kmap_atomic(pfn_to_page(paddr >> PAGE_SHIFT),
+					    KM_USER0);
+		--walker->level;
+	}
+	walker->ptep = ptep;
 }
 
 static void FNAME(release_walker)(struct guest_walker *walker)
@@ -109,41 +146,6 @@ static void FNAME(set_pde)(struct kvm_vcpu *vcpu, u64 guest_pde,
 		       guest_pde & PT_DIRTY_MASK, access_bits);
 }
 
-/*
- * Fetch a guest pte from a specific level in the paging hierarchy.
- */
-static pt_element_t *FNAME(fetch_guest)(struct kvm_vcpu *vcpu,
-					struct guest_walker *walker,
-					int level,
-					gva_t addr)
-{
-
-	ASSERT(level > 0  && level <= walker->level);
-
-	for (;;) {
-		int index = PT_INDEX(addr, walker->level);
-		hpa_t paddr;
-
-		ASSERT(((unsigned long)walker->table & PAGE_MASK) ==
-		       ((unsigned long)&walker->table[index] & PAGE_MASK));
-		if (level == walker->level ||
-		    !is_present_pte(walker->table[index]) ||
-		    (walker->level == PT_DIRECTORY_LEVEL &&
-		     (walker->table[index] & PT_PAGE_SIZE_MASK) &&
-		     (PTTYPE == 64 || is_pse(vcpu))))
-			return &walker->table[index];
-		if (walker->level != 3 || is_long_mode(vcpu))
-			walker->inherited_ar &= walker->table[index];
-		walker->table_gfn = (walker->table[index] & PT_BASE_ADDR_MASK)
-			>> PAGE_SHIFT;
-		paddr = safe_gpa_to_hpa(vcpu, walker->table[index] & PT_BASE_ADDR_MASK);
-		kunmap_atomic(walker->table, KM_USER0);
-		walker->table = kmap_atomic(pfn_to_page(paddr >> PAGE_SHIFT),
-					    KM_USER0);
-		--walker->level;
-	}
-}
-
 /*
  * Fetch a shadow pte for a specific level in the paging hierarchy.
  */
@@ -153,6 +155,10 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 	hpa_t shadow_addr;
 	int level;
 	u64 *prev_shadow_ent = NULL;
+	pt_element_t *guest_ent = walker->ptep;
+
+	if (!is_present_pte(*guest_ent))
+		return NULL;
 
 	shadow_addr = vcpu->mmu.root_hpa;
 	level = vcpu->mmu.shadow_root_level;
@@ -160,7 +166,6 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 	for (; ; level--) {
 		u32 index = SHADOW_PT_INDEX(addr, level);
 		u64 *shadow_ent = ((u64 *)__va(shadow_addr)) + index;
-		pt_element_t *guest_ent;
 		u64 shadow_pte;
 
 		if (is_present_pte(*shadow_ent) || is_io_pte(*shadow_ent)) {
@@ -171,21 +176,6 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 			continue;
 		}
 
-		if (PTTYPE == 32 && level > PT32_ROOT_LEVEL) {
-			ASSERT(level == PT32E_ROOT_LEVEL);
-			guest_ent = FNAME(fetch_guest)(vcpu, walker,
-						       PT32_ROOT_LEVEL, addr);
-		} else
-			guest_ent = FNAME(fetch_guest)(vcpu, walker,
-						       level, addr);
-
-		if (!is_present_pte(*guest_ent))
-			return NULL;
-
-		/* Don't set accessed bit on PAE PDPTRs */
-		if (vcpu->mmu.root_level != 3 || walker->level != 3)
-			*guest_ent |= PT_ACCESSED_MASK;
-
 		if (level == PT_PAGE_TABLE_LEVEL) {
 
 			if (walker->level == PT_DIRECTORY_LEVEL) {
@@ -253,7 +243,7 @@ static int FNAME(fix_write_pf)(struct kvm_vcpu *vcpu,
 			*shadow_ent &= ~PT_USER_MASK;
 		}
 
-	guest_ent = FNAME(fetch_guest)(vcpu, walker, PT_PAGE_TABLE_LEVEL, addr);
+	guest_ent = walker->ptep;
 
 	if (!is_present_pte(*guest_ent)) {
 		*shadow_ent = 0;
@@ -296,7 +286,7 @@ static int FNAME(page_fault)(struct kvm_vcpu *vcpu, gva_t addr,
 	 * Look up the shadow pte for the faulting address.
 	 */
 	for (;;) {
-		FNAME(init_walker)(&walker, vcpu);
+		FNAME(walk_addr)(&walker, vcpu, addr);
 		shadow_pte = FNAME(fetch)(vcpu, addr, &walker);
 		if (IS_ERR(shadow_pte)) {  /* must be -ENOMEM */
 			nonpaging_flush(vcpu);
@@ -357,9 +347,8 @@ static gpa_t FNAME(gva_to_gpa)(struct kvm_vcpu *vcpu, gva_t vaddr)
 	pt_element_t guest_pte;
 	gpa_t gpa;
 
-	FNAME(init_walker)(&walker, vcpu);
-	guest_pte = *FNAME(fetch_guest)(vcpu, &walker, PT_PAGE_TABLE_LEVEL,
-					vaddr);
+	FNAME(walk_addr)(&walker, vcpu, vaddr);
+	guest_pte = *walker.ptep;
 	FNAME(release_walker)(&walker);
 
 	if (!is_present_pte(guest_pte))
-- 
2.42.0

```