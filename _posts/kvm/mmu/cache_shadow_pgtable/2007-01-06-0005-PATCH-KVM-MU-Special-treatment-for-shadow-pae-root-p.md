---
layout:     post
title:      "[PATCH 05/33] [PATCH] KVM: MU: Special treatment for shadow pae root pages"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:40 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 17ac10ad2bb7d8c4f401668484b2e661a15726c6 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:40 -0800
Subject: [PATCH 05/33] [PATCH] KVM: MU: Special treatment for shadow pae root
 pages

Since we're not going to cache the pae-mode shadow root pages, allocate a
single pae shadow that will hold the four lower-level pages, which will act as
roots.

> 由于我们不打算缓存 pae-mode shadow ROOT pages，因此分配一个 pae shadow 来保存四个
> 较低级别的页面，这些页面将充当root。

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm.h |  17 +------
 drivers/kvm/mmu.c | 110 +++++++++++++++++++++++++++++++++-------------
 2 files changed, 82 insertions(+), 45 deletions(-)

diff --git a/drivers/kvm/kvm.h b/drivers/kvm/kvm.h
index 8323f4009362..abe40dd34eea 100644
--- a/drivers/kvm/kvm.h
+++ b/drivers/kvm/kvm.h
@@ -123,6 +123,8 @@ struct kvm_mmu {
 	hpa_t root_hpa;
 	int root_level;
 	int shadow_root_level;
+
+	u64 *pae_root;
 };
 
 struct kvm_guest_debug {
@@ -548,19 +550,4 @@ static inline u32 get_rdx_init_val(void)
 #define TSS_REDIRECTION_SIZE (256 / 8)
 #define RMODE_TSS_SIZE (TSS_BASE_SIZE + TSS_REDIRECTION_SIZE + TSS_IOPB_SIZE + 1)
 
-#ifdef CONFIG_X86_64
-
-/*
- * When emulating 32-bit mode, cr3 is only 32 bits even on x86_64.  Therefore
- * we need to allocate shadow page tables in the first 4GB of memory, which
- * happens to fit the DMA32 zone.
- */
-#define GFP_KVM_MMU (GFP_KERNEL | __GFP_DMA32)
-
-#else
-
-#define GFP_KVM_MMU GFP_KERNEL
-
-#endif
-
 #endif
diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 0f27beb6c5df..1dcbbd511660 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -420,19 +420,63 @@ static int nonpaging_map(struct kvm_vcpu *vcpu, gva_t v, hpa_t p)
 	}
 }
 
+static void mmu_free_roots(struct kvm_vcpu *vcpu)
+{
+	int i;
+
+#ifdef CONFIG_X86_64
+	if (vcpu->mmu.shadow_root_level == PT64_ROOT_LEVEL) {
+		hpa_t root = vcpu->mmu.root_hpa;
+
+		ASSERT(VALID_PAGE(root));
+		release_pt_page_64(vcpu, root, PT64_ROOT_LEVEL);
+		vcpu->mmu.root_hpa = INVALID_PAGE;
+		return;
+	}
+#endif
+	for (i = 0; i < 4; ++i) {
+		hpa_t root = vcpu->mmu.pae_root[i];
+
+		ASSERT(VALID_PAGE(root));
+		root &= PT64_BASE_ADDR_MASK;
+		release_pt_page_64(vcpu, root, PT32E_ROOT_LEVEL - 1);
+		vcpu->mmu.pae_root[i] = INVALID_PAGE;
+	}
+	vcpu->mmu.root_hpa = INVALID_PAGE;
+}
+
+static void mmu_alloc_roots(struct kvm_vcpu *vcpu)
+{
+	int i;
+
+#ifdef CONFIG_X86_64
+	if (vcpu->mmu.shadow_root_level == PT64_ROOT_LEVEL) {
+		hpa_t root = vcpu->mmu.root_hpa;
+
+		ASSERT(!VALID_PAGE(root));
+		root = kvm_mmu_alloc_page(vcpu, NULL);
+		vcpu->mmu.root_hpa = root;
+		return;
+	}
+#endif
+	for (i = 0; i < 4; ++i) {
+		hpa_t root = vcpu->mmu.pae_root[i];
+
+		ASSERT(!VALID_PAGE(root));
+		root = kvm_mmu_alloc_page(vcpu, NULL);
+		vcpu->mmu.pae_root[i] = root | PT_PRESENT_MASK;
+	}
+	vcpu->mmu.root_hpa = __pa(vcpu->mmu.pae_root);
+}
+
 static void nonpaging_flush(struct kvm_vcpu *vcpu)
 {
 	hpa_t root = vcpu->mmu.root_hpa;
 
 	++kvm_stat.tlb_flush;
 	pgprintk("nonpaging_flush\n");
-	ASSERT(VALID_PAGE(root));
-	release_pt_page_64(vcpu, root, vcpu->mmu.shadow_root_level);
-	root = kvm_mmu_alloc_page(vcpu, NULL);
-	ASSERT(VALID_PAGE(root));
-	vcpu->mmu.root_hpa = root;
-	if (is_paging(vcpu))
-		root |= (vcpu->cr3 & (CR3_PCD_MASK | CR3_WPT_MASK));
+	mmu_free_roots(vcpu);
+	mmu_alloc_roots(vcpu);
 	kvm_arch_ops->set_cr3(vcpu, root);
 	kvm_arch_ops->tlb_flush(vcpu);
 }
@@ -475,13 +519,7 @@ static void nonpaging_inval_page(struct kvm_vcpu *vcpu, gva_t addr)
 
 static void nonpaging_free(struct kvm_vcpu *vcpu)
 {
-	hpa_t root;
-
-	ASSERT(vcpu);
-	root = vcpu->mmu.root_hpa;
-	if (VALID_PAGE(root))
-		release_pt_page_64(vcpu, root, vcpu->mmu.shadow_root_level);
-	vcpu->mmu.root_hpa = INVALID_PAGE;
+	mmu_free_roots(vcpu);
 }
 
 static int nonpaging_init_context(struct kvm_vcpu *vcpu)
@@ -495,7 +533,7 @@ static int nonpaging_init_context(struct kvm_vcpu *vcpu)
 	context->free = nonpaging_free;
 	context->root_level = PT32E_ROOT_LEVEL;
 	context->shadow_root_level = PT32E_ROOT_LEVEL;
-	context->root_hpa = kvm_mmu_alloc_page(vcpu, NULL);
+	mmu_alloc_roots(vcpu);
 	ASSERT(VALID_PAGE(context->root_hpa));
 	kvm_arch_ops->set_cr3(vcpu, context->root_hpa);
 	return 0;
@@ -647,7 +685,7 @@ static void paging_free(struct kvm_vcpu *vcpu)
 #include "paging_tmpl.h"
 #undef PTTYPE
 
-static int paging64_init_context(struct kvm_vcpu *vcpu)
+static int paging64_init_context_common(struct kvm_vcpu *vcpu, int level)
 {
 	struct kvm_mmu *context = &vcpu->mmu;
 
@@ -657,15 +695,20 @@ static int paging64_init_context(struct kvm_vcpu *vcpu)
 	context->inval_page = paging_inval_page;
 	context->gva_to_gpa = paging64_gva_to_gpa;
 	context->free = paging_free;
-	context->root_level = PT64_ROOT_LEVEL;
-	context->shadow_root_level = PT64_ROOT_LEVEL;
-	context->root_hpa = kvm_mmu_alloc_page(vcpu, NULL);
+	context->root_level = level;
+	context->shadow_root_level = level;
+	mmu_alloc_roots(vcpu);
 	ASSERT(VALID_PAGE(context->root_hpa));
 	kvm_arch_ops->set_cr3(vcpu, context->root_hpa |
 		    (vcpu->cr3 & (CR3_PCD_MASK | CR3_WPT_MASK)));
 	return 0;
 }
 
+static int paging64_init_context(struct kvm_vcpu *vcpu)
+{
+	return paging64_init_context_common(vcpu, PT64_ROOT_LEVEL);
+}
+
 static int paging32_init_context(struct kvm_vcpu *vcpu)
 {
 	struct kvm_mmu *context = &vcpu->mmu;
@@ -677,7 +720,7 @@ static int paging32_init_context(struct kvm_vcpu *vcpu)
 	context->free = paging_free;
 	context->root_level = PT32_ROOT_LEVEL;
 	context->shadow_root_level = PT32E_ROOT_LEVEL;
-	context->root_hpa = kvm_mmu_alloc_page(vcpu, NULL);
+	mmu_alloc_roots(vcpu);
 	ASSERT(VALID_PAGE(context->root_hpa));
 	kvm_arch_ops->set_cr3(vcpu, context->root_hpa |
 		    (vcpu->cr3 & (CR3_PCD_MASK | CR3_WPT_MASK)));
@@ -686,14 +729,7 @@ static int paging32_init_context(struct kvm_vcpu *vcpu)
 
 static int paging32E_init_context(struct kvm_vcpu *vcpu)
 {
-	int ret;
-
-	if ((ret = paging64_init_context(vcpu)))
-		return ret;
-
-	vcpu->mmu.root_level = PT32E_ROOT_LEVELalloc_mmu_pages;
-	vcpu->mmu.shadow_root_level = PT32E_ROOT_LEVEL;
-	return 0;
+	return paging64_init_context_common(vcpu, PT32E_ROOT_LEVEL);
 }
 
 static int init_kvm_mmu(struct kvm_vcpu *vcpu)
@@ -737,26 +773,40 @@ static void free_mmu_pages(struct kvm_vcpu *vcpu)
 		__free_page(pfn_to_page(page->page_hpa >> PAGE_SHIFT));
 		page->page_hpa = INVALID_PAGE;
 	}
+	free_page((unsigned long)vcpu->mmu.pae_root);
 }
 
 static int alloc_mmu_pages(struct kvm_vcpu *vcpu)
 {
+	struct page *page;
 	int i;
 
 	ASSERT(vcpu);
 
 	for (i = 0; i < KVM_NUM_MMU_PAGES; i++) {
-		struct page *page;
 		struct kvm_mmu_page *page_header = &vcpu->page_header_buf[i];
 
 		INIT_LIST_HEAD(&page_header->link);
    //这样做, 仅让
-		if ((page = alloc_page(GFP_KVM_MMU)) == NULL)
    //这里相当于分配non-root level pgtable, 所以不用加 __GFP_DMA32 的限制
+		if ((page = alloc_page(GFP_KERNEL)) == NULL)
 			goto error_1;
 		page->private = (unsigned long)page_header;
 		page_header->page_hpa = (hpa_t)page_to_pfn(page) << PAGE_SHIFT;
 		memset(__va(page_header->page_hpa), 0, PAGE_SIZE);
 		list_add(&page_header->link, &vcpu->free_pages);
 	}
+
+	/*
+	 * When emulating 32-bit mode, cr3 is only 32 bits even on x86_64.
+	 * Therefore we need to allocate shadow page tables in the first
+	 * 4GB of memory, which happens to fit the DMA32 zone.
+	 */
	/*
	 * 无论是pae 还是 page32, cr3指向的Root level pgtable都是32bit的.
	 */
+	page = alloc_page(GFP_KERNEL | __GFP_DMA32);
+	if (!page)
+		goto error_1;
+	vcpu->mmu.pae_root = page_address(page);
+	for (i = 0; i < 4; ++i)
+		vcpu->mmu.pae_root[i] = INVALID_PAGE;
+
 	return 0;
 
 error_1:
-- 
2.42.0

```