---
layout:     post
title:      "[PATCH 03/13] KVM: MMU: move local TLB flush to mmu_set_spte"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:31 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From a378b4e64c0fef2d9e53214db167878b7673a7a3 Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:31 -0300
Subject: [PATCH 03/13] KVM: MMU: move local TLB flush to mmu_set_spte

Since the sync page path can collapse flushes.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c | 8 ++++----
 1 file changed, 4 insertions(+), 4 deletions(-)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index 9ad4cc553893..23752ef0839c 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -1189,10 +1189,8 @@ static int set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 				 __func__, gfn);
 			ret = 1;
 			pte_access &= ~ACC_WRITE_MASK;
-			if (is_writeble_pte(spte)) {
+			if (is_writeble_pte(spte))
 				spte &= ~PT_WRITABLE_MASK;
-				kvm_x86_ops->tlb_flush(vcpu);
-			}
 		}
 	}
 
@@ -1241,9 +1239,11 @@ static void mmu_set_spte(struct kvm_vcpu *vcpu, u64 *shadow_pte,
 		}
 	}
 	if (set_spte(vcpu, shadow_pte, pte_access, user_fault, write_fault,
-		      dirty, largepage, gfn, pfn, speculative))
+		      dirty, largepage, gfn, pfn, speculative)) {
 		if (write_fault)
 			*ptwrite = 1;
+		kvm_x86_ops->tlb_flush(vcpu);
+	}
 
 	pgprintk("%s: setting spte %llx\n", __func__, *shadow_pte);
 	pgprintk("instantiating %s PTE (%s) at %ld (%llx) addr %p\n",
-- 
2.42.0

```