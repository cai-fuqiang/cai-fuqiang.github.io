---
layout:     post
title:      "[PATCH 25/33] [PATCH] KVM: MMU: Never free a shadow page actively serving as a root"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:51 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 3bb65a22a4502067f8cd3cb4c923ffa70be62091 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:51 -0800
Subject: [PATCH 25/33] [PATCH] KVM: MMU: Never free a shadow page actively
 serving as a root

We always need cr3 to point to something valid, so if we detect that we're
freeing a root page, simply push it back to the top of the active list.

> 我们总是需要cr3来指向有效的东西，所以如果我们检测到我们正在释放一个根页面，
> 只需将其推回到活动列表的顶部。

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm.h |  1 +
 drivers/kvm/mmu.c | 20 ++++++++++++++++++--
 2 files changed, 19 insertions(+), 2 deletions(-)

diff --git a/drivers/kvm/kvm.h b/drivers/kvm/kvm.h
index 201b2735ca91..b24a86e1f434 100644
--- a/drivers/kvm/kvm.h
+++ b/drivers/kvm/kvm.h
@@ -134,6 +134,7 @@ struct kvm_mmu_page {
 				    */
 	int global;              /* Set if all ptes in this page are global */
 	int multimapped;         /* More than one parent_pte? */
+	int root_count;          /* Currently serving as active root */
 	union {
 		u64 *parent_pte;               /* !multimapped */
 		struct hlist_head parent_ptes; /* multimapped, kvm_pte_chain */
diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 0e44aca9eee7..f16321498093 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -550,8 +550,13 @@ static void kvm_mmu_zap_page(struct kvm_vcpu *vcpu,
 		*parent_pte = 0;
 	}
 	kvm_mmu_page_unlink_children(vcpu, page);
-	hlist_del(&page->hash_link);
-	kvm_mmu_free_page(vcpu, page->page_hpa);
+	if (!page->root_count) {
+		hlist_del(&page->hash_link);
+		kvm_mmu_free_page(vcpu, page->page_hpa);
+	} else {
+		list_del(&page->link);
+		list_add(&page->link, &vcpu->kvm->active_mmu_pages);
+	}
 }
 
 static int kvm_mmu_unprotect_page(struct kvm_vcpu *vcpu, gfn_t gfn)
@@ -667,12 +672,15 @@ static int nonpaging_map(struct kvm_vcpu *vcpu, gva_t v, hpa_t p)
 static void mmu_free_roots(struct kvm_vcpu *vcpu)
 {
 	int i;
+	struct kvm_mmu_page *page;
 
 #ifdef CONFIG_X86_64
 	if (vcpu->mmu.shadow_root_level == PT64_ROOT_LEVEL) {
 		hpa_t root = vcpu->mmu.root_hpa;
 
 		ASSERT(VALID_PAGE(root));
+		page = page_header(root);
+		--page->root_count;
 		vcpu->mmu.root_hpa = INVALID_PAGE;
 		return;
 	}
@@ -682,6 +690,8 @@ static void mmu_free_roots(struct kvm_vcpu *vcpu)
 
 		ASSERT(VALID_PAGE(root));
 		root &= PT64_BASE_ADDR_MASK;
+		page = page_header(root);
+		--page->root_count;
 		vcpu->mmu.pae_root[i] = INVALID_PAGE;
 	}
 	vcpu->mmu.root_hpa = INVALID_PAGE;
@@ -691,6 +701,8 @@ static void mmu_alloc_roots(struct kvm_vcpu *vcpu)
 {
 	int i;
 	gfn_t root_gfn;
+	struct kvm_mmu_page *page;
+
 	root_gfn = vcpu->cr3 >> PAGE_SHIFT;
 
 #ifdef CONFIG_X86_64
@@ -700,6 +712,8 @@ static void mmu_alloc_roots(struct kvm_vcpu *vcpu)
 		ASSERT(!VALID_PAGE(root));
 		root = kvm_mmu_get_page(vcpu, root_gfn, 0,
 					PT64_ROOT_LEVEL, 0, NULL)->page_hpa;
+		page = page_header(root);
+		++page->root_count;
 		vcpu->mmu.root_hpa = root;
 		return;
 	}
@@ -715,6 +729,8 @@ static void mmu_alloc_roots(struct kvm_vcpu *vcpu)
 		root = kvm_mmu_get_page(vcpu, root_gfn, i << 30,
 					PT32_ROOT_LEVEL, !is_paging(vcpu),
 					NULL)->page_hpa;
+		page = page_header(root);
+		++page->root_count;
 		vcpu->mmu.pae_root[i] = root | PT_PRESENT_MASK;
 	}
 	vcpu->mmu.root_hpa = __pa(vcpu->mmu.pae_root);
-- 
2.42.0

```