---
layout:     post
title:      "[PATCH 02/33] [PATCH] KVM: MMU: Teach the page table walker to track guest page table gfns"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:39 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```
From 6bcbd6aba00fced696fc99f1a4fcd7ac7d42d6ef Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:39 -0800
```

Subject: [PATCH 02/33] [PATCH] KVM: MMU: Teach the page table walker to track
 guest page table gfns

Saving the table gfns removes the need to walk the guest and host page tables
in lockstep.
> ```
> lockstep: 步调一致; 紧密步伐
> ```
>
> 保存table gfns 避免了需要遍历guest 和host 页表来同步

```diff
Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/paging_tmpl.h | 7 +++++--
 1 file changed, 5 insertions(+), 2 deletions(-)

diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index 8c48528a6e89..3a35c8067dec 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -52,6 +52,7 @@
  */
 struct guest_walker {
 	int level;
+	gfn_t table_gfn;
 	pt_element_t *table;
 	pt_element_t inherited_ar;
 };
@@ -63,8 +64,8 @@ static void FNAME(init_walker)(struct guest_walker *walker,
 	struct kvm_memory_slot *slot;
 
 	walker->level = vcpu->mmu.root_level;
-	slot = gfn_to_memslot(vcpu->kvm,
-			      (vcpu->cr3 & PT64_BASE_ADDR_MASK) >> PAGE_SHIFT);
+	walker->table_gfn = (vcpu->cr3 & PT64_BASE_ADDR_MASK) >> PAGE_SHIFT;
+	slot = gfn_to_memslot(vcpu->kvm, walker->table_gfn);
 	hpa = safe_gpa_to_hpa(vcpu, vcpu->cr3 & PT64_BASE_ADDR_MASK);
 	walker->table = kmap_atomic(pfn_to_page(hpa >> PAGE_SHIFT), KM_USER0);
 
@@ -133,6 +134,8 @@ static pt_element_t *FNAME(fetch_guest)(struct kvm_vcpu *vcpu,
 			return &walker->table[index];
 		if (walker->level != 3 || is_long_mode(vcpu))
 			walker->inherited_ar &= walker->table[index];
+		walker->table_gfn = (walker->table[index] & PT_BASE_ADDR_MASK)
+			>> PAGE_SHIFT;
 		paddr = safe_gpa_to_hpa(vcpu, walker->table[index] & PT_BASE_ADDR_MASK);
 		kunmap_atomic(walker->table, KM_USER0);
 		walker->table = kmap_atomic(pfn_to_page(paddr >> PAGE_SHIFT),
-- 
2.42.0

```