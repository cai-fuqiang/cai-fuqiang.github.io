---
layout:     post
title:      "[PATCH 18/33] [PATCH] KVM: MMU: Remove invlpg interception"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:47 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 5f015a5b28c75bb6cc5158640db58689b1ee1b51 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:47 -0800
Subject: [PATCH 18/33] [PATCH] KVM: MMU: Remove invlpg interception

Since we write protect shadowed guest page tables, there is no need to trap
page invalidations (the guest will always change the mapping before issuing
the invlpg instruction).

> interception : 拦截
>
> 由于我们 wp 了 shadow guest pgtable，因此无需捕获page invalidation（guest将始终在
> 发出 invlpg 指令之前更改映射）。

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm.h      |  1 -
 drivers/kvm/kvm_main.c |  4 ----
 drivers/kvm/mmu.c      | 43 ------------------------------------------
 drivers/kvm/svm.c      |  1 -
 drivers/kvm/vmx.c      | 13 -------------
 5 files changed, 62 deletions(-)

diff --git a/drivers/kvm/kvm.h b/drivers/kvm/kvm.h
index 1d0be85651f5..6e4daf404146 100644
--- a/drivers/kvm/kvm.h
+++ b/drivers/kvm/kvm.h
@@ -158,7 +158,6 @@ struct kvm_vcpu;
 struct kvm_mmu {
 	void (*new_cr3)(struct kvm_vcpu *vcpu);
 	int (*page_fault)(struct kvm_vcpu *vcpu, gva_t gva, u32 err);
-	void (*inval_page)(struct kvm_vcpu *vcpu, gva_t gva);
 	void (*free)(struct kvm_vcpu *vcpu);
 	gpa_t (*gva_to_gpa)(struct kvm_vcpu *vcpu, gva_t gva);
 	hpa_t root_hpa;
diff --git a/drivers/kvm/kvm_main.c b/drivers/kvm/kvm_main.c
index 79032438dd16..cec10106ce77 100644
--- a/drivers/kvm/kvm_main.c
+++ b/drivers/kvm/kvm_main.c
@@ -943,10 +943,6 @@ static unsigned long get_segment_base(struct kvm_vcpu *vcpu, int seg)
 
 int emulate_invlpg(struct kvm_vcpu *vcpu, gva_t address)
 {
-	spin_lock(&vcpu->kvm->lock);
-	vcpu->mmu.inval_page(vcpu, address);
-	spin_unlock(&vcpu->kvm->lock);
-	kvm_arch_ops->invlpg(vcpu, address);
 	return X86EMUL_CONTINUE;
 }
 
diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index e4a20a45d834..b7b05c44399d 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -767,10 +767,6 @@ static int nonpaging_page_fault(struct kvm_vcpu *vcpu, gva_t gva,
 	return nonpaging_map(vcpu, addr & PAGE_MASK, paddr);
 }
 
-static void nonpaging_inval_page(struct kvm_vcpu *vcpu, gva_t addr)
-{
-}
-
 static void nonpaging_free(struct kvm_vcpu *vcpu)
 {
 	mmu_free_roots(vcpu);
@@ -782,7 +778,6 @@ static int nonpaging_init_context(struct kvm_vcpu *vcpu)
 
 	context->new_cr3 = nonpaging_new_cr3;
 	context->page_fault = nonpaging_page_fault;
-	context->inval_page = nonpaging_inval_page;
 	context->gva_to_gpa = nonpaging_gva_to_gpa;
 	context->free = nonpaging_free;
 	context->root_level = 0;
@@ -895,42 +890,6 @@ static int may_access(u64 pte, int write, int user)
 	return 1;
 }
 
-/*
- * Remove a shadow pte.
- */
-static void paging_inval_page(struct kvm_vcpu *vcpu, gva_t addr)
-{
-	hpa_t page_addr = vcpu->mmu.root_hpa;
-	int level = vcpu->mmu.shadow_root_level;
-
-	++kvm_stat.invlpg;
-
-	for (; ; level--) {
-		u32 index = PT64_INDEX(addr, level);
-		u64 *table = __va(page_addr);
-
-		if (level == PT_PAGE_TABLE_LEVEL ) {
-			rmap_remove(vcpu->kvm, &table[index]);
-			table[index] = 0;
-			return;
-		}
-
-		if (!is_present_pte(table[index]))
-			return;
-
-		page_addr = table[index] & PT64_BASE_ADDR_MASK;
-
-		if (level == PT_DIRECTORY_LEVEL &&
-			  (table[index] & PT_SHADOW_PS_MARK)) {
-			table[index] = 0;
-			release_pt_page_64(vcpu, page_addr, PT_PAGE_TABLE_LEVEL);
-
-			kvm_arch_ops->tlb_flush(vcpu);
-			return;
-		}
-	}
-}
-
 static void paging_free(struct kvm_vcpu *vcpu)
 {
 	nonpaging_free(vcpu);
@@ -951,7 +910,6 @@ static int paging64_init_context_common(struct kvm_vcpu *vcpu, int level)
 	ASSERT(is_pae(vcpu));
 	context->new_cr3 = paging_new_cr3;
 	context->page_fault = paging64_page_fault;
-	context->inval_page = paging_inval_page;
 	context->gva_to_gpa = paging64_gva_to_gpa;
 	context->free = paging_free;
 	context->root_level = level;
@@ -974,7 +932,6 @@ static int paging32_init_context(struct kvm_vcpu *vcpu)
 
 	context->new_cr3 = paging_new_cr3;
 	context->page_fault = paging32_page_fault;
-	context->inval_page = paging_inval_page;
 	context->gva_to_gpa = paging32_gva_to_gpa;
 	context->free = paging_free;
 	context->root_level = PT32_ROOT_LEVEL;
diff --git a/drivers/kvm/svm.c b/drivers/kvm/svm.c
index 869b524dda6b..99250011a471 100644
--- a/drivers/kvm/svm.c
+++ b/drivers/kvm/svm.c
@@ -497,7 +497,6 @@ static void init_vmcb(struct vmcb *vmcb)
 		/*              (1ULL << INTERCEPT_SELECTIVE_CR0) | */
 				(1ULL << INTERCEPT_CPUID) |
 				(1ULL << INTERCEPT_HLT) |
-				(1ULL << INTERCEPT_INVLPG) |
 				(1ULL << INTERCEPT_INVLPGA) |
 				(1ULL << INTERCEPT_IOIO_PROT) |
 				(1ULL << INTERCEPT_MSR_PROT) |
diff --git a/drivers/kvm/vmx.c b/drivers/kvm/vmx.c
index 2a1c37eed711..59178ad4d344 100644
--- a/drivers/kvm/vmx.c
+++ b/drivers/kvm/vmx.c
@@ -1059,7 +1059,6 @@ static int vmx_vcpu_setup(struct kvm_vcpu *vcpu)
 			       | CPU_BASED_CR8_LOAD_EXITING    /* 20.6.2 */
 			       | CPU_BASED_CR8_STORE_EXITING   /* 20.6.2 */
 			       | CPU_BASED_UNCOND_IO_EXITING   /* 20.6.2 */
//MSR_IA32_VMX_PROCBASED_CTLS, 如果该bit为1, 则VM-execution相关字段必须设置为1, 如果
//为0, 则即可以设置为0, 也可以设置为1. 这里想设置为0, 所以不去set该bit.
-			       | CPU_BASED_INVDPG_EXITING
 			       | CPU_BASED_MOV_DR_EXITING
 			       | CPU_BASED_USE_TSC_OFFSETING   /* 21.3 */
 			);
@@ -1438,17 +1437,6 @@ static int handle_io(struct kvm_vcpu *vcpu, struct kvm_run *kvm_run)
 	return 0;
 }
 
-static int handle_invlpg(struct kvm_vcpu *vcpu, struct kvm_run *kvm_run)
-{
-	u64 address = vmcs_read64(EXIT_QUALIFICATION);
-	int instruction_length = vmcs_read32(VM_EXIT_INSTRUCTION_LEN);
-	spin_lock(&vcpu->kvm->lock);
-	vcpu->mmu.inval_page(vcpu, address);
-	spin_unlock(&vcpu->kvm->lock);
-	vmcs_writel(GUEST_RIP, vmcs_readl(GUEST_RIP) + instruction_length);
-	return 1;
-}
-
 static int handle_cr(struct kvm_vcpu *vcpu, struct kvm_run *kvm_run)
 {
 	u64 exit_qualification;
@@ -1636,7 +1624,6 @@ static int (*kvm_vmx_exit_handlers[])(struct kvm_vcpu *vcpu,
 	[EXIT_REASON_EXCEPTION_NMI]           = handle_exception,
 	[EXIT_REASON_EXTERNAL_INTERRUPT]      = handle_external_interrupt,
 	[EXIT_REASON_IO_INSTRUCTION]          = handle_io,
-	[EXIT_REASON_INVLPG]                  = handle_invlpg,
 	[EXIT_REASON_CR_ACCESS]               = handle_cr,
 	[EXIT_REASON_DR_ACCESS]               = handle_dr,
 	[EXIT_REASON_CPUID]                   = handle_cpuid,
-- 
2.42.0

```