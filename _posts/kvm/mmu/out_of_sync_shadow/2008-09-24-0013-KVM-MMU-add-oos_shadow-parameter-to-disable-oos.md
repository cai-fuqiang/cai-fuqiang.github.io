---
layout:     post
title:      "[PATCH 13/13] KVM: MMU: add \"oos_shadow\" parameter to disable oos says it all."
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:41 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From 582801a95d2f2ceab841779e1dec0e11dfec44c0 Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:41 -0300
Subject: [PATCH 13/13] KVM: MMU: add "oos_shadow" parameter to disable oos

Subject says it all.

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c | 5 ++++-
 1 file changed, 4 insertions(+), 1 deletion(-)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index cb391d629af2..99c239c5c0ac 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -70,6 +70,9 @@ static int dbg = 0;
 module_param(dbg, bool, 0644);
 #endif
 
+static int oos_shadow = 1;
+module_param(oos_shadow, bool, 0644);
+
 #ifndef MMU_DEBUG
 #define ASSERT(x) do { } while (0)
 #else
@@ -1424,7 +1427,7 @@ static int mmu_need_write_protect(struct kvm_vcpu *vcpu, gfn_t gfn,
 			return 1;
 		if (shadow->unsync)
 			return 0;
-		if (can_unsync)
+		if (can_unsync && oos_shadow)
 			return kvm_unsync_page(vcpu, shadow);
 		return 1;
 	}
-- 
2.42.0

```