---
layout:     post
title:      "[PATCH 22/33] [PATCH] KVM: MMU: Ensure freed shadow pages are clean"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:49 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 5f1e0b6abcc100a79528387207adc3dd92aa5374 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:49 -0800
Subject: [PATCH 22/33] [PATCH] KVM: MMU: Ensure freed shadow pages are clean

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c | 1 +
 1 file changed, 1 insertion(+)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index c55ce7d1509e..b9ba240144b7 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -318,6 +318,7 @@ static void kvm_mmu_free_page(struct kvm_vcpu *vcpu, hpa_t page_hpa)
 {
 	struct kvm_mmu_page *page_head = page_header(page_hpa);
 
+	ASSERT(is_empty_shadow_page(page_hpa));
 	list_del(&page_head->link);
 	page_head->page_hpa = page_hpa;
 	list_add(&page_head->link, &vcpu->free_pages);
-- 
2.42.0

```