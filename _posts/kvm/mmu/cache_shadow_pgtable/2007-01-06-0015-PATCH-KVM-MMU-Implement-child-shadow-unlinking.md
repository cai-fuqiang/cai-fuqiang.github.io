---
layout:     post
title:      "[PATCH 15/33] [PATCH] KVM: MMU: Implement child shadow unlinking"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:46 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 697fe2e24ac49f03a82f6cfe5d77f7a2122ff382 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:46 -0800
Subject: [PATCH 15/33] [PATCH] KVM: MMU: Implement child shadow unlinking

When removing a page table, we must maintain the parent_pte field all child
shadow page tables.

> 当删除页表时，我们必须维护所有子影子页表的parent_pte字段。 
```

> 该patch, 主要是来解除该shadow pgtable和其child的映射关系

```diff
Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c | 42 ++++++++++++++++++++++++++++++++++++++----
 1 file changed, 38 insertions(+), 4 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 1484b7211717..7e20dbf4f84c 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -402,12 +402,21 @@ static void mmu_page_remove_parent_pte(struct kvm_mmu_page *page,
 				break;
 			if (pte_chain->parent_ptes[i] != parent_pte)
 				continue;
-			while (i + 1 < NR_PTE_CHAIN_ENTRIES) {
+			while (i + 1 < NR_PTE_CHAIN_ENTRIES
+				&& pte_chain->parent_ptes[i + 1]) {
 				pte_chain->parent_ptes[i]
 					= pte_chain->parent_ptes[i + 1];
 				++i;
 			}
 			pte_chain->parent_ptes[i] = NULL;
+			if (i == 0) {
+				hlist_del(&pte_chain->link);
+				kfree(pte_chain);
+				if (hlist_empty(&page->parent_ptes)) {
+					page->multimapped = 0;
+					page->parent_pte = NULL;
+				}
+			}
 			return;
 		}
 	BUG();
@@ -481,7 +490,30 @@ static struct kvm_mmu_page *kvm_mmu_get_page(struct kvm_vcpu *vcpu,
 static void kvm_mmu_page_unlink_children(struct kvm_vcpu *vcpu,
 					 struct kvm_mmu_page *page)
 {
-	BUG();
+	unsigned i;
+	u64 *pt;
+	u64 ent;
+
+	pt = __va(page->page_hpa);
+
+	if (page->role.level == PT_PAGE_TABLE_LEVEL) {
+		for (i = 0; i < PT64_ENT_PER_PAGE; ++i) {
+			if (pt[i] & PT_PRESENT_MASK)
+				rmap_remove(vcpu->kvm, &pt[i]);
+			pt[i] = 0;
+		}
+		return;
+	}
+
+	for (i = 0; i < PT64_ENT_PER_PAGE; ++i) {
+		ent = pt[i];
+
+		pt[i] = 0;
+		if (!(ent & PT_PRESENT_MASK))
+			continue;
+		ent &= PT64_BASE_ADDR_MASK;
+		mmu_page_remove_parent_pte(page_header(ent), &pt[i]);
+	}
 }
 
 static void kvm_mmu_put_page(struct kvm_vcpu *vcpu,
@@ -489,8 +521,7 @@ static void kvm_mmu_put_page(struct kvm_vcpu *vcpu,
 			     u64 *parent_pte)
 {
 	mmu_page_remove_parent_pte(page, parent_pte);
-	if (page->role.level > PT_PAGE_TABLE_LEVEL)
-		kvm_mmu_page_unlink_children(vcpu, page);
	//这里不再做限制, 如果是 PT_PAGE_TABLE_LEVEL, 就接触pte和 page之间的反向映射.
+	kvm_mmu_page_unlink_children(vcpu, page);
 	hlist_del(&page->hash_link);
 	list_del(&page->link);
 	list_add(&page->link, &vcpu->free_pages);
@@ -511,6 +542,7 @@ static void kvm_mmu_zap_page(struct kvm_vcpu *vcpu,
 					     struct kvm_pte_chain, link);
 			parent_pte = chain->parent_ptes[0];
 		}
+		BUG_ON(!parent_pte);
 		kvm_mmu_put_page(vcpu, page, parent_pte);
 		*parent_pte = 0;
 	}
@@ -530,6 +562,8 @@ static int kvm_mmu_unprotect_page(struct kvm_vcpu *vcpu, gfn_t gfn)
 	bucket = &vcpu->kvm->mmu_page_hash[index];
 	hlist_for_each_entry_safe(page, node, n, bucket, hash_link)
 		if (page->gfn == gfn && !page->role.metaphysical) {
+			pgprintk("%s: gfn %lx role %x\n", __FUNCTION__, gfn,
+				 page->role.word);
 			kvm_mmu_zap_page(vcpu, page);
 			r = 1;
 		}
-- 
2.42.0

```