---
layout:     post
title:      "[PATCH 27/33] [PATCH] KVM: MMU: Treat user-mode faults as a hint that a page is no longer a page table"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:52 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 143646567f6dcd584e1ab359b5ec83e0545e70cf Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:52 -0800
Subject: [PATCH 27/33] [PATCH] KVM: MMU: Treat user-mode faults as a hint that
 a page is no longer a page table

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/paging_tmpl.h | 13 ++++++++++++-
 1 file changed, 12 insertions(+), 1 deletion(-)
```

> 因为页表一般都是kernel 侧操作,如果发生了用户态操作了 pgtable, 则说明其已经
> 不是pgtable[了.
{: .prompt-tip}
```diff
diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index 03c474aaedde..6acb16ea5ce2 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -271,6 +271,7 @@ static int FNAME(fix_write_pf)(struct kvm_vcpu *vcpu,
 	pt_element_t *guest_ent;
 	int writable_shadow;
 	gfn_t gfn;
+	struct kvm_mmu_page *page;

 	if (is_writeble_pte(*shadow_ent))
 		return 0;
@@ -303,7 +304,17 @@ static int FNAME(fix_write_pf)(struct kvm_vcpu *vcpu,
 	}

 	gfn = walker->gfn;
-	if (kvm_mmu_lookup_page(vcpu, gfn)) {
+
+	if (user) {
+		/*
+		 * Usermode page faults won't be for page table updates.
+		 */
+		while ((page = kvm_mmu_lookup_page(vcpu, gfn)) != NULL) {
+			pgprintk("%s: zap %lx %x\n",
+				 __FUNCTION__, gfn, page->role.word);
+			kvm_mmu_zap_page(vcpu, page);
+		}
+	} else if (kvm_mmu_lookup_page(vcpu, gfn)) {
 		pgprintk("%s: found shadow page for %lx, marking ro\n",
 			 __FUNCTION__, gfn);
 		*write_pt = 1;
--
2.42.0

```