---
layout:     post
title:      "[PATCH 10/13] KVM: MMU: mmu_convert_notrap helper"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:38 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From 6844dec6948679d084f054235fee19ba4e3a3096 Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:38 -0300
Subject: [PATCH 10/13] KVM: MMU: mmu_convert_notrap helper

Need to convert shadow_notrap_nonpresent -> shadow_trap_nonpresent when
unsyncing pages.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c | 14 ++++++++++++++
 1 file changed, 14 insertions(+)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index c9b4b902527b..57c7580e7f98 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -1173,6 +1173,20 @@ static void page_header_update_slot(struct kvm *kvm, void *pte, gfn_t gfn)
 	__set_bit(slot, &sp->slot_bitmap);
 }
 
+static void mmu_convert_notrap(struct kvm_mmu_page *sp)
+{
+	int i;
+	u64 *pt = sp->spt;
+
+	if (shadow_trap_nonpresent_pte == shadow_notrap_nonpresent_pte)
+		return;
+
+	for (i = 0; i < PT64_ENT_PER_PAGE; ++i) {
+		if (pt[i] == shadow_notrap_nonpresent_pte)
+			set_shadow_pte(&pt[i], shadow_trap_nonpresent_pte);
+	}
+}
+
 struct page *gva_to_page(struct kvm_vcpu *vcpu, gva_t gva)
 {
 	struct page *page;
-- 
2.42.0

```