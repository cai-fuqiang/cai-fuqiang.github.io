---
layout:     post
title:      "[PATCH 01/13] KVM: MMU: flush remote TLBs on large->normal entry overwrite"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:29 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From 93a423e7045cf3cf69f960ff307edda1afcd7b41 Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:29 -0300
Subject: [PATCH 01/13] KVM: MMU: flush remote TLBs on large->normal entry
 overwrite

It is necessary to flush all TLB's when a large spte entry is
overwritten with a normal page directory pointer.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/paging_tmpl.h | 5 ++++-
 1 file changed, 4 insertions(+), 1 deletion(-)

diff --git a/arch/x86/kvm/paging_tmpl.h b/arch/x86/kvm/paging_tmpl.h
index 6dd08e096e24..e9fbaa44d444 100644
--- a/arch/x86/kvm/paging_tmpl.h
+++ b/arch/x86/kvm/paging_tmpl.h
@@ -310,8 +310,11 @@ static int FNAME(shadow_walk_entry)(struct kvm_shadow_walk *_sw,
 	if (is_shadow_present_pte(*sptep) && !is_large_pte(*sptep))
 		return 0;
 
-	if (is_large_pte(*sptep))
+	if (is_large_pte(*sptep)) {
+		set_shadow_pte(sptep, shadow_trap_nonpresent_pte);
+		kvm_flush_remote_tlbs(vcpu->kvm);
 		rmap_remove(vcpu->kvm, sptep);
+	}
 
 	if (level == PT_DIRECTORY_LEVEL && gw->level == PT_DIRECTORY_LEVEL) {
 		metaphysical = 1;
-- 
2.42.0

```