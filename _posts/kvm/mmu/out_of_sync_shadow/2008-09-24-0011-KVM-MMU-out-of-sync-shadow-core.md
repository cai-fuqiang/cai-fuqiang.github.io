---
layout:     post
title:      "[PATCH 11/13] KVM: MMU: out of sync shadow core"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:39 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From 4731d4c7a07769cf2926c327177b97bb8c68cafc Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:39 -0300
Subject: [PATCH 11/13] KVM: MMU: out of sync shadow core

Allow guest pagetables to go out of sync.  Instead of emulating write
accesses to guest pagetables, or unshadowing them, we un-write-protect
the page table and allow the guest to modify it at will.  We rely on
invlpg executions to synchronize individual ptes, and will synchronize
the entire pagetable on tlb flushes.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c         | 210 ++++++++++++++++++++++++++++++++++---
 arch/x86/kvm/paging_tmpl.h |   2 +-
 arch/x86/kvm/x86.c         |   3 +
 include/asm-x86/kvm_host.h |   3 +
 include/linux/kvm_host.h   |   1 +
 5 files changed, 201 insertions(+), 18 deletions(-)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index 57c7580e7f98..d88659ae7778 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -147,6 +147,10 @@ struct kvm_shadow_walk {
 		     u64 addr, u64 *spte, int level);
 };
 
+struct kvm_unsync_walk {
+	int (*entry) (struct kvm_mmu_page *sp, struct kvm_unsync_walk *walk);
+};
+
 typedef int (*mmu_parent_walk_fn) (struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp);
 
 static struct kmem_cache *pte_chain_cache;
@@ -654,8 +658,6 @@ static void rmap_write_protect(struct kvm *kvm, u64 gfn)
 
 	if (write_protected)
 		kvm_flush_remote_tlbs(kvm);
-
-	account_shadowed(kvm, gfn);
 }
 
 static int kvm_unmap_rmapp(struct kvm *kvm, unsigned long *rmapp)
@@ -908,6 +910,41 @@ static void nonpaging_invlpg(struct kvm_vcpu *vcpu, gva_t gva)
 {
 }
 
+static int mmu_unsync_walk(struct kvm_mmu_page *sp,
+			   struct kvm_unsync_walk *walker)
+{
+	int i, ret;
+
+	if (!sp->unsync_children)
+		return 0;
+
+	for (i = 0; i < PT64_ENT_PER_PAGE; ++i) {
+		u64 ent = sp->spt[i];
+
+		if (is_shadow_present_pte(ent)) {
+			struct kvm_mmu_page *child;
+			child = page_header(ent & PT64_BASE_ADDR_MASK);
+
+			if (child->unsync_children) {
+				ret = mmu_unsync_walk(child, walker);
+				if (ret)
+					return ret;
+			}
+
+			if (child->unsync) {
+				ret = walker->entry(child, walker);
+				if (ret)
+					return ret;
+			}
+		}
+	}
+
+	if (i == PT64_ENT_PER_PAGE)
+		sp->unsync_children = 0;
+
+	return 0;
+}
+
 static struct kvm_mmu_page *kvm_mmu_lookup_page(struct kvm *kvm, gfn_t gfn)
 {
 	unsigned index;
@@ -928,6 +965,59 @@ static struct kvm_mmu_page *kvm_mmu_lookup_page(struct kvm *kvm, gfn_t gfn)
 	return NULL;
 }
 
+static void kvm_unlink_unsync_page(struct kvm *kvm, struct kvm_mmu_page *sp)
+{
+	WARN_ON(!sp->unsync);
+	sp->unsync = 0;
+	--kvm->stat.mmu_unsync;
+}
+
+static int kvm_mmu_zap_page(struct kvm *kvm, struct kvm_mmu_page *sp);
+
+static int kvm_sync_page(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
+{
+	if (sp->role.glevels != vcpu->arch.mmu.root_level) {
+		kvm_mmu_zap_page(vcpu->kvm, sp);
+		return 1;
+	}
+
+	rmap_write_protect(vcpu->kvm, sp->gfn);
+	if (vcpu->arch.mmu.sync_page(vcpu, sp)) {
+		kvm_mmu_zap_page(vcpu->kvm, sp);
+		return 1;
+	}
+
+	kvm_mmu_flush_tlb(vcpu);
+	kvm_unlink_unsync_page(vcpu->kvm, sp);
+	return 0;
+}
+
+struct sync_walker {
+	struct kvm_vcpu *vcpu;
+	struct kvm_unsync_walk walker;
+};
+
+static int mmu_sync_fn(struct kvm_mmu_page *sp, struct kvm_unsync_walk *walk)
+{
+	struct sync_walker *sync_walk = container_of(walk, struct sync_walker,
+						     walker);
+	struct kvm_vcpu *vcpu = sync_walk->vcpu;
+
+	kvm_sync_page(vcpu, sp);
+	return (need_resched() || spin_needbreak(&vcpu->kvm->mmu_lock));
+}
+
+static void mmu_sync_children(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
+{
+	struct sync_walker walker = {
+		.walker = { .entry = mmu_sync_fn, },
+		.vcpu = vcpu,
+	};
+
+	while (mmu_unsync_walk(sp, &walker.walker))
+		cond_resched_lock(&vcpu->kvm->mmu_lock);
+}
+
 static struct kvm_mmu_page *kvm_mmu_get_page(struct kvm_vcpu *vcpu,
 					     gfn_t gfn,
 					     gva_t gaddr,
@@ -941,7 +1031,7 @@ static struct kvm_mmu_page *kvm_mmu_get_page(struct kvm_vcpu *vcpu,
 	unsigned quadrant;
 	struct hlist_head *bucket;
 	struct kvm_mmu_page *sp;
-	struct hlist_node *node;
+	struct hlist_node *node, *tmp;
 
 	role.word = 0;
 	role.glevels = vcpu->arch.mmu.root_level;
@@ -957,8 +1047,18 @@ static struct kvm_mmu_page *kvm_mmu_get_page(struct kvm_vcpu *vcpu,
 		 gfn, role.word);
 	index = kvm_page_table_hashfn(gfn);
 	bucket = &vcpu->kvm->arch.mmu_page_hash[index];
-	hlist_for_each_entry(sp, node, bucket, hash_link)
-		if (sp->gfn == gfn && sp->role.word == role.word) {
+	hlist_for_each_entry_safe(sp, node, tmp, bucket, hash_link)
+		if (sp->gfn == gfn) {
+			if (sp->unsync)
+				if (kvm_sync_page(vcpu, sp))
+					continue;
+
+			if (sp->role.word != role.word)
+				continue;
+
+			if (sp->unsync_children)
+				set_bit(KVM_REQ_MMU_SYNC, &vcpu->requests);
+
 			mmu_page_add_parent_pte(vcpu, sp, parent_pte);
 			pgprintk("%s: found\n", __func__);
 			return sp;
@@ -971,8 +1071,10 @@ static struct kvm_mmu_page *kvm_mmu_get_page(struct kvm_vcpu *vcpu,
 	sp->gfn = gfn;
 	sp->role = role;
 	hlist_add_head(&sp->hash_link, bucket);
-	if (!metaphysical)
+	if (!metaphysical) {
 		rmap_write_protect(vcpu->kvm, gfn);
+		account_shadowed(vcpu->kvm, gfn);
+	}
 	if (shadow_trap_nonpresent_pte != shadow_notrap_nonpresent_pte)
 		vcpu->arch.mmu.prefetch_page(vcpu, sp);
 	else
@@ -1078,14 +1180,47 @@ static void kvm_mmu_unlink_parents(struct kvm *kvm, struct kvm_mmu_page *sp)
 	}
 }
 
+struct zap_walker {
+	struct kvm_unsync_walk walker;
+	struct kvm *kvm;
+	int zapped;
+};
+
+static int mmu_zap_fn(struct kvm_mmu_page *sp, struct kvm_unsync_walk *walk)
+{
+	struct zap_walker *zap_walk = container_of(walk, struct zap_walker,
+						     walker);
+	kvm_mmu_zap_page(zap_walk->kvm, sp);
+	zap_walk->zapped = 1;
+	return 0;
+}
+
+static int mmu_zap_unsync_children(struct kvm *kvm, struct kvm_mmu_page *sp)
+{
+	struct zap_walker walker = {
+		.walker = { .entry = mmu_zap_fn, },
+		.kvm = kvm,
+		.zapped = 0,
+	};
+
+	if (sp->role.level == PT_PAGE_TABLE_LEVEL)
+		return 0;
+	mmu_unsync_walk(sp, &walker.walker);
+	return walker.zapped;
+}
+
 static int kvm_mmu_zap_page(struct kvm *kvm, struct kvm_mmu_page *sp)
 {
+	int ret;
 	++kvm->stat.mmu_shadow_zapped;
+	ret = mmu_zap_unsync_children(kvm, sp);
 	kvm_mmu_page_unlink_children(kvm, sp);
 	kvm_mmu_unlink_parents(kvm, sp);
 	kvm_flush_remote_tlbs(kvm);
 	if (!sp->role.invalid && !sp->role.metaphysical)
 		unaccount_shadowed(kvm, sp->gfn);
+	if (sp->unsync)
+		kvm_unlink_unsync_page(kvm, sp);
 	if (!sp->root_count) {
 		hlist_del(&sp->hash_link);
 		kvm_mmu_free_page(kvm, sp);
@@ -1095,7 +1230,7 @@ static int kvm_mmu_zap_page(struct kvm *kvm, struct kvm_mmu_page *sp)
 		kvm_reload_remote_mmus(kvm);
 	}
 	kvm_mmu_reset_last_pte_updated(kvm);
-	return 0;
+	return ret;
 }
 
 /*
@@ -1201,10 +1336,58 @@ struct page *gva_to_page(struct kvm_vcpu *vcpu, gva_t gva)
 	return page;
 }
 
+static int unsync_walk_fn(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
+{
+	sp->unsync_children = 1;
+	return 1;
+}
+
+static int kvm_unsync_page(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
+{
+	unsigned index;
+	struct hlist_head *bucket;
+	struct kvm_mmu_page *s;
+	struct hlist_node *node, *n;
+
+	index = kvm_page_table_hashfn(sp->gfn);
+	bucket = &vcpu->kvm->arch.mmu_page_hash[index];
+	/* don't unsync if pagetable is shadowed with multiple roles */
+	hlist_for_each_entry_safe(s, node, n, bucket, hash_link) {
+		if (s->gfn != sp->gfn || s->role.metaphysical)
+			continue;
+		if (s->role.word != sp->role.word)
+			return 1;
+	}
+	mmu_parent_walk(vcpu, sp, unsync_walk_fn);
+	++vcpu->kvm->stat.mmu_unsync;
+	sp->unsync = 1;
+	mmu_convert_notrap(sp);
+	return 0;
+}
+
+static int mmu_need_write_protect(struct kvm_vcpu *vcpu, gfn_t gfn,
+				  bool can_unsync)
+{
+	struct kvm_mmu_page *shadow;
+
+	shadow = kvm_mmu_lookup_page(vcpu->kvm, gfn);
+	if (shadow) {
+		if (shadow->role.level != PT_PAGE_TABLE_LEVEL)
+			return 1;
+		if (shadow->unsync)
+			return 0;
+		if (can_unsync)
+			return kvm_unsync_page(vcpu, shadow);
+		return 1;
+	}
+	return 0;
+}
+
 static int set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 		    unsigned pte_access, int user_fault,
 		    int write_fault, int dirty, int largepage,
-		    gfn_t gfn, pfn_t pfn, bool speculative)
+		    gfn_t gfn, pfn_t pfn, bool speculative,
+		    bool can_unsync)
 {
 	u64 spte;
 	int ret = 0;
@@ -1231,7 +1414,6 @@ static int set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 
 	if ((pte_access & ACC_WRITE_MASK)
 	    || (write_fault && !is_write_protection(vcpu) && !user_fault)) {
-		struct kvm_mmu_page *shadow;
 
 		if (largepage && has_wrprotected_page(vcpu->kvm, gfn)) {
 			ret = 1;
@@ -1241,8 +1423,7 @@ static int set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 
 		spte |= PT_WRITABLE_MASK;
 
-		shadow = kvm_mmu_lookup_page(vcpu->kvm, gfn);
-		if (shadow) {
+		if (mmu_need_write_protect(vcpu, gfn, can_unsync)) {
 			pgprintk("%s: found shadow page for %lx, marking ro\n",
 				 __func__, gfn);
 			ret = 1;
@@ -1260,7 +1441,6 @@ set_pte:
 	return ret;
 }
 
-
 static void mmu_set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 			 unsigned pt_access, unsigned pte_access,
 			 int user_fault, int write_fault, int dirty,
@@ -1298,7 +1478,7 @@ static void mmu_set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 		}
 	}
 	if (set_spte(vcpu, shadow_pte, pte_access, user_fault, write_fault,
-		      dirty, largepage, gfn, pfn, speculative)) {
+		      dirty, largepage, gfn, pfn, speculative, true)) {
 		if (write_fault)
 			*ptwrite = 1;
 		kvm_x86_ops->tlb_flush(vcpu);
@@ -1518,10 +1698,6 @@ static void mmu_alloc_roots(struct kvm_vcpu *vcpu)
 	vcpu->arch.mmu.root_hpa = __pa(vcpu->arch.mmu.pae_root);
 }
 
-static void mmu_sync_children(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
-{
-}
-
 static void mmu_sync_roots(struct kvm_vcpu *vcpu)
 {
 	int i;
diff --git a/arch/x86/kvm/paging_tmpl.h b/arch/x86/kvm/paging_tmpl.h
index dc169e8148b1..613ec9aa674a 100644
--- a/arch/x86/kvm/paging_tmpl.h
+++ b/arch/x86/kvm/paging_tmpl.h
@@ -580,7 +580,7 @@ static int FNAME(sync_page)(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
 		pte_access = sp->role.access & FNAME(gpte_access)(vcpu, gpte);
 		set_spte(vcpu, &sp->spt[i], pte_access, 0, 0,
 			 is_dirty_pte(gpte), 0, gfn,
-			 spte_to_pfn(sp->spt[i]), true);
+			 spte_to_pfn(sp->spt[i]), true, false);
 	}
 
 	return !nr_present;
diff --git a/arch/x86/kvm/x86.c b/arch/x86/kvm/x86.c
index efee85ba07e5..1c5864ac0837 100644
--- a/arch/x86/kvm/x86.c
+++ b/arch/x86/kvm/x86.c
@@ -101,6 +101,7 @@ struct kvm_stats_debugfs_item debugfs_entries[] = {
 	{ "mmu_flooded", VM_STAT(mmu_flooded) },
 	{ "mmu_recycled", VM_STAT(mmu_recycled) },
 	{ "mmu_cache_miss", VM_STAT(mmu_cache_miss) },
+	{ "mmu_unsync", VM_STAT(mmu_unsync) },
 	{ "remote_tlb_flush", VM_STAT(remote_tlb_flush) },
 	{ "largepages", VM_STAT(lpages) },
 	{ NULL }
@@ -3120,6 +3121,8 @@ static int vcpu_enter_guest(struct kvm_vcpu *vcpu, struct kvm_run *kvm_run)
 	if (vcpu->requests) {
 		if (test_and_clear_bit(KVM_REQ_MIGRATE_TIMER, &vcpu->requests))
 			__kvm_migrate_timers(vcpu);
+		if (test_and_clear_bit(KVM_REQ_MMU_SYNC, &vcpu->requests))
+			kvm_mmu_sync_roots(vcpu);
 		if (test_and_clear_bit(KVM_REQ_TLB_FLUSH, &vcpu->requests))
 			kvm_x86_ops->tlb_flush(vcpu);
 		if (test_and_clear_bit(KVM_REQ_REPORT_TPR_ACCESS,
diff --git a/include/asm-x86/kvm_host.h b/include/asm-x86/kvm_host.h
index 8b935cc4c14b..7d36fcc02818 100644
--- a/include/asm-x86/kvm_host.h
+++ b/include/asm-x86/kvm_host.h
@@ -195,6 +195,8 @@ struct kvm_mmu_page {
 				    */
 	int multimapped;         /* More than one parent_pte? */
 	int root_count;          /* Currently serving as active root */
+	bool unsync;
+	bool unsync_children;
 	union {
 		u64 *parent_pte;               /* !multimapped */
 		struct hlist_head parent_ptes; /* multimapped, kvm_pte_chain */
@@ -371,6 +373,7 @@ struct kvm_vm_stat {
 	u32 mmu_flooded;
 	u32 mmu_recycled;
 	u32 mmu_cache_miss;
+	u32 mmu_unsync;
 	u32 remote_tlb_flush;
 	u32 lpages;
 };
diff --git a/include/linux/kvm_host.h b/include/linux/kvm_host.h
index 6252802c3cc0..73b7c52b9493 100644
--- a/include/linux/kvm_host.h
+++ b/include/linux/kvm_host.h
@@ -35,6 +35,7 @@
 #define KVM_REQ_TRIPLE_FAULT       4
 #define KVM_REQ_PENDING_TIMER      5
 #define KVM_REQ_UNHALT             6
+#define KVM_REQ_MMU_SYNC           7
 
 struct kvm_vcpu;
 extern struct kmem_cache *kvm_vcpu_cache;
-- 
2.42.0

```