---
layout:     post
title:      "[PATCH 28/33] [PATCH] KVM: MMU: Free pages on kvm destruction"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:52 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From f51234c2cd3ab8bed836e09686e27877e1b55f2a Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:52 -0800
Subject: [PATCH 28/33] [PATCH] KVM: MMU: Free pages on kvm destruction

Because mmu pages have attached rmap and parent pte chain structures, we need
to zap them before freeing so the attached structures are freed.

> 因为 mmu pages 附加了 rmap 和parent pte chain结构，所以我们需要在释放之前对
> 其进行 zap，以便释放附加结构。

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c | 9 +++++++--
 1 file changed, 7 insertions(+), 2 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index f16321498093..0bd2a19709ce 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -1065,9 +1065,14 @@ EXPORT_SYMBOL_GPL(kvm_mmu_free_some_pages);
 
 static void free_mmu_pages(struct kvm_vcpu *vcpu)
 {
-	while (!list_empty(&vcpu->free_pages)) {
-		struct kvm_mmu_page *page;
+	struct kvm_mmu_page *page;
 
+	while (!list_empty(&vcpu->kvm->active_mmu_pages)) {
+		page = container_of(vcpu->kvm->active_mmu_pages.next,
+				    struct kvm_mmu_page, link);
+		kvm_mmu_zap_page(vcpu, page);
+	}
+	while (!list_empty(&vcpu->free_pages)) {
 		page = list_entry(vcpu->free_pages.next,
 				  struct kvm_mmu_page, link);
 		list_del(&page->link);
-- 
2.42.0

```