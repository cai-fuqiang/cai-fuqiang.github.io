---
layout:     post
title:      "[PATCH 04/13] KVM: MMU: do not write-protect large mappings"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:32 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From 38187c830cab84daecb41169948467f1f19317e3 Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:32 -0300
Subject: [PATCH 04/13] KVM: MMU: do not write-protect large mappings

There is not much point in write protecting large mappings. This
can only happen when a page is shadowed during the window between
is_largepage_backed and mmu_lock acquision. Zap the entry instead, so
the next pagefault will find a shadowed page via is_largepage_backed and
fallback to 4k translations.

Simplifies out of sync shadow.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c | 10 ++++++++--
 1 file changed, 8 insertions(+), 2 deletions(-)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index 23752ef0839c..731e6fe9cb07 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -1180,11 +1180,16 @@ static int set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 	    || (write_fault && !is_write_protection(vcpu) && !user_fault)) {
 		struct kvm_mmu_page *shadow;
 
+		if (largepage && has_wrprotected_page(vcpu->kvm, gfn)) {
+			ret = 1;
+			spte = shadow_trap_nonpresent_pte;
+			goto set_pte;
+		}
+
 		spte |= PT_WRITABLE_MASK;
 
 		shadow = kvm_mmu_lookup_page(vcpu->kvm, gfn);
-		if (shadow ||
-		   (largepage && has_wrprotected_page(vcpu->kvm, gfn))) {
+		if (shadow) {
 			pgprintk("%s: found shadow page for %lx, marking ro\n",
 				 __func__, gfn);
 			ret = 1;
@@ -1197,6 +1202,7 @@ static int set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 	if (pte_access & ACC_WRITE_MASK)
 		mark_page_dirty(vcpu->kvm, gfn);
 
+set_pte:
 	set_shadow_pte(shadow_pte, spte);
 	return ret;
 }
-- 
2.42.0

```