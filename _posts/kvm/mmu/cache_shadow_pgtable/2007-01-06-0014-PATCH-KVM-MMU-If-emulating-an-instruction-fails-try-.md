---
layout:     post
title:      "[PATCH 14/33] [PATCH] KVM: MMU: If emulating an instruction fails, try unprotecting the page"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:45 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From a436036baf331703b4d2c8e8a45f02c597bf6913 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:45 -0800
Subject: [PATCH 14/33] [PATCH] KVM: MMU: If emulating an instruction fails,
 try unprotecting the page

A page table may have been recycled into a regular page, and so any
instruction can be executed on it.  Unprotect the page and let the cpu do its
thing.

> 页表可能已被回收到常规页中，因此可以在其上执行任何指令。 取消页面保护并让 cpu 
> 执行其操作。
```
> 走到下面的路径中, 就说明不是常规的内存操作指令, 如果是, 并且模拟了就会返回0
> 那么就说明该指令不太像是在操作 pgtable, 例如PUSH指令, 是在操作堆栈, 那么该
> page 很可能被释放, 不用做guest pgtable了. 我们需要zap this shadow pgtable
{:.prompt-tip}
```diff
Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm.h      |  1 +
 drivers/kvm/kvm_main.c |  2 ++
 drivers/kvm/mmu.c      | 58 ++++++++++++++++++++++++++++++++++++++++++
 3 files changed, 61 insertions(+)

diff --git a/drivers/kvm/kvm.h b/drivers/kvm/kvm.h
index b7068ecd7765..34c43bb4d348 100644
--- a/drivers/kvm/kvm.h
+++ b/drivers/kvm/kvm.h
@@ -450,6 +450,7 @@ unsigned long segment_base(u16 selector);
 
 void kvm_mmu_pre_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes);
 void kvm_mmu_post_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes);
+int kvm_mmu_unprotect_page_virt(struct kvm_vcpu *vcpu, gva_t gva);
 
 static inline struct page *_gfn_to_page(struct kvm *kvm, gfn_t gfn)
 {
diff --git a/drivers/kvm/kvm_main.c b/drivers/kvm/kvm_main.c
index 047f6f6ed3f6..79032438dd16 100644
--- a/drivers/kvm/kvm_main.c
+++ b/drivers/kvm/kvm_main.c
@@ -1063,6 +1063,8 @@ int emulate_instruction(struct kvm_vcpu *vcpu,
 	}
  
 	if (r) {
+		if (kvm_mmu_unprotect_page_virt(vcpu, cr2))
+			return EMULATE_DONE;
 		if (!vcpu->mmio_needed) {
 			report_emulation_failure(&emulate_ctxt);
 			return EMULATE_FAIL;
diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 6dbd83b86623..1484b7211717 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -478,11 +478,62 @@ static struct kvm_mmu_page *kvm_mmu_get_page(struct kvm_vcpu *vcpu,
 	return page;
 }
 
+static void kvm_mmu_page_unlink_children(struct kvm_vcpu *vcpu,
+					 struct kvm_mmu_page *page)
+{
+	BUG();
+}
+
 static void kvm_mmu_put_page(struct kvm_vcpu *vcpu,
 			     struct kvm_mmu_page *page,
 			     u64 *parent_pte)
 {
 	mmu_page_remove_parent_pte(page, parent_pte);
+	if (page->role.level > PT_PAGE_TABLE_LEVEL)
+		kvm_mmu_page_unlink_children(vcpu, page);
+	hlist_del(&page->hash_link);
+	list_del(&page->link);
+	list_add(&page->link, &vcpu->free_pages);
+}
//和所有的parent pte解除映射
+static void kvm_mmu_zap_page(struct kvm_vcpu *vcpu,
+			     struct kvm_mmu_page *page)
+{
+	u64 *parent_pte;
+
+	while (page->multimapped || page->parent_pte) {
+		if (!page->multimapped)
+			parent_pte = page->parent_pte;
+		else {
+			struct kvm_pte_chain *chain;
+
+			chain = container_of(page->parent_ptes.first,
+					     struct kvm_pte_chain, link);
+			parent_pte = chain->parent_ptes[0];
+		}
+		kvm_mmu_put_page(vcpu, page, parent_pte);
+		*parent_pte = 0;
+	}
+}
+
+static int kvm_mmu_unprotect_page(struct kvm_vcpu *vcpu, gfn_t gfn)
+{
+	unsigned index;
+	struct hlist_head *bucket;
+	struct kvm_mmu_page *page;
+	struct hlist_node *node, *n;
+	int r;
+
	//找到该gfn对应的 shadow pgtable, 并释放他们
+	pgprintk("%s: looking for gfn %lx\n", __FUNCTION__, gfn);
+	r = 0;
+	index = kvm_page_table_hashfn(gfn) % KVM_NUM_MMU_PAGES;
+	bucket = &vcpu->kvm->mmu_page_hash[index];
+	hlist_for_each_entry_safe(page, node, n, bucket, hash_link)
+		if (page->gfn == gfn && !page->role.metaphysical) {
+			kvm_mmu_zap_page(vcpu, page);
+			r = 1;
+		}
+	return r;
 }
 
 static void page_header_update_slot(struct kvm *kvm, void *pte, gpa_t gpa)
@@ -1001,6 +1052,13 @@ void kvm_mmu_post_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes)
 {
 }
 
+int kvm_mmu_unprotect_page_virt(struct kvm_vcpu *vcpu, gva_t gva)
+{
+	gpa_t gpa = vcpu->mmu.gva_to_gpa(vcpu, gva);
+
+	return kvm_mmu_unprotect_page(vcpu, gpa >> PAGE_SHIFT);
+}
+
 static void free_mmu_pages(struct kvm_vcpu *vcpu)
 {
 	while (!list_empty(&vcpu->free_pages)) {
-- 
2.42.0

```