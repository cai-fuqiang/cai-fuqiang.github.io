---
layout:     post
title:      "[PATCH 21/33] [PATCH] KVM: MMU: move is_empty_shadow_page() above kvm_mmu_free_page()"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:49 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 260746c03dcb2e5089f95b60cb786aaf405ced63 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:49 -0800
Subject: [PATCH 21/33] [PATCH] KVM: MMU: move is_empty_shadow_page() above
 kvm_mmu_free_page()

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c | 20 ++++++++++----------
 1 file changed, 10 insertions(+), 10 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 50b1432dceee..c55ce7d1509e 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -303,16 +303,6 @@ static void rmap_write_protect(struct kvm *kvm, u64 gfn)
 	}
 }
 
-static void kvm_mmu_free_page(struct kvm_vcpu *vcpu, hpa_t page_hpa)
-{
-	struct kvm_mmu_page *page_head = page_header(page_hpa);
-
-	list_del(&page_head->link);
-	page_head->page_hpa = page_hpa;
-	list_add(&page_head->link, &vcpu->free_pages);
-	++vcpu->kvm->n_free_mmu_pages;
-}
-
 static int is_empty_shadow_page(hpa_t page_hpa)
 {
 	u32 *pos;
@@ -324,6 +314,16 @@ static int is_empty_shadow_page(hpa_t page_hpa)
 	return 1;
 }
 
+static void kvm_mmu_free_page(struct kvm_vcpu *vcpu, hpa_t page_hpa)
+{
+	struct kvm_mmu_page *page_head = page_header(page_hpa);
+
+	list_del(&page_head->link);
+	page_head->page_hpa = page_hpa;
+	list_add(&page_head->link, &vcpu->free_pages);
+	++vcpu->kvm->n_free_mmu_pages;
+}
+
 static unsigned kvm_page_table_hashfn(gfn_t gfn)
 {
 	return gfn;
-- 
2.42.0

```