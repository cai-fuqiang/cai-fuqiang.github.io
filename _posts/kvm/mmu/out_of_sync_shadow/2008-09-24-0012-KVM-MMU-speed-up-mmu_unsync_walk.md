---
layout:     post
title:      "[PATCH 12/13] KVM: MMU: speed up mmu_unsync_walk"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:40 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From 0074ff63ebc195701062ca46e0d82fcea0fa3a0a Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:40 -0300
Subject: [PATCH 12/13] KVM: MMU: speed up mmu_unsync_walk

Cache the unsynced children information in a per-page bitmap.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c         | 72 +++++++++++++++++++++++++++++++-------
 include/asm-x86/kvm_host.h |  1 +
 2 files changed, 61 insertions(+), 12 deletions(-)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index d88659ae7778..cb391d629af2 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -891,6 +891,52 @@ static void mmu_parent_walk(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp,
 		}
 }
 
+static void kvm_mmu_update_unsync_bitmap(u64 *spte)
+{
+	unsigned int index;
+	struct kvm_mmu_page *sp = page_header(__pa(spte));
+
+	index = spte - sp->spt;
+	__set_bit(index, sp->unsync_child_bitmap);
+	sp->unsync_children = 1;
+}
+
+static void kvm_mmu_update_parents_unsync(struct kvm_mmu_page *sp)
+{
+	struct kvm_pte_chain *pte_chain;
+	struct hlist_node *node;
+	int i;
+
+	if (!sp->parent_pte)
+		return;
+
+	if (!sp->multimapped) {
+		kvm_mmu_update_unsync_bitmap(sp->parent_pte);
+		return;
+	}
+
+	hlist_for_each_entry(pte_chain, node, &sp->parent_ptes, link)
+		for (i = 0; i < NR_PTE_CHAIN_ENTRIES; ++i) {
+			if (!pte_chain->parent_ptes[i])
+				break;
+			kvm_mmu_update_unsync_bitmap(pte_chain->parent_ptes[i]);
+		}
+}
+
+static int unsync_walk_fn(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
+{
+	sp->unsync_children = 1;
+	kvm_mmu_update_parents_unsync(sp);
+	return 1;
+}
+
+static void kvm_mmu_mark_parents_unsync(struct kvm_vcpu *vcpu,
+					struct kvm_mmu_page *sp)
+{
+	mmu_parent_walk(vcpu, sp, unsync_walk_fn);
+	kvm_mmu_update_parents_unsync(sp);
+}
+
 static void nonpaging_prefetch_page(struct kvm_vcpu *vcpu,
 				    struct kvm_mmu_page *sp)
 {
@@ -910,6 +956,11 @@ static void nonpaging_invlpg(struct kvm_vcpu *vcpu, gva_t gva)
 {
 }
 
+#define for_each_unsync_children(bitmap, idx)		\
+	for (idx = find_first_bit(bitmap, 512);		\
+	     idx < 512;					\
+	     idx = find_next_bit(bitmap, 512, idx+1))
+
 static int mmu_unsync_walk(struct kvm_mmu_page *sp,
 			   struct kvm_unsync_walk *walker)
 {
@@ -918,7 +969,7 @@ static int mmu_unsync_walk(struct kvm_mmu_page *sp,
 	if (!sp->unsync_children)
 		return 0;
 
-	for (i = 0; i < PT64_ENT_PER_PAGE; ++i) {
+	for_each_unsync_children(sp->unsync_child_bitmap, i) {
 		u64 ent = sp->spt[i];
 
 		if (is_shadow_present_pte(ent)) {
@@ -929,17 +980,19 @@ static int mmu_unsync_walk(struct kvm_mmu_page *sp,
 				ret = mmu_unsync_walk(child, walker);
 				if (ret)
 					return ret;
+				__clear_bit(i, sp->unsync_child_bitmap);
 			}
 
 			if (child->unsync) {
 				ret = walker->entry(child, walker);
+				__clear_bit(i, sp->unsync_child_bitmap);
 				if (ret)
 					return ret;
 			}
 		}
 	}
 
-	if (i == PT64_ENT_PER_PAGE)
+	if (find_first_bit(sp->unsync_child_bitmap, 512) == 512)
 		sp->unsync_children = 0;
 
 	return 0;
@@ -1056,10 +1109,11 @@ static struct kvm_mmu_page *kvm_mmu_get_page(struct kvm_vcpu *vcpu,
 			if (sp->role.word != role.word)
 				continue;
 
-			if (sp->unsync_children)
-				set_bit(KVM_REQ_MMU_SYNC, &vcpu->requests);
-
 			mmu_page_add_parent_pte(vcpu, sp, parent_pte);
+			if (sp->unsync_children) {
+				set_bit(KVM_REQ_MMU_SYNC, &vcpu->requests);
+				kvm_mmu_mark_parents_unsync(vcpu, sp);
+			}
 			pgprintk("%s: found\n", __func__);
 			return sp;
 		}
@@ -1336,12 +1390,6 @@ struct page *gva_to_page(struct kvm_vcpu *vcpu, gva_t gva)
 	return page;
 }
 
-static int unsync_walk_fn(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
-{
-	sp->unsync_children = 1;
-	return 1;
-}
-
 static int kvm_unsync_page(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
 {
 	unsigned index;
@@ -1358,7 +1406,7 @@ static int kvm_unsync_page(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
 		if (s->role.word != sp->role.word)
 			return 1;
 	}
-	mmu_parent_walk(vcpu, sp, unsync_walk_fn);
+	kvm_mmu_mark_parents_unsync(vcpu, sp);
 	++vcpu->kvm->stat.mmu_unsync;
 	sp->unsync = 1;
 	mmu_convert_notrap(sp);
diff --git a/include/asm-x86/kvm_host.h b/include/asm-x86/kvm_host.h
index 7d36fcc02818..0992d721c5f7 100644
--- a/include/asm-x86/kvm_host.h
+++ b/include/asm-x86/kvm_host.h
@@ -201,6 +201,7 @@ struct kvm_mmu_page {
 		u64 *parent_pte;               /* !multimapped */
 		struct hlist_head parent_ptes; /* multimapped, kvm_pte_chain */
 	};
+	DECLARE_BITMAP(unsync_child_bitmap, 512);
 };
 
 struct kvm_pv_mmu_op_buffer {
-- 
2.42.0

```