---
layout:     post
title:      "[PATCH 11/33] [PATCH] KVM: MMU: Let the walker extract the target page gfn from the pte"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:44 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 815af8d42ee3f844c0ceaf2104bd9c6a0bb1e26c Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:44 -0800
Subject: [PATCH 11/33] [PATCH] KVM: MMU: Let the walker extract the target
 page gfn from the pte

This fixes a problem where set_pte_common() looked for shadowed pages based on
the page directory gfn (a huge page) instead of the actual gfn being mapped.

> 这修复了 set_pte_common() 根据页面目录 gfn（a huge page）而不是映射的实际 gfn 
> 查找shadow page 的问题。
```

> 在set_pte_common()流程中, 需要查看该gfn 所在的page 是不是pgtable, 而pgtable都是
> normal size的页面, 所以我们需要找到actual gfn 来search shadow pgtable. 该patch
> 将actual gfn 放到 walk_addr中进行计算, 然后会用在 set_pte_common 中的 gaddr参数,
> 以及 kvm_mmu_lookup_page() gfn参数中.
{: .prompt-tip}

```diff
Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c         |  7 ++++---
 drivers/kvm/paging_tmpl.h | 41 ++++++++++++++++++++++++++-------------
 2 files changed, 31 insertions(+), 17 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index ba813f49f8aa..ceae25bfd4b5 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -752,7 +752,8 @@ static inline void set_pte_common(struct kvm_vcpu *vcpu,
 			     u64 *shadow_pte,
 			     gpa_t gaddr,
 			     int dirty,
-			     u64 access_bits)
+			     u64 access_bits,
+			     gfn_t gfn)
 {
 	hpa_t paddr;
 
@@ -779,10 +780,10 @@ static inline void set_pte_common(struct kvm_vcpu *vcpu,
 	if (access_bits & PT_WRITABLE_MASK) {
 		struct kvm_mmu_page *shadow;
 
-		shadow = kvm_mmu_lookup_page(vcpu, gaddr >> PAGE_SHIFT);
+		shadow = kvm_mmu_lookup_page(vcpu, gfn);
 		if (shadow) {
 			pgprintk("%s: found shadow page for %lx, marking ro\n",
-				 __FUNCTION__, (gfn_t)(gaddr >> PAGE_SHIFT));
+				 __FUNCTION__, gfn);
 			access_bits &= ~PT_WRITABLE_MASK;
 			*shadow_pte &= ~PT_WRITABLE_MASK;
 		}
diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index cd71973c780c..cf4b74cc75b5 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -62,6 +62,7 @@ struct guest_walker {
 	pt_element_t *table;
 	pt_element_t *ptep;
 	pt_element_t inherited_ar;
+	gfn_t gfn;
 };
 
 /*
@@ -113,12 +114,23 @@ static void FNAME(walk_addr)(struct guest_walker *walker,
 		if (is_present_pte(*ptep) && !(*ptep &  PT_ACCESSED_MASK))
 			*ptep |= PT_ACCESSED_MASK;
 
-		if (!is_present_pte(*ptep) ||
-		    walker->level == PT_PAGE_TABLE_LEVEL ||
-		    (walker->level == PT_DIRECTORY_LEVEL &&
-		     (*ptep & PT_PAGE_SIZE_MASK) &&
-		     (PTTYPE == 64 || is_pse(vcpu))))
+		if (!is_present_pte(*ptep))
+			break;
+
+		if (walker->level == PT_PAGE_TABLE_LEVEL) {
+			walker->gfn = (*ptep & PT_BASE_ADDR_MASK)
+				>> PAGE_SHIFT;
+			break;
+		}
+
+		if (walker->level == PT_DIRECTORY_LEVEL
+		    && (*ptep & PT_PAGE_SIZE_MASK)
+		    && (PTTYPE == 64 || is_pse(vcpu))) {
+			walker->gfn = (*ptep & PT_DIR_BASE_ADDR_MASK)
+				>> PAGE_SHIFT;
+			walker->gfn += PT_INDEX(addr, PT_PAGE_TABLE_LEVEL);
 			break;
+		}
 
 		if (walker->level != 3 || is_long_mode(vcpu))
 			walker->inherited_ar &= walker->table[index];
@@ -143,30 +155,29 @@ static void FNAME(release_walker)(struct guest_walker *walker)
 }
 
 static void FNAME(set_pte)(struct kvm_vcpu *vcpu, u64 guest_pte,
-			   u64 *shadow_pte, u64 access_bits)
+			   u64 *shadow_pte, u64 access_bits, gfn_t gfn)
 {
 	ASSERT(*shadow_pte == 0);
 	access_bits &= guest_pte;
 	*shadow_pte = (guest_pte & PT_PTE_COPY_MASK);
 	set_pte_common(vcpu, shadow_pte, guest_pte & PT_BASE_ADDR_MASK,
-		       guest_pte & PT_DIRTY_MASK, access_bits);
+		       guest_pte & PT_DIRTY_MASK, access_bits, gfn);
 }
 
 static void FNAME(set_pde)(struct kvm_vcpu *vcpu, u64 guest_pde,
-			   u64 *shadow_pte, u64 access_bits,
-			   int index)
+			   u64 *shadow_pte, u64 access_bits, gfn_t gfn)
 {
 	gpa_t gaddr;
 
 	ASSERT(*shadow_pte == 0);
 	access_bits &= guest_pde;
-	gaddr = (guest_pde & PT_DIR_BASE_ADDR_MASK) + PAGE_SIZE * index;
+	gaddr = (gpa_t)gfn << PAGE_SHIFT;
 	if (PTTYPE == 32 && is_cpuid_PSE36())
 		gaddr |= (guest_pde & PT32_DIR_PSE36_MASK) <<
 			(32 - PT32_DIR_PSE36_SHIFT);
 	*shadow_pte = guest_pde & PT_PTE_COPY_MASK;
 	set_pte_common(vcpu, shadow_pte, gaddr,
-		       guest_pde & PT_DIRTY_MASK, access_bits);
+		       guest_pde & PT_DIRTY_MASK, access_bits, gfn);
 }
 
 /*
@@ -214,10 +225,12 @@ static u64 *FNAME(fetch)(struct kvm_vcpu *vcpu, gva_t addr,
 					*prev_shadow_ent |= PT_SHADOW_PS_MARK;
 				FNAME(set_pde)(vcpu, *guest_ent, shadow_ent,
 					       walker->inherited_ar,
-				          PT_INDEX(addr, PT_PAGE_TABLE_LEVEL));
+					       walker->gfn);
 			} else {
 				ASSERT(walker->level == PT_PAGE_TABLE_LEVEL);
-				FNAME(set_pte)(vcpu, *guest_ent, shadow_ent, walker->inherited_ar);
+				FNAME(set_pte)(vcpu, *guest_ent, shadow_ent,
+					       walker->inherited_ar,
+					       walker->gfn);
 			}
 			return shadow_ent;
 		}
@@ -291,7 +304,7 @@ static int FNAME(fix_write_pf)(struct kvm_vcpu *vcpu,
 		return 0;
 	}
 
-	gfn = (*guest_ent & PT64_BASE_ADDR_MASK) >> PAGE_SHIFT;
+	gfn = walker->gfn;
 	if (kvm_mmu_lookup_page(vcpu, gfn)) {
 		pgprintk("%s: found shadow page for %lx, marking ro\n",
 			 __FUNCTION__, gfn);
-- 
2.42.0

```