---
layout:     post
title:      "[PATCH 31/33] [PATCH] KVM: MMU: Flush guest tlb when reducing permissions on a pte"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:55 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 40907d5768ab8cadd4cad97bef350820ded20338 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:55 -0800
Subject: [PATCH 31/33] [PATCH] KVM: MMU: Flush guest tlb when reducing
 permissions on a pte

If we reduce permissions on a pte, we must flush the cached copy of the pte
from the guest's tlb.

> 如果我们减少了pte 的权限, 我们必须从guest tlb中 flush 该pte的cached copy.

This is implemented at the moment by flushing the entire guest tlb, and can be
improved by flushing just the relevant virtual address, if it is known.

> 目前，这是通过刷新整个guest tlb 来实现的，并且可以通过仅刷新相关虚拟地址（如果已知）
> 来改进。

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c | 7 ++++++-
 1 file changed, 6 insertions(+), 1 deletion(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 7761089ef3bc..2fc252813927 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -383,6 +383,7 @@ static void rmap_write_protect(struct kvm_vcpu *vcpu, u64 gfn)
 		BUG_ON(!(*spte & PT_WRITABLE_MASK));
 		rmap_printk("rmap_write_protect: spte %p %llx\n", spte, *spte);
 		rmap_remove(vcpu, spte);
+		kvm_arch_ops->tlb_flush(vcpu);
 		*spte &= ~(u64)PT_WRITABLE_MASK;
 	}
 }
@@ -594,6 +595,7 @@ static void kvm_mmu_page_unlink_children(struct kvm_vcpu *vcpu,
 				rmap_remove(vcpu, &pt[i]);
 			pt[i] = 0;
 		}
+		kvm_arch_ops->tlb_flush(vcpu);
 		return;
 	}
 
@@ -927,7 +929,10 @@ static inline void set_pte_common(struct kvm_vcpu *vcpu,
 			pgprintk("%s: found shadow page for %lx, marking ro\n",
 				 __FUNCTION__, gfn);
 			access_bits &= ~PT_WRITABLE_MASK;
-			*shadow_pte &= ~PT_WRITABLE_MASK;
+			if (is_writeble_pte(*shadow_pte)) {
+				    *shadow_pte &= ~PT_WRITABLE_MASK;
+				    kvm_arch_ops->tlb_flush(vcpu);
+			}
 		}
 	}
 
-- 
2.42.0

```