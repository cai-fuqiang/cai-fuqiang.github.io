---
layout:     post
title:      "[PATCH 08/13] KVM: MMU: mmu_parent_walk"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:36 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From ad8cfbe3fffdc09704f0808fde3934855620d545 Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:36 -0300
Subject: [PATCH 08/13] KVM: MMU: mmu_parent_walk

Introduce a function to walk all parents of a given page, invoking a handler.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c | 27 +++++++++++++++++++++++++++
 1 file changed, 27 insertions(+)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index e89af1df4fcd..b82abee78f17 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -147,6 +147,8 @@ struct kvm_shadow_walk {
 		     u64 addr, u64 *spte, int level);
 };
 
+typedef int (*mmu_parent_walk_fn) (struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp);
+
 static struct kmem_cache *pte_chain_cache;
 static struct kmem_cache *rmap_desc_cache;
 static struct kmem_cache *mmu_page_header_cache;
@@ -862,6 +864,31 @@ static void mmu_page_remove_parent_pte(struct kvm_mmu_page *sp,
 	BUG();
 }
 
+
+static void mmu_parent_walk(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp,
+			    mmu_parent_walk_fn fn)
+{
+	struct kvm_pte_chain *pte_chain;
+	struct hlist_node *node;
+	struct kvm_mmu_page *parent_sp;
+	int i;
+
+	if (!sp->multimapped && sp->parent_pte) {
+		parent_sp = page_header(__pa(sp->parent_pte));
+		fn(vcpu, parent_sp);
+		mmu_parent_walk(vcpu, parent_sp, fn);
+		return;
+	}
+	hlist_for_each_entry(pte_chain, node, &sp->parent_ptes, link)
+		for (i = 0; i < NR_PTE_CHAIN_ENTRIES; ++i) {
+			if (!pte_chain->parent_ptes[i])
+				break;
+			parent_sp = page_header(__pa(pte_chain->parent_ptes[i]));
+			fn(vcpu, parent_sp);
+			mmu_parent_walk(vcpu, parent_sp, fn);
+		}
+}
+
 static void nonpaging_prefetch_page(struct kvm_vcpu *vcpu,
 				    struct kvm_mmu_page *sp)
 {
-- 
2.42.0

```