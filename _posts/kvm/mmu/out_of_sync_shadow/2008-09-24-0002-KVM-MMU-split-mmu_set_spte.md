---
layout:     post
title:      "[PATCH 02/13] KVM: MMU: split mmu_set_spte"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:30 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From 1e73f9dd885957bf0c7bb5e63b350d5aeb06b726 Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:30 -0300
Subject: [PATCH 02/13] KVM: MMU: split mmu_set_spte

Split the spte entry creation code into a new set_spte function.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c | 101 +++++++++++++++++++++++++--------------------
 1 file changed, 57 insertions(+), 44 deletions(-)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index 5779a2323e23..9ad4cc553893 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -1148,44 +1148,13 @@ struct page *gva_to_page(struct kvm_vcpu *vcpu, gva_t gva)
 	return page;
 }
 
-static void mmu_set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
-			 unsigned pt_access, unsigned pte_access,
-			 int user_fault, int write_fault, int dirty,
-			 int *ptwrite, int largepage, gfn_t gfn,
-			 pfn_t pfn, bool speculative)
+static int set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
+		    unsigned pte_access, int user_fault,
+		    int write_fault, int dirty, int largepage,
+		    gfn_t gfn, pfn_t pfn, bool speculative)
 {
 	u64 spte;
-	int was_rmapped = 0;
-	int was_writeble = is_writeble_pte(*shadow_pte);
-
-	pgprintk("%s: spte %llx access %x write_fault %d"
-		 " user_fault %d gfn %lx\n",
-		 __func__, *shadow_pte, pt_access,
-		 write_fault, user_fault, gfn);
-
-	if (is_rmap_pte(*shadow_pte)) {
-		/*
-		 * If we overwrite a PTE page pointer with a 2MB PMD, unlink
-		 * the parent of the now unreachable PTE.
-		 */
-		if (largepage && !is_large_pte(*shadow_pte)) {
-			struct kvm_mmu_page *child;
-			u64 pte = *shadow_pte;
-
-			child = page_header(pte & PT64_BASE_ADDR_MASK);
-			mmu_page_remove_parent_pte(child, shadow_pte);
-		} else if (pfn != spte_to_pfn(*shadow_pte)) {
-			pgprintk("hfn old %lx new %lx\n",
-				 spte_to_pfn(*shadow_pte), pfn);
-			rmap_remove(vcpu->kvm, shadow_pte);
-		} else {
-			if (largepage)
-				was_rmapped = is_large_pte(*shadow_pte);
-			else
-				was_rmapped = 1;
-		}
-	}
-
+	int ret = 0;
 	/*
 	 * We don't set the accessed bit, since we sometimes want to see
 	 * whether the guest actually used the pte (in order to detect
@@ -1218,26 +1187,70 @@ static void mmu_set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 		   (largepage && has_wrprotected_page(vcpu->kvm, gfn))) {
 			pgprintk("%s: found shadow page for %lx, marking ro\n",
 				 __func__, gfn);
+			ret = 1;
 			pte_access &= ~ACC_WRITE_MASK;
 			if (is_writeble_pte(spte)) {
 				spte &= ~PT_WRITABLE_MASK;
 				kvm_x86_ops->tlb_flush(vcpu);
 			}
-			if (write_fault)
-				*ptwrite = 1;
 		}
 	}
 
 	if (pte_access & ACC_WRITE_MASK)
 		mark_page_dirty(vcpu->kvm, gfn);
 
-	pgprintk("%s: setting spte %llx\n", __func__, spte);
-	pgprintk("instantiating %s PTE (%s) at %ld (%llx) addr %p\n",
-		 (spte&PT_PAGE_SIZE_MASK)? "2MB" : "4kB",
-		 (spte&PT_WRITABLE_MASK)?"RW":"R", gfn, spte, shadow_pte);
 	set_shadow_pte(shadow_pte, spte);
-	if (!was_rmapped && (spte & PT_PAGE_SIZE_MASK)
-	    && (spte & PT_PRESENT_MASK))
+	return ret;
+}
+
+
+static void mmu_set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
+			 unsigned pt_access, unsigned pte_access,
+			 int user_fault, int write_fault, int dirty,
+			 int *ptwrite, int largepage, gfn_t gfn,
+			 pfn_t pfn, bool speculative)
+{
+	int was_rmapped = 0;
+	int was_writeble = is_writeble_pte(*shadow_pte);
+
+	pgprintk("%s: spte %llx access %x write_fault %d"
+		 " user_fault %d gfn %lx\n",
+		 __func__, *shadow_pte, pt_access,
+		 write_fault, user_fault, gfn);
+
+	if (is_rmap_pte(*shadow_pte)) {
+		/*
+		 * If we overwrite a PTE page pointer with a 2MB PMD, unlink
+		 * the parent of the now unreachable PTE.
+		 */
+		if (largepage && !is_large_pte(*shadow_pte)) {
+			struct kvm_mmu_page *child;
+			u64 pte = *shadow_pte;
+
+			child = page_header(pte & PT64_BASE_ADDR_MASK);
+			mmu_page_remove_parent_pte(child, shadow_pte);
+		} else if (pfn != spte_to_pfn(*shadow_pte)) {
+			pgprintk("hfn old %lx new %lx\n",
+				 spte_to_pfn(*shadow_pte), pfn);
+			rmap_remove(vcpu->kvm, shadow_pte);
+		} else {
+			if (largepage)
+				was_rmapped = is_large_pte(*shadow_pte);
+			else
+				was_rmapped = 1;
+		}
+	}
+	if (set_spte(vcpu, shadow_pte, pte_access, user_fault, write_fault,
+		      dirty, largepage, gfn, pfn, speculative))
+		if (write_fault)
+			*ptwrite = 1;
+
+	pgprintk("%s: setting spte %llx\n", __func__, *shadow_pte);
+	pgprintk("instantiating %s PTE (%s) at %ld (%llx) addr %p\n",
+		 is_large_pte(*shadow_pte)? "2MB" : "4kB",
+		 is_present_pte(*shadow_pte)?"RW":"R", gfn,
+		 *shadow_pte, shadow_pte);
+	if (!was_rmapped && is_large_pte(*shadow_pte))
 		++vcpu->kvm->stat.lpages;
 
 	page_header_update_slot(vcpu->kvm, shadow_pte, gfn);
-- 
2.42.0

```