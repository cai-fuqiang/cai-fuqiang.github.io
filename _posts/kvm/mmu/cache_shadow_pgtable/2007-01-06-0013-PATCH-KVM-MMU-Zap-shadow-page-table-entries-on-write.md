---
layout:     post
title:      "[PATCH 13/33] [PATCH] KVM: MMU: Zap shadow page table entries on writes to guest page tables"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:45 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 9b7a032567ee1128daeebebfc14d3acedfe28c8c Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:45 -0800
Subject: [PATCH 13/33] [PATCH] KVM: MMU: Zap shadow page table entries on
 writes to guest page tables

Iterate over all shadow pages which correspond to a the given guest page table
and remove the mappings.

> correspond /ˌkɔːrəˈspɑːnd/: 相一致
>
> 迭代与给定guest pgtable 相对应的所有影子页并删除映射。

A subsequent page fault will reestablish the new mapping.

> 随后的页面错误将重新建立新的映射。
```

> 如果修改了guest pgtable, 造成写保护, 在emulate 写入 guest page table之前,
> 先clear掉spte(实际上也就是取消映射), 并且处理好反向映射.以及pte_chain
{: .prompt-tip}

```diff
Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/mmu.c | 36 ++++++++++++++++++++++++++++++++++++
 1 file changed, 36 insertions(+)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index bce7eb21f739..6dbd83b86623 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -958,7 +958,43 @@ int kvm_mmu_reset_context(struct kvm_vcpu *vcpu)
 
 void kvm_mmu_pre_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes)
 {
+	gfn_t gfn = gpa >> PAGE_SHIFT;
+	struct kvm_mmu_page *page;
+	struct kvm_mmu_page *child;
+	struct hlist_node *node;
+	struct hlist_head *bucket;
+	unsigned index;
+	u64 *spte;
+	u64 pte;
+	unsigned offset = offset_in_page(gpa);
+	unsigned page_offset;
+	int level;
+
 	pgprintk("%s: gpa %llx bytes %d\n", __FUNCTION__, gpa, bytes);
+	index = kvm_page_table_hashfn(gfn) % KVM_NUM_MMU_PAGES;
+	bucket = &vcpu->kvm->mmu_page_hash[index];
+	hlist_for_each_entry(page, node, bucket, hash_link) {
+		if (page->gfn != gfn || page->role.metaphysical)
+			continue;
+		page_offset = offset;
+		level = page->role.level;
+		if (page->role.glevels == PT32_ROOT_LEVEL) {
+			page_offset <<= 1;          /* 32->64 */
+			page_offset &= ~PAGE_MASK;
+		}
+		spte = __va(page->page_hpa);
+		spte += page_offset / sizeof(*spte);
+		pte = *spte;
+		if (is_present_pte(pte)) {
+			if (level == PT_PAGE_TABLE_LEVEL)
+				rmap_remove(vcpu->kvm, spte);
+			else {
+				child = page_header(pte & PT64_BASE_ADDR_MASK);
+				mmu_page_remove_parent_pte(child, spte);
+			}
+		}
+		*spte = 0;
+	}
 }
 
 void kvm_mmu_post_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes)
-- 
2.42.0

```