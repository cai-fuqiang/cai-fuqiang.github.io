---
layout:     post
title:      "[PATCH 20/33] [PATCH] KVM: MMU: Handle misaligned accesses to write protected guest page tables"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:48 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 0e7bc4b9610ed9fde0fa14f0b7a7f939805e5ae9 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:48 -0800
Subject: [PATCH 20/33] [PATCH] KVM: MMU: Handle misaligned accesses to write
 protected guest page tables

A misaligned access affects two shadow ptes instead of just one.
> 未对齐的访问会影响两个影子 pte，而不是仅影响一个。

Since a misaligned access is unlikely to occur on a real page table, just zap
the page out of existence, avoiding further trouble.

> 由于在实际页表上不太可能发生未对齐的访问，因此只需将该页zap即可，避免进一步
> 的麻烦。

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c | 19 +++++++++++++++++--
 1 file changed, 17 insertions(+), 2 deletions(-)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 53c3643038bb..50b1432dceee 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -954,21 +954,36 @@ void kvm_mmu_pre_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes)
 	gfn_t gfn = gpa >> PAGE_SHIFT;
 	struct kvm_mmu_page *page;
 	struct kvm_mmu_page *child;
-	struct hlist_node *node;
+	struct hlist_node *node, *n;
 	struct hlist_head *bucket;
 	unsigned index;
 	u64 *spte;
 	u64 pte;
 	unsigned offset = offset_in_page(gpa);
+	unsigned pte_size;
 	unsigned page_offset;
+	unsigned misaligned;
 	int level;
 
 	pgprintk("%s: gpa %llx bytes %d\n", __FUNCTION__, gpa, bytes);
 	index = kvm_page_table_hashfn(gfn) % KVM_NUM_MMU_PAGES;
 	bucket = &vcpu->kvm->mmu_page_hash[index];
-	hlist_for_each_entry(page, node, bucket, hash_link) {
+	hlist_for_each_entry_safe(page, node, n, bucket, hash_link) {
 		if (page->gfn != gfn || page->role.metaphysical)
 			continue;
+		pte_size = page->role.glevels == PT32_ROOT_LEVEL ? 4 : 8;
		/* 这里要比较offset和 offset+bytes-1,两者是不是没有在同一个pte_size中
		 * 例如,如果pte_size 是8 byte
		 * |---8------|---8-----|-----8---|
		 *   offset     offset+
		 *              byte-1
		 * 这样就说明, 其没有对齐.
		 * 所以就需要验证, 在pte_size - 1的其余位, 两者有没有不同的bit, 就需要
		 * 用到异或运算.
		 */
+		misaligned = (offset ^ (offset + bytes - 1)) & ~(pte_size - 1);
+		if (misaligned) {
+			/*
+			 * Misaligned accesses are too much trouble to fix
+			 * up; also, they usually indicate a page is not used
+			 * as a page table.
+			 */
+			pgprintk("misaligned: gpa %llx bytes %d role %x\n",
+				 gpa, bytes, page->role.word);
+			kvm_mmu_zap_page(vcpu, page);
+			continue;
+		}
 		page_offset = offset;
 		level = page->role.level;
 		if (page->role.glevels == PT32_ROOT_LEVEL) {
-- 
2.42.0

```
