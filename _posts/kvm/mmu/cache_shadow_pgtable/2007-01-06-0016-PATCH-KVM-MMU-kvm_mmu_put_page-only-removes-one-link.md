---
layout:     post
title:      "[PATCH 16/33] [PATCH] KVM: MMU: kvm_mmu_put_page() only removes one link to the page"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:47 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From cc4529efc7b730b596d9c7d5a917c00a357e92aa Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:47 -0800
Subject: [PATCH 16/33] [PATCH] KVM: MMU: kvm_mmu_put_page() only removes one
 link to the page

...  and so must not free it unconditionally.

Move the freeing to kvm_mmu_zap_page().

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c | 8 ++++----
 1 file changed, 4 insertions(+), 4 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 7e20dbf4f84c..d788866d5a6f 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -521,10 +521,6 @@ static void kvm_mmu_put_page(struct kvm_vcpu *vcpu,
 			     u64 *parent_pte)
 {
 	mmu_page_remove_parent_pte(page, parent_pte);
-	kvm_mmu_page_unlink_children(vcpu, page);
-	hlist_del(&page->hash_link);
-	list_del(&page->link);
-	list_add(&page->link, &vcpu->free_pages);
 }
 
 static void kvm_mmu_zap_page(struct kvm_vcpu *vcpu,
@@ -546,6 +542,10 @@ static void kvm_mmu_zap_page(struct kvm_vcpu *vcpu,
 		kvm_mmu_put_page(vcpu, page, parent_pte);
 		*parent_pte = 0;
 	}
+	kvm_mmu_page_unlink_children(vcpu, page);
+	hlist_del(&page->hash_link);
+	list_del(&page->link);
+	list_add(&page->link, &vcpu->free_pages);
 }
 
 static int kvm_mmu_unprotect_page(struct kvm_vcpu *vcpu, gfn_t gfn)
-- 
2.42.0

```