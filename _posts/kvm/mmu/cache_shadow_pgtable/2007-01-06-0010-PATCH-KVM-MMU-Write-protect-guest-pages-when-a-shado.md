---
layout:     post
title:      "[PATCH 10/33] [PATCH] KVM: MMU: Write protect guest pages when a shadow is created for them"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:43 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 374cbac0333ddf5cf1c6637efaf7f3adcc67fd75 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:43 -0800
Subject: [PATCH 10/33] [PATCH] KVM: MMU: Write protect guest pages when a
 shadow is created for them

When we cache a guest page table into a shadow page table, we need to prevent
further access to that page by the guest, as that would render the cache
incoherent.

> 当我们将guest pgtable 缓存到影子页表中时，我们需要防止guest进一步访问该页面，
> 因为这会导致缓存 incoherent.

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c         | 72 +++++++++++++++++++++++++++++----------
 drivers/kvm/paging_tmpl.h |  1 +
 2 files changed, 55 insertions(+), 18 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 47c699c21c08..ba813f49f8aa 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -274,6 +274,35 @@ static void rmap_remove(struct kvm *kvm, u64 *spte)
 	}
 }

+static void rmap_write_protect(struct kvm *kvm, u64 gfn)
+{
+	struct page *page;
+	struct kvm_memory_slot *slot;
+	struct kvm_rmap_desc *desc;
+	u64 *spte;
+
+	slot = gfn_to_memslot(kvm, gfn);
+	BUG_ON(!slot);
+	page = gfn_to_page(slot, gfn);
+
 //通过反向映射, 找到所有相关的spte, 将其 PT_WRITABLE_MASK clear.
+	while (page->private) {
+		if (!(page->private & 1))
+			spte = (u64 *)page->private;
+		else {
+			desc = (struct kvm_rmap_desc *)(page->private & ~1ul);
+			spte = desc->shadow_ptes[0];
+		}
+		BUG_ON(!spte);
+		BUG_ON((*spte & PT64_BASE_ADDR_MASK) !=
+		       page_to_pfn(page) << PAGE_SHIFT);
+		BUG_ON(!(*spte & PT_PRESENT_MASK));
+		BUG_ON(!(*spte & PT_WRITABLE_MASK));
+		rmap_printk("rmap_write_protect: spte %p %llx\n", spte, *spte);
    //而rmap的作用是,当一个page从normal page 变为pgtable时, 找到所有
    //能访问到它的spte, 将其修改为 NOT WRITABLE, 
    //而如果修改后, 所有的spte都不是 WRITABLE了, 所以不再需要rmap了,
    //这里会执行rmap_remove
+		rmap_remove(kvm, spte);
+		*spte &= ~(u64)PT_WRITABLE_MASK;
+	}
+}
+
 static void kvm_mmu_free_page(struct kvm_vcpu *vcpu, hpa_t page_hpa)
 {
 	struct kvm_mmu_page *page_head = page_header(page_hpa);
@@ -444,6 +473,8 @@ static struct kvm_mmu_page *kvm_mmu_get_page(struct kvm_vcpu *vcpu,
 	page->gfn = gfn;
 	page->role = role;
 	hlist_add_head(&page->hash_link, bucket);
  //如果不是 metaphysical , 说明该shadow pgtable在guest中对应的有pgtable, 需要wp该page,
  //也就是让guest访问该 page时, 触发 wp
+	if (!metaphysical)
+		rmap_write_protect(vcpu->kvm, gfn);
 	return page;
 }
 
@@ -705,6 +736,7 @@ static void kvm_mmu_flush_tlb(struct kvm_vcpu *vcpu)
 
 static void paging_new_cr3(struct kvm_vcpu *vcpu)
 {
+	pgprintk("%s: cr3 %lx\n", __FUNCTION__, vcpu->cr3);
 	mmu_free_roots(vcpu);
 	mmu_alloc_roots(vcpu);
 	kvm_mmu_flush_tlb(vcpu);
@@ -727,24 +759,11 @@ static inline void set_pte_common(struct kvm_vcpu *vcpu,
 	*shadow_pte |= access_bits << PT_SHADOW_BITS_OFFSET;
 	if (!dirty)
 		access_bits &= ~PT_WRITABLE_MASK;
-	if (access_bits & PT_WRITABLE_MASK) {
-		struct kvm_mmu_page *shadow;
 
-		shadow = kvm_mmu_lookup_page(vcpu, gaddr >> PAGE_SHIFT);
-		if (shadow)
-			pgprintk("%s: found shadow page for %lx, marking ro\n",
-				 __FUNCTION__, (gfn_t)(gaddr >> PAGE_SHIFT));
-		if (shadow)
-			access_bits &= ~PT_WRITABLE_MASK;
-	}
-
-	if (access_bits & PT_WRITABLE_MASK)
-		mark_page_dirty(vcpu->kvm, gaddr >> PAGE_SHIFT);
+	paddr = gpa_to_hpa(vcpu, gaddr & PT64_BASE_ADDR_MASK);
 
 	*shadow_pte |= access_bits;
 
-	paddr = gpa_to_hpa(vcpu, gaddr & PT64_BASE_ADDR_MASK);
-
 	if (!(*shadow_pte & PT_GLOBAL_MASK))
 		mark_pagetable_nonglobal(shadow_pte);
 
@@ -752,11 +771,28 @@ static inline void set_pte_common(struct kvm_vcpu *vcpu,
 		*shadow_pte |= gaddr;
 		*shadow_pte |= PT_SHADOW_IO_MARK;
 		*shadow_pte &= ~PT_PRESENT_MASK;
-	} else {
-		*shadow_pte |= paddr;
-		page_header_update_slot(vcpu->kvm, shadow_pte, gaddr);
-		rmap_add(vcpu->kvm, shadow_pte);
+		return;
 	}
+
+	*shadow_pte |= paddr;
+
+	if (access_bits & PT_WRITABLE_MASK) {
+		struct kvm_mmu_page *shadow;
+
+		shadow = kvm_mmu_lookup_page(vcpu, gaddr >> PAGE_SHIFT);
+		if (shadow) {
+			pgprintk("%s: found shadow page for %lx, marking ro\n",
+				 __FUNCTION__, (gfn_t)(gaddr >> PAGE_SHIFT));
+			access_bits &= ~PT_WRITABLE_MASK;
+			*shadow_pte &= ~PT_WRITABLE_MASK;
+		}
+	}
+
+	if (access_bits & PT_WRITABLE_MASK)
+		mark_page_dirty(vcpu->kvm, gaddr >> PAGE_SHIFT);
+
+	page_header_update_slot(vcpu->kvm, shadow_pte, gaddr);
  //注意, 这里rmap_add() 并不会对 NO WRITABLE 的 shadow_pte指向
  //的page做反向映射, 详见: is_rmap_pte()
+	rmap_add(vcpu->kvm, shadow_pte);
 }
 
 static void inject_page_fault(struct kvm_vcpu *vcpu,
diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index f7cce443ca6f..cd71973c780c 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -133,6 +133,7 @@ static void FNAME(walk_addr)(struct guest_walker *walker,
 			 walker->level - 1, table_gfn);
 	}
 	walker->ptep = ptep;
+	pgprintk("%s: pte %llx\n", __FUNCTION__, (u64)*ptep);
 }
 
 static void FNAME(release_walker)(struct guest_walker *walker)
-- 
2.42.0

```