---
layout:     post
title:      "[PATCH 08/33] [PATCH] KVM: MMU: Make kvm_mmu_alloc_page() return a kvm_mmu_page pointer"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:42 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 25c0de2cc6c26cb99553c2444936a7951c120c09 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:42 -0800
Subject: [PATCH 08/33] [PATCH] KVM: MMU: Make kvm_mmu_alloc_page() return a
 kvm_mmu_page pointer

This allows further manipulation on the shadow page table.

> manipulation /məˌnɪpjəˈleɪʃən/: 操控变换

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c         | 24 +++++++++++-------------
 drivers/kvm/paging_tmpl.h |  6 ++++--
 2 files changed, 15 insertions(+), 15 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 1dcbbd511660..da4d7ddb9bdc 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -292,12 +292,13 @@ static int is_empty_shadow_page(hpa_t page_hpa)
 	return 1;
 }
 
-static hpa_t kvm_mmu_alloc_page(struct kvm_vcpu *vcpu, u64 *parent_pte)
+static struct kvm_mmu_page *kvm_mmu_alloc_page(struct kvm_vcpu *vcpu,
+					       u64 *parent_pte)
 {
 	struct kvm_mmu_page *page;
 
 	if (list_empty(&vcpu->free_pages))
-		return INVALID_PAGE;
+		return NULL;
 
 	page = list_entry(vcpu->free_pages.next, struct kvm_mmu_page, link);
 	list_del(&page->link);
@@ -306,7 +307,7 @@ static hpa_t kvm_mmu_alloc_page(struct kvm_vcpu *vcpu, u64 *parent_pte)
 	page->slot_bitmap = 0;
 	page->global = 1;
 	page->parent_pte = parent_pte;
-	return page->page_hpa;
+	return page;
 }
 
 static void page_header_update_slot(struct kvm *kvm, void *pte, gpa_t gpa)
@@ -402,19 +403,16 @@ static int nonpaging_map(struct kvm_vcpu *vcpu, gva_t v, hpa_t p)
 		}
 
 		if (table[index] == 0) {
-			hpa_t new_table = kvm_mmu_alloc_page(vcpu,
-							     &table[index]);
+			struct kvm_mmu_page *new_table;
 
-			if (!VALID_PAGE(new_table)) {
+			new_table = kvm_mmu_alloc_page(vcpu, &table[index]);
+			if (!new_table) {
 				pgprintk("nonpaging_map: ENOMEM\n");
 				return -ENOMEM;
 			}
 
      /*
       * pae level pgtable 已经被load了, 所以这里不会在fetch
       */
-			if (level == PT32E_ROOT_LEVEL)
-				table[index] = new_table | PT_PRESENT_MASK;
-			else
-				table[index] = new_table | PT_PRESENT_MASK |
-						PT_WRITABLE_MASK | PT_USER_MASK;
+			table[index] = new_table->page_hpa | PT_PRESENT_MASK
+				| PT_WRITABLE_MASK | PT_USER_MASK;
 		}
 		table_addr = table[index] & PT64_BASE_ADDR_MASK;
 	}
@@ -454,7 +452,7 @@ static void mmu_alloc_roots(struct kvm_vcpu *vcpu)
 		hpa_t root = vcpu->mmu.root_hpa;
 
 		ASSERT(!VALID_PAGE(root));
-		root = kvm_mmu_alloc_page(vcpu, NULL);
+		root = kvm_mmu_alloc_page(vcpu, NULL)->page_hpa;
 		vcpu->mmu.root_hpa = root;
 		return;
 	}
@@ -463,7 +461,7 @@ static void mmu_alloc_roots(struct kvm_vcpu *vcpu)
 		hpa_t root = vcpu->mmu.pae_root[i];
 
 		ASSERT(!VALID_PAGE(root));
-		root = kvm_mmu_alloc_page(vcpu, NULL);
+		root = kvm_mmu_alloc_page(vcpu, NULL)->page_hpa;
 		vcpu->mmu.pae_root[i] = root | PT_PRESENT_MASK;
 	}
 	vcpu->mmu.root_hpa = __pa(vcpu->mmu.pae_root);
diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index 7af49ae80e5a..11cac9ddf26a 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -179,6 +179,7 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 	for (; ; level--) {
 		u32 index = SHADOW_PT_INDEX(addr, level);
 		u64 *shadow_ent = ((u64 *)__va(shadow_addr)) + index;
+		struct kvm_mmu_page *shadow_page;
 		u64 shadow_pte;
 
 		if (is_present_pte(*shadow_ent) || is_io_pte(*shadow_ent)) {
@@ -204,9 +205,10 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 			return shadow_ent;
 		}
 
-		shadow_addr = kvm_mmu_alloc_page(vcpu, shadow_ent);
-		if (!VALID_PAGE(shadow_addr))
+		shadow_page = kvm_mmu_alloc_page(vcpu, shadow_ent);
+		if (!shadow_page)
 			return ERR_PTR(-ENOMEM);
+		shadow_addr = shadow_page->page_hpa;
 		shadow_pte = shadow_addr | PT_PRESENT_MASK | PT_ACCESSED_MASK
 			| PT_WRITABLE_MASK | PT_USER_MASK;
 		*shadow_ent = shadow_pte;
-- 
2.42.0

```