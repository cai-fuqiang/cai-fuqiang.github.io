---
layout:     post
title:      "[PATCH 06/13] KVM: MMU: sync roots on mmu reload"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:34 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

```diff
From 0ba73cdadb8ac172f396df7e23c4a9cebd59b550 Mon Sep 17 00:00:00 2001
From: Marcelo Tosatti <mtosatti@redhat.com>
Date: Tue, 23 Sep 2008 13:18:34 -0300
Subject: [PATCH 06/13] KVM: MMU: sync roots on mmu reload

Signed-off-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Avi Kivity <avi@redhat.com>
---
 arch/x86/kvm/mmu.c         | 36 ++++++++++++++++++++++++++++++++++++
 arch/x86/kvm/x86.c         |  1 +
 include/asm-x86/kvm_host.h |  1 +
 3 files changed, 38 insertions(+)

diff --git a/arch/x86/kvm/mmu.c b/arch/x86/kvm/mmu.c
index 90f01169c8f0..9d8c4bb68a81 100644
--- a/arch/x86/kvm/mmu.c
+++ b/arch/x86/kvm/mmu.c
@@ -1471,6 +1471,41 @@ static void mmu_alloc_roots(struct kvm_vcpu *vcpu)
 	vcpu->arch.mmu.root_hpa = __pa(vcpu->arch.mmu.pae_root);
 }
 
+static void mmu_sync_children(struct kvm_vcpu *vcpu, struct kvm_mmu_page *sp)
+{
+}
+
+static void mmu_sync_roots(struct kvm_vcpu *vcpu)
+{
+	int i;
+	struct kvm_mmu_page *sp;
+
+	if (!VALID_PAGE(vcpu->arch.mmu.root_hpa))
+		return;
+	if (vcpu->arch.mmu.shadow_root_level == PT64_ROOT_LEVEL) {
+		hpa_t root = vcpu->arch.mmu.root_hpa;
+		sp = page_header(root);
+		mmu_sync_children(vcpu, sp);
+		return;
+	}
+	for (i = 0; i < 4; ++i) {
+		hpa_t root = vcpu->arch.mmu.pae_root[i];
+
+		if (root) {
+			root &= PT64_BASE_ADDR_MASK;
+			sp = page_header(root);
+			mmu_sync_children(vcpu, sp);
+		}
+	}
+}
+
+void kvm_mmu_sync_roots(struct kvm_vcpu *vcpu)
+{
+	spin_lock(&vcpu->kvm->mmu_lock);
+	mmu_sync_roots(vcpu);
+	spin_unlock(&vcpu->kvm->mmu_lock);
+}
+
 static gpa_t nonpaging_gva_to_gpa(struct kvm_vcpu *vcpu, gva_t vaddr)
 {
 	return vaddr;
@@ -1715,6 +1750,7 @@ int kvm_mmu_load(struct kvm_vcpu *vcpu)
 	spin_lock(&vcpu->kvm->mmu_lock);
 	kvm_mmu_free_some_pages(vcpu);
 	mmu_alloc_roots(vcpu);
+	mmu_sync_roots(vcpu);
 	spin_unlock(&vcpu->kvm->mmu_lock);
 	kvm_x86_ops->set_cr3(vcpu, vcpu->arch.mmu.root_hpa);
 	kvm_mmu_flush_tlb(vcpu);
diff --git a/arch/x86/kvm/x86.c b/arch/x86/kvm/x86.c
index 08edeabf15e6..88e6d9abbd2b 100644
--- a/arch/x86/kvm/x86.c
+++ b/arch/x86/kvm/x86.c
@@ -594,6 +594,7 @@ EXPORT_SYMBOL_GPL(kvm_set_cr4);
 void kvm_set_cr3(struct kvm_vcpu *vcpu, unsigned long cr3)
 {
 	if (cr3 == vcpu->arch.cr3 && !pdptrs_changed(vcpu)) {
+		kvm_mmu_sync_roots(vcpu);
 		kvm_mmu_flush_tlb(vcpu);
 		return;
 	}
diff --git a/include/asm-x86/kvm_host.h b/include/asm-x86/kvm_host.h
index 8bad9bd9b37e..475d8ab83bff 100644
--- a/include/asm-x86/kvm_host.h
+++ b/include/asm-x86/kvm_host.h
@@ -584,6 +584,7 @@ int kvm_mmu_unprotect_page_virt(struct kvm_vcpu *vcpu, gva_t gva);
 void __kvm_mmu_free_some_pages(struct kvm_vcpu *vcpu);
 int kvm_mmu_load(struct kvm_vcpu *vcpu);
 void kvm_mmu_unload(struct kvm_vcpu *vcpu);
+void kvm_mmu_sync_roots(struct kvm_vcpu *vcpu);
 
 int kvm_emulate_hypercall(struct kvm_vcpu *vcpu);
 
-- 
2.42.0

```