---
layout:     post
title:      "[PATCH 32/33] [PATCH] KVM: MMU: Destroy mmu while we still have a vcpu left"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:55 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 9ede74e0af549d75d4ea870bed8b178983816745 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:55 -0800
Subject: [PATCH 32/33] [PATCH] KVM: MMU: Destroy mmu while we still have a
 vcpu left

mmu_destroy flushes the guest tlb (indirectly), which needs a valid vcpu.

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm_main.c | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

diff --git a/drivers/kvm/kvm_main.c b/drivers/kvm/kvm_main.c
index 6623fecff040..6e15aef6c34f 100644
--- a/drivers/kvm/kvm_main.c
+++ b/drivers/kvm/kvm_main.c
@@ -271,8 +271,8 @@ static void kvm_free_physmem(struct kvm *kvm)
 
 static void kvm_free_vcpu(struct kvm_vcpu *vcpu)
 {
-	kvm_arch_ops->vcpu_free(vcpu);
 	kvm_mmu_destroy(vcpu);
+	kvm_arch_ops->vcpu_free(vcpu);
 }
 
 static void kvm_free_vcpus(struct kvm *kvm)
-- 
2.42.0

```