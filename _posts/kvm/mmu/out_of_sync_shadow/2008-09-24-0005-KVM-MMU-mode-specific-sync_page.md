---
layout:     post
title:      "[PATCH 05/13] KVM: MMU: mode specific sync_page"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:33 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From e8bc217aef67d41d767ede6e7a7eb10f1d47c86c Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:33 -0300
Subject: [PATCH 05/13] KVM: MMU: mode specific sync_page

Examine guest pagetable and bring the shadow back in sync. Caller is responsible
for local TLB flush before re-entering guest mode.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c         | 10 +++++++
 arch/x86/kvm/paging_tmpl.h | 54 ++++++++++++++++++++++++++++++++++++++
 include/asm-x86/kvm_host.h |  2 ++
 3 files changed, 66 insertions(+)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index 731e6fe9cb07..90f01169c8f0 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -871,6 +871,12 @@ static void nonpaging_prefetch_page(struct kvm_vcpu *vcpu,
 		sp->spt[i] = shadow_trap_nonpresent_pte;
 }
 
+static int nonpaging_sync_page(struct kvm_vcpu *vcpu,
+			       struct kvm_mmu_page *sp)
+{
+	return 1;
+}
+
 static struct kvm_mmu_page *kvm_mmu_lookup_page(struct kvm *kvm, gfn_t gfn)
 {
 	unsigned index;
@@ -1547,6 +1553,7 @@ static int nonpaging_init_context(struct kvm_vcpu *vcpu)
 	context->gva_to_gpa = nonpaging_gva_to_gpa;
 	context->free = nonpaging_free;
 	context->prefetch_page = nonpaging_prefetch_page;
+	context->sync_page = nonpaging_sync_page;
 	context->root_level = 0;
 	context->shadow_root_level = PT32E_ROOT_LEVEL;
 	context->root_hpa = INVALID_PAGE;
@@ -1594,6 +1601,7 @@ static int paging64_init_context_common(struct kvm_vcpu *vcpu, int level)
 	context->page_fault = paging64_page_fault;
 	context->gva_to_gpa = paging64_gva_to_gpa;
 	context->prefetch_page = paging64_prefetch_page;
+	context->sync_page = paging64_sync_page;
 	context->free = paging_free;
 	context->root_level = level;
 	context->shadow_root_level = level;
@@ -1615,6 +1623,7 @@ static int paging32_init_context(struct kvm_vcpu *vcpu)
 	context->gva_to_gpa = paging32_gva_to_gpa;
 	context->free = paging_free;
 	context->prefetch_page = paging32_prefetch_page;
+	context->sync_page = paging32_sync_page;
 	context->root_level = PT32_ROOT_LEVEL;
 	context->shadow_root_level = PT32E_ROOT_LEVEL;
 	context->root_hpa = INVALID_PAGE;
@@ -1634,6 +1643,7 @@ static int init_kvm_tdp_mmu(struct kvm_vcpu *vcpu)
 	context->page_fault = tdp_page_fault;
 	context->free = nonpaging_free;
 	context->prefetch_page = nonpaging_prefetch_page;
+	context->sync_page = nonpaging_sync_page;
 	context->shadow_root_level = kvm_x86_ops->get_tdp_level();
 	context->root_hpa = INVALID_PAGE;
 
diff --git a/arch/x86/kvm/paging_tmpl.h b/arch/x86/kvm/paging_tmpl.h
index e9fbaa44d444..776fb6d2fd81 100644
--- a/arch/x86/kvm/paging_tmpl.h
+++ b/arch/x86/kvm/paging_tmpl.h
@@ -507,6 +507,60 @@ static void FNAME(prefetch_page)(struct kvm_vcpu *vcpu,
 	}
 }
 
+/*
+ * Using the cached information from sp->gfns is safe because:
+ * - The spte has a reference to the struct page, so the pfn for a given gfn
+ *   can't change unless all sptes pointing to it are nuked first.
+ * - Alias changes zap the entire shadow cache.
+ */
+static int FNAME(sync_page)(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
+{
+	int i, offset, nr_present;
+
+	offset = nr_present = 0;
+
+	if (PTTYPE == 32)
+		offset = sp->role.quadrant << PT64_LEVEL_BITS;
+
+	for (i = 0; i < PT64_ENT_PER_PAGE; i++) {
+		unsigned pte_access;
+		pt_element_t gpte;
+		gpa_t pte_gpa;
+		gfn_t gfn = sp->gfns[i];
+
+		if (!is_shadow_present_pte(sp->spt[i]))
+			continue;
+
+		pte_gpa = gfn_to_gpa(sp->gfn);
+		pte_gpa += (i+offset) * sizeof(pt_element_t);
+
+		if (kvm_read_guest_atomic(vcpu->kvm, pte_gpa, &gpte,
+					  sizeof(pt_element_t)))
+			return -EINVAL;
+
+		if (gpte_to_gfn(gpte) != gfn || !is_present_pte(gpte) ||
+		    !(gpte & PT_ACCESSED_MASK)) {
+			u64 nonpresent;
+
+			rmap_remove(vcpu->kvm, &sp->spt[i]);
+			if (is_present_pte(gpte))
+				nonpresent = shadow_trap_nonpresent_pte;
+			else
+				nonpresent = shadow_notrap_nonpresent_pte;
+			set_shadow_pte(&sp->spt[i], nonpresent);
+			continue;
+		}
+
+		nr_present++;
+		pte_access = sp->role.access & FNAME(gpte_access)(vcpu, gpte);
+		set_spte(vcpu, &sp->spt[i], pte_access, 0, 0,
+			 is_dirty_pte(gpte), 0, gfn,
+			 spte_to_pfn(sp->spt[i]), true);
+	}
+
+	return !nr_present;
+}
+
 #undef pt_element_t
 #undef guest_walker
 #undef shadow_walker
diff --git a/include/asm-x86/kvm_host.h b/include/asm-x86/kvm_host.h
index 805629c0f15f..8bad9bd9b37e 100644
--- a/include/asm-x86/kvm_host.h
+++ b/include/asm-x86/kvm_host.h
@@ -220,6 +220,8 @@ struct kvm_mmu {
 	gpa_t (*gva_to_gpa)(struct kvm_vcpu *vcpu, gva_t gva);
 	void (*prefetch_page)(struct kvm_vcpu *vcpu,
 			      struct kvm_mmu_page *page);
+	int (*sync_page)(struct kvm_vcpu *vcpu,
+			 struct kvm_mmu_page *sp);
 	hpa_t root_hpa;
 	int root_level;
 	int shadow_root_level;
-- 
2.42.0

```