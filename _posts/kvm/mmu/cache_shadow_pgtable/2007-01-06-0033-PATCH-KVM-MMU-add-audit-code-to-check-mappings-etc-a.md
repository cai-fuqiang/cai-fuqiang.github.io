---
layout:     post
title:      "[PATCH 33/33] [PATCH] KVM: MMU: add audit code to check mappings, etc are correct"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:56 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 37a7d8b046da6254718be1409140cd7bf3126f8f Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:56 -0800
Subject: [PATCH 33/33] [PATCH] KVM: MMU: add audit code to check mappings, etc
 are correct

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c         | 187 +++++++++++++++++++++++++++++++++++++-
 drivers/kvm/paging_tmpl.h |   4 +
 2 files changed, 189 insertions(+), 2 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 2fc252813927..6e7381bc2218 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -26,8 +26,31 @@
 #include "vmx.h"
 #include "kvm.h"
 
-#define pgprintk(x...) do { printk(x); } while (0)
-#define rmap_printk(x...) do { printk(x); } while (0)
+#undef MMU_DEBUG
+
+#undef AUDIT
+
+#ifdef AUDIT
+static void kvm_mmu_audit(struct kvm_vcpu *vcpu, const char *msg);
+#else
+static void kvm_mmu_audit(struct kvm_vcpu *vcpu, const char *msg) {}
+#endif
+
+#ifdef MMU_DEBUG
+
+#define pgprintk(x...) do { if (dbg) printk(x); } while (0)
+#define rmap_printk(x...) do { if (dbg) printk(x); } while (0)
+
+#else
+
+#define pgprintk(x...) do { } while (0)
+#define rmap_printk(x...) do { } while (0)
+
+#endif
+
+#if defined(MMU_DEBUG) || defined(AUDIT)
+static int dbg = 1;
+#endif
 
 #define ASSERT(x)							\
 	if (!(x)) {							\
@@ -1271,3 +1294,163 @@ void kvm_mmu_slot_remove_write_access(struct kvm_vcpu *vcpu, int slot)
 			}
 	}
 }
+
+#ifdef AUDIT
+
+static const char *audit_msg;
+
+static gva_t canonicalize(gva_t gva)
+{
+#ifdef CONFIG_X86_64
+	gva = (long long)(gva << 16) >> 16;
+#endif
+	return gva;
+}
+
+static void audit_mappings_page(struct kvm_vcpu *vcpu, u64 page_pte,
+				gva_t va, int level)
+{
+	u64 *pt = __va(page_pte & PT64_BASE_ADDR_MASK);
+	int i;
+	gva_t va_delta = 1ul << (PAGE_SHIFT + 9 * (level - 1));
+
+	for (i = 0; i < PT64_ENT_PER_PAGE; ++i, va += va_delta) {
+		u64 ent = pt[i];
+
+		if (!ent & PT_PRESENT_MASK)
+			continue;
+
+		va = canonicalize(va);
+		if (level > 1)
+			audit_mappings_page(vcpu, ent, va, level - 1);
+		else {
+			gpa_t gpa = vcpu->mmu.gva_to_gpa(vcpu, va);
+			hpa_t hpa = gpa_to_hpa(vcpu, gpa);
+
+			if ((ent & PT_PRESENT_MASK)
+			    && (ent & PT64_BASE_ADDR_MASK) != hpa)
+				printk(KERN_ERR "audit error: (%s) levels %d"
+				       " gva %lx gpa %llx hpa %llx ent %llx\n",
+				       audit_msg, vcpu->mmu.root_level,
+				       va, gpa, hpa, ent);
+		}
+	}
+}
+
+static void audit_mappings(struct kvm_vcpu *vcpu)
+{
+	int i;
+
+	if (vcpu->mmu.root_level == 4)
+		audit_mappings_page(vcpu, vcpu->mmu.root_hpa, 0, 4);
+	else
+		for (i = 0; i < 4; ++i)
+			if (vcpu->mmu.pae_root[i] & PT_PRESENT_MASK)
+				audit_mappings_page(vcpu,
+						    vcpu->mmu.pae_root[i],
+						    i << 30,
+						    2);
+}
+
+static int count_rmaps(struct kvm_vcpu *vcpu)
+{
+	int nmaps = 0;
+	int i, j, k;
+
+	for (i = 0; i < KVM_MEMORY_SLOTS; ++i) {
+		struct kvm_memory_slot *m = &vcpu->kvm->memslots[i];
+		struct kvm_rmap_desc *d;
+
+		for (j = 0; j < m->npages; ++j) {
+			struct page *page = m->phys_mem[j];
+
+			if (!page->private)
+				continue;
+			if (!(page->private & 1)) {
+				++nmaps;
+				continue;
+			}
+			d = (struct kvm_rmap_desc *)(page->private & ~1ul);
+			while (d) {
+				for (k = 0; k < RMAP_EXT; ++k)
+					if (d->shadow_ptes[k])
+						++nmaps;
+					else
+						break;
+				d = d->more;
+			}
+		}
+	}
+	return nmaps;
+}
+
+static int count_writable_mappings(struct kvm_vcpu *vcpu)
+{
+	int nmaps = 0;
+	struct kvm_mmu_page *page;
+	int i;
+
+	list_for_each_entry(page, &vcpu->kvm->active_mmu_pages, link) {
+		u64 *pt = __va(page->page_hpa);
+
+		if (page->role.level != PT_PAGE_TABLE_LEVEL)
+			continue;
+
+		for (i = 0; i < PT64_ENT_PER_PAGE; ++i) {
+			u64 ent = pt[i];
+
+			if (!(ent & PT_PRESENT_MASK))
+				continue;
+			if (!(ent & PT_WRITABLE_MASK))
+				continue;
+			++nmaps;
+		}
+	}
+	return nmaps;
+}
+
+static void audit_rmap(struct kvm_vcpu *vcpu)
+{
+	int n_rmap = count_rmaps(vcpu);
+	int n_actual = count_writable_mappings(vcpu);
+
+	if (n_rmap != n_actual)
+		printk(KERN_ERR "%s: (%s) rmap %d actual %d\n",
+		       __FUNCTION__, audit_msg, n_rmap, n_actual);
+}
+
+static void audit_write_protection(struct kvm_vcpu *vcpu)
+{
+	struct kvm_mmu_page *page;
+
+	list_for_each_entry(page, &vcpu->kvm->active_mmu_pages, link) {
+		hfn_t hfn;
+		struct page *pg;
+
+		if (page->role.metaphysical)
+			continue;
+
+		hfn = gpa_to_hpa(vcpu, (gpa_t)page->gfn << PAGE_SHIFT)
+			>> PAGE_SHIFT;
+		pg = pfn_to_page(hfn);
+		if (pg->private)
+			printk(KERN_ERR "%s: (%s) shadow page has writable"
+			       " mappings: gfn %lx role %x\n",
+			       __FUNCTION__, audit_msg, page->gfn,
+			       page->role.word);
+	}
+}
+
+static void kvm_mmu_audit(struct kvm_vcpu *vcpu, const char *msg)
+{
+	int olddbg = dbg;
+
+	dbg = 0;
+	audit_msg = msg;
+	audit_rmap(vcpu);
+	audit_write_protection(vcpu);
+	audit_mappings(vcpu);
+	dbg = olddbg;
+}
+
+#endif
diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index 32b385188454..c894b51ba3f8 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -355,6 +355,7 @@ static int FNAME(page_fault)(struct kvm_vcpu *vcpu, gva_t addr,
 	int r;
 
 	pgprintk("%s: addr %lx err %x\n", __FUNCTION__, addr, error_code);
+	kvm_mmu_audit(vcpu, "pre page fault");
 
 	r = mmu_topup_memory_caches(vcpu);
 	if (r)
@@ -402,6 +403,7 @@ static int FNAME(page_fault)(struct kvm_vcpu *vcpu, gva_t addr,
 		pgprintk("%s: io work, no access\n", __FUNCTION__);
 		inject_page_fault(vcpu, addr,
 				  error_code | PFERR_PRESENT_MASK);
+		kvm_mmu_audit(vcpu, "post page fault (io)");
 		return 0;
 	}
 
@@ -410,10 +412,12 @@ static int FNAME(page_fault)(struct kvm_vcpu *vcpu, gva_t addr,
 	 */
 	if (pte_present && !fixed && !write_pt) {
 		inject_page_fault(vcpu, addr, error_code);
+		kvm_mmu_audit(vcpu, "post page fault (guest)");
 		return 0;
 	}
 
 	++kvm_stat.pf_fixed;
+	kvm_mmu_audit(vcpu, "post page fault (fixed)");
 
 	return write_pt;
 }
-- 
2.42.0

```