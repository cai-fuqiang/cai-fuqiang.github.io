---
layout:     post
title:      "[PATCH 24/33] [PATCH] KVM: MMU: Page table write flood protection"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:50 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 86a5ba025d0a0b251817d0efbeaf7037d4175d21 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:50 -0800
Subject: [PATCH 24/33] [PATCH] KVM: MMU: Page table write flood protection

In fork() (or when we protect a page that is no longer a page table), we can
experience floods of writes to a page, which have to be emulated.  This is
expensive.

> 在 fork() 中（或者当我们保护不再是页表的页面时），我们可能会遇到对页面的大量写
> 入，必须对其进行模拟。 这是很昂贵的。

So, if we detect such a flood, zap the page so subsequent writes can proceed
natively.

> 因此，如果我们检测到此类flood，请zap该页面，以便后续写入可以natively进行。

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm.h |  3 +++
 drivers/kvm/mmu.c | 16 +++++++++++++++-
 2 files changed, 18 insertions(+), 1 deletion(-)

diff --git a/drivers/kvm/kvm.h b/drivers/kvm/kvm.h
index 6e4daf404146..201b2735ca91 100644
--- a/drivers/kvm/kvm.h
+++ b/drivers/kvm/kvm.h
@@ -238,6 +238,9 @@ struct kvm_vcpu {
 	struct kvm_mmu_page page_header_buf[KVM_NUM_MMU_PAGES];
 	struct kvm_mmu mmu;
 
+	gfn_t last_pt_write_gfn;
+	int   last_pt_write_count;
+
 	struct kvm_guest_debug guest_debug;
 
 	char fx_buf[FX_BUF_SIZE];
diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 8cf3688f7e70..0e44aca9eee7 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -969,8 +969,17 @@ void kvm_mmu_pre_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes)
 	unsigned page_offset;
 	unsigned misaligned;
 	int level;
+	int flooded = 0;
 
 	pgprintk("%s: gpa %llx bytes %d\n", __FUNCTION__, gpa, bytes);
+	if (gfn == vcpu->last_pt_write_gfn) {
+		++vcpu->last_pt_write_count;
+		if (vcpu->last_pt_write_count >= 3)
+			flooded = 1;
+	} else {
+		vcpu->last_pt_write_gfn = gfn;
+		vcpu->last_pt_write_count = 1;
+	}
 	index = kvm_page_table_hashfn(gfn) % KVM_NUM_MMU_PAGES;
 	bucket = &vcpu->kvm->mmu_page_hash[index];
 	hlist_for_each_entry_safe(page, node, n, bucket, hash_link) {
@@ -978,11 +987,16 @@ void kvm_mmu_pre_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes)
 			continue;
 		pte_size = page->role.glevels == PT32_ROOT_LEVEL ? 4 : 8;
 		misaligned = (offset ^ (offset + bytes - 1)) & ~(pte_size - 1);
-		if (misaligned) {
+		if (misaligned || flooded) {
 			/*
 			 * Misaligned accesses are too much trouble to fix
 			 * up; also, they usually indicate a page is not used
 			 * as a page table.
+			 *
+			 * If we're seeing too many writes to a page,
+			 * it may no longer be a page table, or we may be
+			 * forking, in which case it is better to unmap the
+			 * page.
 			 */
 			pgprintk("misaligned: gpa %llx bytes %d role %x\n",
 				 gpa, bytes, page->role.word);
-- 
2.42.0

```