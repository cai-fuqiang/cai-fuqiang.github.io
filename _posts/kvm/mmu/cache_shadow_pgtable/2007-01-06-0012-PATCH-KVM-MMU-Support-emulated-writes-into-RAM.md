---
layout:     post
title:      "[PATCH 12/33] [PATCH] KVM: MMU: Support emulated writes into RAM"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:44 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From da4a00f002239f72b0d7d0eeaa3b60100e2b1438 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:44 -0800
Subject: [PATCH 12/33] [PATCH] KVM: MMU: Support emulated writes into RAM

As the mmu write protects guest page table, we emulate those writes.  Since
they are not mmio, there is no need to go to userspace to perform them.

> 由于 mmu wp 了 guest 页表，因此我们模拟这些写入。 由于它们不是 mmio，因此
> 无需进入用户空间来执行它们。

So, perform the writes in the kernel if possible, and notify the mmu about
them so it can take the approriate action.

> 因此，如果可能的话，在内核中执行写入，并通知 mmu，以便它采取适当的操作。

Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm.h      |  3 +++
 drivers/kvm/kvm_main.c | 24 ++++++++++++++++++++++++
 drivers/kvm/mmu.c      |  9 +++++++++
 3 files changed, 36 insertions(+)

diff --git a/drivers/kvm/kvm.h b/drivers/kvm/kvm.h
index 58b9deb0bc0e..b7068ecd7765 100644
--- a/drivers/kvm/kvm.h
+++ b/drivers/kvm/kvm.h
@@ -448,6 +448,9 @@ int kvm_write_guest(struct kvm_vcpu *vcpu,
 
 unsigned long segment_base(u16 selector);
 
+void kvm_mmu_pre_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes);
+void kvm_mmu_post_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes);
+
 static inline struct page *_gfn_to_page(struct kvm *kvm, gfn_t gfn)
 {
 	struct kvm_memory_slot *slot = gfn_to_memslot(kvm, gfn);
diff --git a/drivers/kvm/kvm_main.c b/drivers/kvm/kvm_main.c
index 68e121eeccbc..047f6f6ed3f6 100644
--- a/drivers/kvm/kvm_main.c
+++ b/drivers/kvm/kvm_main.c
@@ -877,6 +877,27 @@ static int emulator_read_emulated(unsigned long addr,
 	}
 }
 
+static int emulator_write_phys(struct kvm_vcpu *vcpu, gpa_t gpa,
+			       unsigned long val, int bytes)
+{
+	struct kvm_memory_slot *m;
+	struct page *page;
+	void *virt;
+
+	if (((gpa + bytes - 1) >> PAGE_SHIFT) != (gpa >> PAGE_SHIFT))
+		return 0;
+	m = gfn_to_memslot(vcpu->kvm, gpa >> PAGE_SHIFT);
+	if (!m)
+		return 0;
+	page = gfn_to_page(m, gpa >> PAGE_SHIFT);
+	kvm_mmu_pre_write(vcpu, gpa, bytes);
+	virt = kmap_atomic(page, KM_USER0);
+	memcpy(virt + offset_in_page(gpa), &val, bytes);
+	kunmap_atomic(virt, KM_USER0);
+	kvm_mmu_post_write(vcpu, gpa, bytes);
+	return 1;
+}
+
 static int emulator_write_emulated(unsigned long addr,
 				   unsigned long val,
 				   unsigned int bytes,
@@ -888,6 +909,9 @@ static int emulator_write_emulated(unsigned long addr,
 	if (gpa == UNMAPPED_GVA)
 		return X86EMUL_PROPAGATE_FAULT;
 
+	if (emulator_write_phys(vcpu, gpa, val, bytes))
+		return X86EMUL_CONTINUE;
+
 	vcpu->mmio_needed = 1;
 	vcpu->mmio_phys_addr = gpa;
 	vcpu->mmio_size = bytes;
diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index ceae25bfd4b5..bce7eb21f739 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -956,6 +956,15 @@ int kvm_mmu_reset_context(struct kvm_vcpu *vcpu)
 	return init_kvm_mmu(vcpu);
 }
 
+void kvm_mmu_pre_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes)
+{
+	pgprintk("%s: gpa %llx bytes %d\n", __FUNCTION__, gpa, bytes);
+}
+
+void kvm_mmu_post_write(struct kvm_vcpu *vcpu, gpa_t gpa, int bytes)
+{
+}
+
 static void free_mmu_pages(struct kvm_vcpu *vcpu)
 {
 	while (!list_empty(&vcpu->free_pages)) {
-- 
2.42.0

```