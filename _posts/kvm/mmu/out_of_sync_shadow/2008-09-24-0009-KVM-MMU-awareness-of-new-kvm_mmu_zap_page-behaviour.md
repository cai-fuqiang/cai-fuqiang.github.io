---
layout:     post
title:      "[PATCH 09/13] KVM: MMU: awareness of new kvm_mmu_zap_page behaviour"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:37 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From 0738541396be165995c7f2387746eb0b47024fec Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:37 -0300
Subject: [PATCH 09/13] KVM: MMU: awareness of new kvm_mmu_zap_page behaviour

kvm_mmu_zap_page will soon zap the unsynced children of a page. Restart
list walk in such case.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c | 13 +++++++++----
 1 file changed, 9 insertions(+), 4 deletions(-)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index b82abee78f17..c9b4b902527b 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -1078,7 +1078,7 @@ static void kvm_mmu_unlink_parents(struct kvm *kvm, struct kvm_mmu_page *sp)
 	}
 }
 
-static void kvm_mmu_zap_page(struct kvm *kvm, struct kvm_mmu_page *sp)
+static int kvm_mmu_zap_page(struct kvm *kvm, struct kvm_mmu_page *sp)
 {
 	++kvm->stat.mmu_shadow_zapped;
 	kvm_mmu_page_unlink_children(kvm, sp);
@@ -1095,6 +1095,7 @@ static void kvm_mmu_zap_page(struct kvm *kvm, struct kvm_mmu_page *sp)
 		kvm_reload_remote_mmus(kvm);
 	}
 	kvm_mmu_reset_last_pte_updated(kvm);
+	return 0;
 }
 
 /*
@@ -1147,8 +1148,9 @@ static int kvm_mmu_unprotect_page(struct kvm *kvm, gfn_t gfn)
 		if (sp->gfn == gfn && !sp->role.metaphysical) {
 			pgprintk("%s: gfn %lx role %x\n", __func__, gfn,
 				 sp->role.word);
-			kvm_mmu_zap_page(kvm, sp);
 			r = 1;
+			if (kvm_mmu_zap_page(kvm, sp))
+				n = bucket->first;
 		}
 	return r;
 }
@@ -1992,7 +1994,8 @@ void kvm_mmu_pte_write(struct kvm_vcpu *vcpu, gpa_t gpa,
 			 */
 			pgprintk("misaligned: gpa %llx bytes %d role %x\n",
 				 gpa, bytes, sp->role.word);
-			kvm_mmu_zap_page(vcpu->kvm, sp);
+			if (kvm_mmu_zap_page(vcpu->kvm, sp))
+				n = bucket->first;
 			++vcpu->kvm->stat.mmu_flooded;
 			continue;
 		}
@@ -2226,7 +2229,9 @@ void kvm_mmu_zap_all(struct kvm *kvm)
 
 	spin_lock(&kvm->mmu_lock);
 	list_for_each_entry_safe(sp, node, &kvm->arch.active_mmu_pages, link)
-		kvm_mmu_zap_page(kvm, sp);
+		if (kvm_mmu_zap_page(kvm, sp))
+			node = container_of(kvm->arch.active_mmu_pages.next,
+					    struct kvm_mmu_page, link);
 	spin_unlock(&kvm->mmu_lock);
 
 	kvm_flush_remote_tlbs(kvm);
-- 
2.42.0

```