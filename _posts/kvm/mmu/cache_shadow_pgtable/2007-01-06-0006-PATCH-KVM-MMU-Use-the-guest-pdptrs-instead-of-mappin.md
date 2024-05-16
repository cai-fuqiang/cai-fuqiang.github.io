---
layout:     post
title:      "[PATCH 06/33] [PATCH] KVM: MMU: Use the guest pdptrs instead of mapping cr3 in pae mode"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:41 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 1b0973bd8f788178f21d9eebdd879203464f8528 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:41 -0800
Subject: [PATCH 06/33] [PATCH] KVM: MMU: Use the guest pdptrs instead of
 mapping cr3 in pae mode

This lets us not write protect a partial page, and is anyway what a real
processor does.

> 这让我们不必对partial page 进行写保护，无论如何，这都是真正的处理器所做的。
```
> 这里为什么要强调硬件怎么做呢?
>
> 因为KVM 是模拟真实的硬件, 硬件没有做的事情, KVM 也可以不做避免引起复杂度,
> 或者避免和hardware 的行为不一致.
>
> 在回过头来看这个patch, 在该patch引入之前, KVM 为 pdpte 也分配了一个 shadow pgtable,
> 但是这个pgtable中只有32-byte的数据存放着. 其他的空间可以供软件做别的用途. 在引入
> 该系列patch后, 需要wp pgtable, 那么这个"partial pgtable" 可能会被软件频繁修改, 导致
> 频繁出发VM-exit.
>
> 其实硬件层面也有这个问题: 内存中的pgtable和 TLB/pdpte register 不同步的问题.(当然
> 这里是和pdpte register 不同步), 硬件的做法是需要软件来主动sync, 例如 flush tlb or
> load pdpte register.
>
> 而这里也是用了硬件的这种做法, 不去wp pdpte shadow pgtable, 只有当guest 主动 load 
> pdpte register时, trap到kvm, kvm再去做sync 
{: .prompt-tip}

```diff
Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm_main.c    |  2 ++
 drivers/kvm/paging_tmpl.h | 28 ++++++++++++++++++----------
 2 files changed, 20 insertions(+), 10 deletions(-)

diff --git a/drivers/kvm/kvm_main.c b/drivers/kvm/kvm_main.c
index 4512d8c39c84..68e121eeccbc 100644
--- a/drivers/kvm/kvm_main.c
+++ b/drivers/kvm/kvm_main.c
@@ -1491,6 +1491,8 @@ static int kvm_dev_ioctl_set_sregs(struct kvm *kvm, struct kvm_sregs *sregs)
 
 	mmu_reset_needed |= vcpu->cr4 != sregs->cr4;
 	kvm_arch_ops->set_cr4(vcpu, sregs->cr4);
+	if (!is_long_mode(vcpu) && is_pae(vcpu))
+		load_pdptrs(vcpu, vcpu->cr3);
 
 	if (mmu_reset_needed)
 		kvm_mmu_reset_context(vcpu);
diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index 963d80e2271f..3ade9445ab23 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -67,18 +67,28 @@ static void FNAME(walk_addr)(struct guest_walker *walker,
 	hpa_t hpa;
 	struct kvm_memory_slot *slot;
 	pt_element_t *ptep;
+	pt_element_t root;
 
 	walker->level = vcpu->mmu.root_level;
-	walker->table_gfn = (vcpu->cr3 & PT64_BASE_ADDR_MASK) >> PAGE_SHIFT;
+	walker->table = NULL;
+	root = vcpu->cr3;
+#if PTTYPE == 64
+	if (!is_long_mode(vcpu)) {
+		walker->ptep = &vcpu->pdptrs[(addr >> 30) & 3];
+		root = *walker->ptep;
+		if (!(root & PT_PRESENT_MASK))
+			return;
+		--walker->level;
+	}
+#endif
+	walker->table_gfn = (root & PT64_BASE_ADDR_MASK) >> PAGE_SHIFT;
 	slot = gfn_to_memslot(vcpu->kvm, walker->table_gfn);
-	hpa = safe_gpa_to_hpa(vcpu, vcpu->cr3 & PT64_BASE_ADDR_MASK);
+	hpa = safe_gpa_to_hpa(vcpu, root & PT64_BASE_ADDR_MASK);
 	walker->table = kmap_atomic(pfn_to_page(hpa >> PAGE_SHIFT), KM_USER0);
 
 	ASSERT((!is_long_mode(vcpu) && is_pae(vcpu)) ||
 	       (vcpu->cr3 & ~(PAGE_MASK | CR3_FLAGS_MASK)) == 0);
 
-	walker->table = (pt_element_t *)( (unsigned long)walker->table |
-		(unsigned long)(vcpu->cr3 & ~(PAGE_MASK | CR3_FLAGS_MASK)) );
 	walker->inherited_ar = PT_USER_MASK | PT_WRITABLE_MASK;
 
 	for (;;) {
@@ -89,11 +99,8 @@ static void FNAME(walk_addr)(struct guest_walker *walker,
 		ASSERT(((unsigned long)walker->table & PAGE_MASK) ==
 		       ((unsigned long)ptep & PAGE_MASK));
 
-		/* Don't set accessed bit on PAE PDPTRs */
-		if (vcpu->mmu.root_level != 3 || walker->level != 3)
-			if ((*ptep & (PT_PRESENT_MASK | PT_ACCESSED_MASK))
-			    == PT_PRESENT_MASK)
-				*ptep |= PT_ACCESSED_MASK;
+		if (is_present_pte(*ptep) && !(*ptep &  PT_ACCESSED_MASK))
+			*ptep |= PT_ACCESSED_MASK;
 
 		if (!is_present_pte(*ptep) ||
 		    walker->level == PT_PAGE_TABLE_LEVEL ||
@@ -116,7 +123,8 @@ static void FNAME(walk_addr)(struct guest_walker *walker,
 
 static void FNAME(release_walker)(struct guest_walker *walker)
 {
-	kunmap_atomic(walker->table, KM_USER0);
+	if (walker->table)
+		kunmap_atomic(walker->table, KM_USER0);
 }
 
 static void FNAME(set_pte)(struct kvm_vcpu *vcpu, u64 guest_pte,
-- 
2.42.0

```
