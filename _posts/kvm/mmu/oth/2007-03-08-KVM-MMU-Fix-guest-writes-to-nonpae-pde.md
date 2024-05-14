---
layout: post
title:  "[PATCH] KVM: MMU: Fix guest writes to nonpae pde"
author: fuqiang
date: Fri, 5 Jan 2007 16:36:38 -0800
categories: [kvm]
tags: [kvm]
---

# 2007-03-08 17:32:00 +0300

```diff
From ac1b714e78c8f0b252f8d8872e6ce6f898a123b3 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Thu, 8 Mar 2007 17:13:32 +0200
Subject: [PATCH] KVM: MMU: Fix guest writes to nonpae pde

KVM shadow page tables are always in pae mode, regardless of the guest
setting.  This means that a guest pde (mapping 4MB of memory) is mapped
to two shadow pdes (mapping 2MB each).

> 无论guest设置如何，KVM 影子页表始终处于 pae 模式。 这意味着一个 guest pde
>（映射 4MB 内存）被映射到两个影子 pde（每个映射 2MB）。

When the guest writes to a pte or pde, we intercept the write and emulate it.
We also remove any shadowed mappings corresponding to the write.  Since the
mmu did not account for the doubling in the number of pdes, it removed the
wrong entry, resulting in a mismatch between shadow page tables and guest
page tables, followed shortly by guest memory corruption.

> corruption /kəˈrʌpʃn/
>
> 当guest 写入 pte 或 pde 时，我们拦截写入并模拟它。 我们还删除了与写入对应的所有
> shadow mappings。 由于 mmu 没有考虑到 pdes 数量加倍的情况，因此它删除了错误的条目，
> 导致影子页表和来宾页表之间不匹配，随后很快就出现了guest 内存损坏。

This patch fixes the problem by detecting the special case of writing to
a non-pae pde and adjusting the address and number of shadow pdes zapped
accordingly.

> accordingly  [əˈkɔːrdɪŋli] 因此; 相应地; 所以; 照着
>
> 此补丁通过检测写入非 pae pde 的特殊情况并相应地调整 zapped pdes 的地址和数量来
> 解决该问题。

Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Avi Kivity <avi@qumranet.com>
---
 drivers/kvm/mmu.c | 46 ++++++++++++++++++++++++++++++++++------------
 1 file changed, 34 insertions(+), 12 deletions(-)


> mail list
>
> https://lore.kernel.org/all/11736076283297-git-send-email-avi@qumranet.com/

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index a1a93368f314..2cb48937be44 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -1093,22 +1093,40 @@ out:
 	return r;
 }

+static void mmu_pre_write_zap_pte(struct kvm_vcpu *vcpu,
+				  struct kvm_mmu_page *page,
+				  u64 *spte)
+{
+	u64 pte;
+	struct kvm_mmu_page *child;
+
+	pte = *spte;
+	if (is_present_pte(pte)) {
+		if (page->role.level == PT_PAGE_TABLE_LEVEL)
+			rmap_remove(vcpu, spte);
+		else {
+			child = page_header(pte & PT64_BASE_ADDR_MASK);
+			mmu_page_remove_parent_pte(vcpu, child, spte);
+		}
+	}
+	*spte = 0;
+}
+
 void kvm_mmu_pre_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes)
 {
 	gfn_t gfn = gpa >> PAGE_SHIFT;
 	struct kvm_mmu_page *page;
-	struct kvm_mmu_page *child;
 	struct hlist_node *node, *n;
 	struct hlist_head *bucket;
 	unsigned index;
 	u64 *spte;
-	u64 pte;
 	unsigned offset = offset_in_page(gpa);
 	unsigned pte_size;
 	unsigned page_offset;
 	unsigned misaligned;
 	int level;
 	int flooded = 0;
+	int npte;

 	pgprintk("%s: gpa %llx bytes %d\n", __FUNCTION__, gpa, bytes);
 	if (gfn == vcpu->last_pt_write_gfn) {
@@ -1144,22 +1162,26 @@ void kvm_mmu_pre_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes)
 		}
 		page_offset = offset;
 		level = page->role.level;
+		npte = 1;
 		if (page->role.glevels == PT32_ROOT_LEVEL) {
-			page_offset <<= 1;          /* 32->64 */
+			page_offset <<= 1;	/* 32->64 */
+			/*
+			 * A 32-bit pde maps 4MB while the shadow pdes map
+			 * only 2MB.  So we need to double the offset again
+			 * and zap two pdes instead of one.
+			 */
+			if (level == PT32_ROOT_LEVEL) {
+				page_offset <<= 1;
+				npte = 2;
+			}
 			page_offset &= ~PAGE_MASK;
 		}
 		spte = __va(page->page_hpa);
 		spte += page_offset / sizeof(*spte);
-		pte = *spte;
-		if (is_present_pte(pte)) {
-			if (level == PT_PAGE_TABLE_LEVEL)
-				rmap_remove(vcpu, spte);
-			else {
-				child = page_header(pte & PT64_BASE_ADDR_MASK);
-				mmu_page_remove_parent_pte(vcpu, child, spte);
-			}
+		while (npte--) {
+			mmu_pre_write_zap_pte(vcpu, page, spte);
+			++spte;
 		}
-		*spte = 0;
 	}
 }

--
2.42.0
```
