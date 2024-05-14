---
layout: post
title:  "[PATCH] KVM: Allow not-present guest page faults to bypass kvm"
author: fuqiang
date:   2007-09-17 18:58:32 +0200
categories: [kvm]
tags: [kvm]
---

```diff
From c7addb902054195b995114df154e061c7d604f69 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Sun, 16 Sep 2007 18:58:32 +0200
Subject: [PATCH] KVM: Allow not-present guest page faults to bypass kvm

There are two classes of page faults trapped by kvm:
 - host page faults, where the fault is needed to allow kvm to install
   the shadow pte or update the guest accessed and dirty bits
 - guest page faults, where the guest has faulted and kvm simply injects
   the fault back into the guest to handle

The second class, guest page faults, is pure overhead.  We can eliminate
some of it on vmx using the following evil trick:
 - when we set up a shadow page table entry, if the corresponding guest pte
   is not present, set up the shadow pte as not present
 - if the guest pte _is_ present, mark the shadow pte as present but also
   set one of the reserved bits in the shadow pte
 - tell the vmx hardware not to trap faults which have the present bit clear

With this, normal page-not-present faults go directly to the guest,
bypassing kvm entirely.

Unfortunately, this trick only works on Intel hardware, as AMD lacks a
way to discriminate among page faults based on error code.  It is also
a little risky since it uses reserved bits which might become unreserved
in the future, so a module parameter is provided to disable it.

> mail list
>
> https://lore.kernel.org/all/1198421495-31481-10-git-send-email-avi@qumranet.com/

Signed-off-by: Avi Kivity <avi@qumranet.com>
---
 drivers/kvm/kvm.h         |  3 ++
 drivers/kvm/kvm_main.c    |  4 +-
 drivers/kvm/mmu.c         | 89 ++++++++++++++++++++++++++++++---------
 drivers/kvm/paging_tmpl.h | 52 +++++++++++++++++------
 drivers/kvm/vmx.c         | 11 ++++-
 5 files changed, 122 insertions(+), 37 deletions(-)

diff --git a/drivers/kvm/kvm.h b/drivers/kvm/kvm.h
index e885b190b798..7de948e9e64e 100644
--- a/drivers/kvm/kvm.h
+++ b/drivers/kvm/kvm.h
@@ -150,6 +150,8 @@ struct kvm_mmu {
 	int (*page_fault)(struct kvm_vcpu *vcpu, gva_t gva, u32 err);
 	void (*free)(struct kvm_vcpu *vcpu);
 	gpa_t (*gva_to_gpa)(struct kvm_vcpu *vcpu, gva_t gva);
+	void (*prefetch_page)(struct kvm_vcpu *vcpu,
+			      struct kvm_mmu_page *page);
 	hpa_t root_hpa;
 	int root_level;
 	int shadow_root_level;
@@ -536,6 +538,7 @@ void kvm_mmu_module_exit(void);
 void kvm_mmu_destroy(struct kvm_vcpu *vcpu);
 int kvm_mmu_create(struct kvm_vcpu *vcpu);
 int kvm_mmu_setup(struct kvm_vcpu *vcpu);
+void kvm_mmu_set_nonpresent_ptes(u64 trap_pte, u64 notrap_pte);
 
 int kvm_mmu_reset_context(struct kvm_vcpu *vcpu);
 void kvm_mmu_slot_remove_write_access(struct kvm *kvm, int slot);
diff --git a/drivers/kvm/kvm_main.c b/drivers/kvm/kvm_main.c
index 710483669f34..82cc7ae0fc83 100644
--- a/drivers/kvm/kvm_main.c
+++ b/drivers/kvm/kvm_main.c
@@ -3501,7 +3501,9 @@ int kvm_init_x86(struct kvm_x86_ops *ops, unsigned int vcpu_size,
 	kvm_preempt_ops.sched_in = kvm_sched_in;
 	kvm_preempt_ops.sched_out = kvm_sched_out;
 
-	return r;
+	kvm_mmu_set_nonpresent_ptes(0ull, 0ull);
+
+	return 0;
 
 out_free:
 	kmem_cache_destroy(kvm_vcpu_cache);
diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index feb5ac986c5d..069ce83f018e 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -156,6 +156,16 @@ static struct kmem_cache *pte_chain_cache;
 static struct kmem_cache *rmap_desc_cache;
 static struct kmem_cache *mmu_page_header_cache;
 
+static u64 __read_mostly shadow_trap_nonpresent_pte;
+static u64 __read_mostly shadow_notrap_nonpresent_pte;
+
+void kvm_mmu_set_nonpresent_ptes(u64 trap_pte, u64 notrap_pte)
+{
+	shadow_trap_nonpresent_pte = trap_pte;
+	shadow_notrap_nonpresent_pte = notrap_pte;
+}
+EXPORT_SYMBOL_GPL(kvm_mmu_set_nonpresent_ptes);
+
 static int is_write_protection(struct kvm_vcpu *vcpu)
 {
 	return vcpu->cr0 & X86_CR0_WP;
@@ -176,6 +186,13 @@ static int is_present_pte(unsigned long pte)
 	return pte & PT_PRESENT_MASK;
 }
 
+static int is_shadow_present_pte(u64 pte)
+{
+	pte &= ~PT_SHADOW_IO_MARK;
+	return pte != shadow_trap_nonpresent_pte
+		&& pte != shadow_notrap_nonpresent_pte;
+}
+
 static int is_writeble_pte(unsigned long pte)
 {
 	return pte & PT_WRITABLE_MASK;
@@ -450,7 +467,7 @@ static int is_empty_shadow_page(u64 *spt)
 	u64 *end;
 
 	for (pos = spt, end = pos + PAGE_SIZE / sizeof(u64); pos != end; pos++)
-		if (*pos != 0) {
+		if ((*pos & ~PT_SHADOW_IO_MARK) != shadow_trap_nonpresent_pte) {
 			printk(KERN_ERR "%s: %p %llx\n", __FUNCTION__,
 			       pos, *pos);
 			return 0;
@@ -632,6 +649,7 @@ static struct kvm_mmu_page *kvm_mmu_get_page(struct kvm_vcpu *vcpu,
 	page->gfn = gfn;
 	page->role = role;
 	hlist_add_head(&page->hash_link, bucket);
+	vcpu->mmu.prefetch_page(vcpu, page);
 	if (!metaphysical)
 		rmap_write_protect(vcpu, gfn);
 	return page;
@@ -648,9 +666,9 @@ static void kvm_mmu_page_unlink_children(struct kvm *kvm,
 
 	if (page->role.level == PT_PAGE_TABLE_LEVEL) {
 		for (i = 0; i < PT64_ENT_PER_PAGE; ++i) {
-			if (pt[i] & PT_PRESENT_MASK)
+			if (is_shadow_present_pte(pt[i]))
 				rmap_remove(&pt[i]);
-			pt[i] = 0;
+			pt[i] = shadow_trap_nonpresent_pte;
 		}
 		kvm_flush_remote_tlbs(kvm);
 		return;
@@ -659,8 +677,8 @@ static void kvm_mmu_page_unlink_children(struct kvm *kvm,
 	for (i = 0; i < PT64_ENT_PER_PAGE; ++i) {
 		ent = pt[i];
 
-		pt[i] = 0;
-		if (!(ent & PT_PRESENT_MASK))
+		pt[i] = shadow_trap_nonpresent_pte;
+		if (!is_shadow_present_pte(ent))
 			continue;
 		ent &= PT64_BASE_ADDR_MASK;
 		mmu_page_remove_parent_pte(page_header(ent), &pt[i]);
@@ -691,7 +709,7 @@ static void kvm_mmu_zap_page(struct kvm *kvm,
 		}
 		BUG_ON(!parent_pte);
 		kvm_mmu_put_page(page, parent_pte);
-		set_shadow_pte(parent_pte, 0);
+		set_shadow_pte(parent_pte, shadow_trap_nonpresent_pte);
 	}
 	kvm_mmu_page_unlink_children(kvm, page);
 	if (!page->root_count) {
@@ -798,7 +816,7 @@ static int nonpaging_map(struct kvm_vcpu *vcpu, gva_t v, hpa_t p)
 
 		if (level == 1) {
 			pte = table[index];
-			if (is_present_pte(pte) && is_writeble_pte(pte))
+			if (is_shadow_present_pte(pte) && is_writeble_pte(pte))
 				return 0;
 			mark_page_dirty(vcpu->kvm, v >> PAGE_SHIFT);
 			page_header_update_slot(vcpu->kvm, table, v);
@@ -808,7 +826,7 @@ static int nonpaging_map(struct kvm_vcpu *vcpu, gva_t v, hpa_t p)
 			return 0;
 		}
 
-		if (table[index] == 0) {
+		if (table[index] == shadow_trap_nonpresent_pte) {
 			struct kvm_mmu_page *new_table;
 			gfn_t pseudo_gfn;
 
@@ -829,6 +847,15 @@ static int nonpaging_map(struct kvm_vcpu *vcpu, gva_t v, hpa_t p)
 	}
 }
 
+static void nonpaging_prefetch_page(struct kvm_vcpu *vcpu,
+				    struct kvm_mmu_page *sp)
+{
+	int i;
+
+	for (i = 0; i < PT64_ENT_PER_PAGE; ++i)
+		sp->spt[i] = shadow_trap_nonpresent_pte;
+}
+
 static void mmu_free_roots(struct kvm_vcpu *vcpu)
 {
 	int i;
@@ -943,6 +970,7 @@ static int nonpaging_init_context(struct kvm_vcpu *vcpu)
 	context->page_fault = nonpaging_page_fault;
 	context->gva_to_gpa = nonpaging_gva_to_gpa;
 	context->free = nonpaging_free;
+	context->prefetch_page = nonpaging_prefetch_page;
 	context->root_level = 0;
 	context->shadow_root_level = PT32E_ROOT_LEVEL;
 	context->root_hpa = INVALID_PAGE;
@@ -989,6 +1017,7 @@ static int paging64_init_context_common(struct kvm_vcpu *vcpu, int level)
 	context->new_cr3 = paging_new_cr3;
 	context->page_fault = paging64_page_fault;
 	context->gva_to_gpa = paging64_gva_to_gpa;
+	context->prefetch_page = paging64_prefetch_page;
 	context->free = paging_free;
 	context->root_level = level;
 	context->shadow_root_level = level;
@@ -1009,6 +1038,7 @@ static int paging32_init_context(struct kvm_vcpu *vcpu)
 	context->page_fault = paging32_page_fault;
 	context->gva_to_gpa = paging32_gva_to_gpa;
 	context->free = paging_free;
+	context->prefetch_page = paging32_prefetch_page;
 	context->root_level = PT32_ROOT_LEVEL;
 	context->shadow_root_level = PT32E_ROOT_LEVEL;
 	context->root_hpa = INVALID_PAGE;
@@ -1081,7 +1111,7 @@ static void mmu_pte_write_zap_pte(struct kvm_vcpu *vcpu,
 	struct kvm_mmu_page *child;
 
 	pte = *spte;
-	if (is_present_pte(pte)) {
+	if (is_shadow_present_pte(pte)) {
 		if (page->role.level == PT_PAGE_TABLE_LEVEL)
 			rmap_remove(spte);
 		else {
@@ -1089,22 +1119,25 @@ static void mmu_pte_write_zap_pte(struct kvm_vcpu *vcpu,
 			mmu_page_remove_parent_pte(child, spte);
 		}
 	}
-	set_shadow_pte(spte, 0);
+	set_shadow_pte(spte, shadow_trap_nonpresent_pte);
 	kvm_flush_remote_tlbs(vcpu->kvm);
 }
 
 static void mmu_pte_write_new_pte(struct kvm_vcpu *vcpu,
 				  struct kvm_mmu_page *page,
 				  u64 *spte,
-				  const void *new, int bytes)
+				  const void *new, int bytes,
+				  int offset_in_pte)
 {
 	if (page->role.level != PT_PAGE_TABLE_LEVEL)
 		return;
 
 	if (page->role.glevels == PT32_ROOT_LEVEL)
-		paging32_update_pte(vcpu, page, spte, new, bytes);
+		paging32_update_pte(vcpu, page, spte, new, bytes,
+				    offset_in_pte);
 	else
-		paging64_update_pte(vcpu, page, spte, new, bytes);
+		paging64_update_pte(vcpu, page, spte, new, bytes,
+				    offset_in_pte);
 }
 
 void kvm_mmu_pte_write(struct kvm_vcpu *vcpu, gpa_t gpa,
@@ -1126,6 +1159,7 @@ void kvm_mmu_pte_write(struct kvm_vcpu *vcpu, gpa_t gpa,
 	int npte;
 
 	pgprintk("%s: gpa %llx bytes %d\n", __FUNCTION__, gpa, bytes);
+	kvm_mmu_audit(vcpu, "pre pte write");
 	if (gfn == vcpu->last_pt_write_gfn) {
 		++vcpu->last_pt_write_count;
 		if (vcpu->last_pt_write_count >= 3)
@@ -1181,10 +1215,12 @@ void kvm_mmu_pte_write(struct kvm_vcpu *vcpu, gpa_t gpa,
 		spte = &page->spt[page_offset / sizeof(*spte)];
 		while (npte--) {
 			mmu_pte_write_zap_pte(vcpu, page, spte);
-			mmu_pte_write_new_pte(vcpu, page, spte, new, bytes);
+			mmu_pte_write_new_pte(vcpu, page, spte, new, bytes,
+					      page_offset & (pte_size - 1));
 			++spte;
 		}
 	}
+	kvm_mmu_audit(vcpu, "post pte write");
 }
 
 int kvm_mmu_unprotect_page_virt(struct kvm_vcpu *vcpu, gva_t gva)
@@ -1359,22 +1395,33 @@ static void audit_mappings_page(struct kvm_vcpu *vcpu, u64 page_pte,
 	for (i = 0; i < PT64_ENT_PER_PAGE; ++i, va += va_delta) {
 		u64 ent = pt[i];
 
-		if (!(ent & PT_PRESENT_MASK))
+		if (ent == shadow_trap_nonpresent_pte)
 			continue;
 
 		va = canonicalize(va);
-		if (level > 1)
+		if (level > 1) {
+			if (ent == shadow_notrap_nonpresent_pte)
+				printk(KERN_ERR "audit: (%s) nontrapping pte"
+				       " in nonleaf level: levels %d gva %lx"
+				       " level %d pte %llx\n", audit_msg,
+				       vcpu->mmu.root_level, va, level, ent);
+
 			audit_mappings_page(vcpu, ent, va, level - 1);
-		else {
+		} else {
 			gpa_t gpa = vcpu->mmu.gva_to_gpa(vcpu, va);
 			hpa_t hpa = gpa_to_hpa(vcpu, gpa);
 
-			if ((ent & PT_PRESENT_MASK)
+			if (is_shadow_present_pte(ent)
 			    && (ent & PT64_BASE_ADDR_MASK) != hpa)
-				printk(KERN_ERR "audit error: (%s) levels %d"
-				       " gva %lx gpa %llx hpa %llx ent %llx\n",
+				printk(KERN_ERR "xx audit error: (%s) levels %d"
+				       " gva %lx gpa %llx hpa %llx ent %llx %d\n",
 				       audit_msg, vcpu->mmu.root_level,
-				       va, gpa, hpa, ent);
+				       va, gpa, hpa, ent, is_shadow_present_pte(ent));
+			else if (ent == shadow_notrap_nonpresent_pte
+				 && !is_error_hpa(hpa))
+				printk(KERN_ERR "audit: (%s) notrap shadow,"
+				       " valid guest gva %lx\n", audit_msg, va);
+
 		}
 	}
 }
diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index 6b094b44f8fb..99ac9b15f773 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -31,6 +31,7 @@
 	#define PT_INDEX(addr, level) PT64_INDEX(addr, level)
 	#define SHADOW_PT_INDEX(addr, level) PT64_INDEX(addr, level)
 	#define PT_LEVEL_MASK(level) PT64_LEVEL_MASK(level)
+	#define PT_LEVEL_BITS PT64_LEVEL_BITS
 	#ifdef CONFIG_X86_64
 	#define PT_MAX_FULL_LEVELS 4
 	#else
@@ -45,6 +46,7 @@
 	#define PT_INDEX(addr, level) PT32_INDEX(addr, level)
 	#define SHADOW_PT_INDEX(addr, level) PT64_INDEX(addr, level)
 	#define PT_LEVEL_MASK(level) PT32_LEVEL_MASK(level)
+	#define PT_LEVEL_BITS PT32_LEVEL_BITS
 	#define PT_MAX_FULL_LEVELS 2
 #else
 	#error Invalid PTTYPE value
@@ -211,12 +213,12 @@ static void FNAME(set_pte_common)(struct kvm_vcpu *vcpu,
 {
 	hpa_t paddr;
 	int dirty = gpte & PT_DIRTY_MASK;
-	u64 spte = *shadow_pte;
-	int was_rmapped = is_rmap_pte(spte);
+	u64 spte;
+	int was_rmapped = is_rmap_pte(*shadow_pte);
 
 	pgprintk("%s: spte %llx gpte %llx access %llx write_fault %d"
 		 " user_fault %d gfn %lx\n",
-		 __FUNCTION__, spte, (u64)gpte, access_bits,
+		 __FUNCTION__, *shadow_pte, (u64)gpte, access_bits,
 		 write_fault, user_fault, gfn);
 
 	if (write_fault && !dirty) {
@@ -236,7 +238,7 @@ static void FNAME(set_pte_common)(struct kvm_vcpu *vcpu,
 		FNAME(mark_pagetable_dirty)(vcpu->kvm, walker);
 	}
 
-	spte |= PT_PRESENT_MASK | PT_ACCESSED_MASK | PT_DIRTY_MASK;
+	spte = PT_PRESENT_MASK | PT_ACCESSED_MASK | PT_DIRTY_MASK;
 	spte |= gpte & PT64_NX_MASK;
 	if (!dirty)
 		access_bits &= ~PT_WRITABLE_MASK;
@@ -248,10 +250,8 @@ static void FNAME(set_pte_common)(struct kvm_vcpu *vcpu,
 		spte |= PT_USER_MASK;
 
 	if (is_error_hpa(paddr)) {
-		spte |= gaddr;
-		spte |= PT_SHADOW_IO_MARK;
-		spte &= ~PT_PRESENT_MASK;
-		set_shadow_pte(shadow_pte, spte);
+		set_shadow_pte(shadow_pte,
+			       shadow_trap_nonpresent_pte | PT_SHADOW_IO_MARK);
 		return;
 	}
 
@@ -286,6 +286,7 @@ unshadowed:
 	if (access_bits & PT_WRITABLE_MASK)
 		mark_page_dirty(vcpu->kvm, gaddr >> PAGE_SHIFT);
 
+	pgprintk("%s: setting spte %llx\n", __FUNCTION__, spte);
 	set_shadow_pte(shadow_pte, spte);
 	page_header_update_slot(vcpu->kvm, shadow_pte, gaddr);
 	if (!was_rmapped)
@@ -304,14 +305,18 @@ static void FNAME(set_pte)(struct kvm_vcpu *vcpu, pt_element_t gpte,
 }
 
 static void FNAME(update_pte)(struct kvm_vcpu *vcpu, struct kvm_mmu_page *page,
-			      u64 *spte, const void *pte, int bytes)
+			      u64 *spte, const void *pte, int bytes,
+			      int offset_in_pte)
 {
 	pt_element_t gpte;
 
-	if (bytes < sizeof(pt_element_t))
-		return;
 	gpte = *(const pt_element_t *)pte;
-	if (~gpte & (PT_PRESENT_MASK | PT_ACCESSED_MASK))
+	if (~gpte & (PT_PRESENT_MASK | PT_ACCESSED_MASK)) {
+		if (!offset_in_pte && !is_present_pte(gpte))
+			set_shadow_pte(spte, shadow_notrap_nonpresent_pte);
+		return;
+	}
+	if (bytes < sizeof(pt_element_t))
 		return;
 	pgprintk("%s: gpte %llx spte %p\n", __FUNCTION__, (u64)gpte, spte);
 	FNAME(set_pte)(vcpu, gpte, spte, PT_USER_MASK | PT_WRITABLE_MASK, 0,
@@ -368,7 +373,7 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 		unsigned hugepage_access = 0;
 
 		shadow_ent = ((u64 *)__va(shadow_addr)) + index;
-		if (is_present_pte(*shadow_ent) || is_io_pte(*shadow_ent)) {
+		if (is_shadow_present_pte(*shadow_ent)) {
 			if (level == PT_PAGE_TABLE_LEVEL)
 				break;
 			shadow_addr = *shadow_ent & PT64_BASE_ADDR_MASK;
@@ -500,6 +505,26 @@ static gpa_t FNAME(gva_to_gpa)(struct kvm_vcpu *vcpu, gva_t vaddr)
 	return gpa;
 }
 
+static void FNAME(prefetch_page)(struct kvm_vcpu *vcpu,
+				 struct kvm_mmu_page *sp)
+{
+	int i;
+	pt_element_t *gpt;
+
+	if (sp->role.metaphysical || PTTYPE == 32) {
+		nonpaging_prefetch_page(vcpu, sp);
+		return;
+	}
+
+	gpt = kmap_atomic(gfn_to_page(vcpu->kvm, sp->gfn), KM_USER0);
+	for (i = 0; i < PT64_ENT_PER_PAGE; ++i)
+		if (is_present_pte(gpt[i]))
+			sp->spt[i] = shadow_trap_nonpresent_pte;
+		else
+			sp->spt[i] = shadow_notrap_nonpresent_pte;
+	kunmap_atomic(gpt, KM_USER0);
+}
+
 #undef pt_element_t
 #undef guest_walker
 #undef FNAME
@@ -508,4 +533,5 @@ static gpa_t FNAME(gva_to_gpa)(struct kvm_vcpu *vcpu, gva_t vaddr)
 #undef SHADOW_PT_INDEX
 #undef PT_LEVEL_MASK
 #undef PT_DIR_BASE_ADDR_MASK
+#undef PT_LEVEL_BITS
 #undef PT_MAX_FULL_LEVELS
diff --git a/drivers/kvm/vmx.c b/drivers/kvm/vmx.c
index 8eb49e055ec0..27a3318fa6c2 100644
--- a/drivers/kvm/vmx.c
+++ b/drivers/kvm/vmx.c
@@ -26,6 +26,7 @@
 #include <linux/mm.h>
 #include <linux/highmem.h>
 #include <linux/sched.h>
+#include <linux/moduleparam.h>
 
 #include <asm/io.h>
 #include <asm/desc.h>
@@ -33,6 +34,9 @@
 MODULE_AUTHOR("Qumranet");
 MODULE_LICENSE("GPL");
 
+static int bypass_guest_pf = 1;
+module_param(bypass_guest_pf, bool, 0);
+
 struct vmcs {
 	u32 revision_id;
 	u32 abort;
@@ -1535,8 +1539,8 @@ static int vmx_vcpu_setup(struct vcpu_vmx *vmx)
 	}
 	vmcs_write32(CPU_BASED_VM_EXEC_CONTROL, exec_control);
 
-	vmcs_write32(PAGE_FAULT_ERROR_CODE_MASK, 0);
-	vmcs_write32(PAGE_FAULT_ERROR_CODE_MATCH, 0);
+	vmcs_write32(PAGE_FAULT_ERROR_CODE_MASK, !!bypass_guest_pf);
+	vmcs_write32(PAGE_FAULT_ERROR_CODE_MATCH, !!bypass_guest_pf);
 	vmcs_write32(CR3_TARGET_COUNT, 0);           /* 22.2.1 */
 
 	vmcs_writel(HOST_CR0, read_cr0());  /* 22.2.3 */
@@ -2582,6 +2586,9 @@ static int __init vmx_init(void)
 	if (r)
 		goto out1;
 
+	if (bypass_guest_pf)
+		kvm_mmu_set_nonpresent_ptes(~0xffeull, 0ull);
+
 	return 0;
 
 out1:
-- 
2.42.0
```
