---
layout:     post
title:      "[PATCH 03/33] [PATCH] KVM: MMU: Load the pae pdptrs on cr3 change like the processor does"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:39 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---
```
From 1342d3536d6a12541ceb276da15f043db90716eb Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:39 -0800
Subject: [PATCH 03/33] [PATCH] KVM: MMU: Load the pae pdptrs on cr3 change
 like the processor does
```

In pae mode, a load of cr3 loads the four third-level page table entries in
addition to cr3 itself.

> 在pae模式下，加载cr3除了加载cr3本身之外，还加载四个三级页表项。
>
>> hardware 也是这样做的, 见intel sdm 4.4.1 `PDPTE Registers`
>>
>>> Corresponding to the PDPTEs, the logical processor maintains a set of four 
>>> (4) internal, non-architectural PDPTE registers, called PDPTE0, PDPTE1, PDPTE2, and 
>>> PDPTE3.
>>
> {: .prompt-tip}

```diff
Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm.h      |  1 +
 drivers/kvm/kvm_main.c | 29 +++++++++++++++++++----------
 2 files changed, 20 insertions(+), 10 deletions(-)

diff --git a/drivers/kvm/kvm.h b/drivers/kvm/kvm.h
index b65511ed4388..8323f4009362 100644
--- a/drivers/kvm/kvm.h
+++ b/drivers/kvm/kvm.h
@@ -185,6 +185,7 @@ struct kvm_vcpu {
 	unsigned long cr3;
 	unsigned long cr4;
 	unsigned long cr8;
+	u64 pdptrs[4]; /* pae */
 	u64 shadow_efer;
 	u64 apic_base;
 	int nmsrs;

/*
 * 这样做的好处有两个.
 * 1. 将pdpte 读取到kvm数据结构中, 方便读取.
 * 2. 可以查看patch 06, 可以避免对 pdpte所在的pgtable进行wp, 减少
 *    vm-exit
 * 3. 这里的好处包不包含让 GUEST pgtable 和 shadow pgtable map关系
 *    1:1, 仔细想想其实不包含, 以为 目前的shadow pgtable 的维度是
 *    多个, 包含了 level, 可以利用这个关系,其映射关系是1:N, 大家可以
 *    这样想, 极限的情况就是 non-paging
 */
diff --git a/drivers/kvm/kvm_main.c b/drivers/kvm/kvm_main.c
index f2a6b6f0e929..4512d8c39c84 100644
--- a/drivers/kvm/kvm_main.c
+++ b/drivers/kvm/kvm_main.c
@@ -298,14 +298,17 @@ static void inject_gp(struct kvm_vcpu *vcpu)
 	kvm_arch_ops->inject_gp(vcpu, 0);
 }
 
-static int pdptrs_have_reserved_bits_set(struct kvm_vcpu *vcpu,
-					 unsigned long cr3)
+/*
+ * Load the pae pdptrs.  Return true is they are all valid.
+ */
+static int load_pdptrs(struct kvm_vcpu *vcpu, unsigned long cr3)
 {
 	gfn_t pdpt_gfn = cr3 >> PAGE_SHIFT;
-	unsigned offset = (cr3 & (PAGE_SIZE-1)) >> 5;
    /*
     * offset是 u64 pointer, 需要原来的base_address >> 3, 也就是 / 8, 实际上
     * 也就是 >> 5 << 2, 那为什么需要先 >> 5呢 ?
     *
     * 在pae mode下, cr3 [4:0]: 是reserved的. 所以需要 >> 5, (其实也就说明
     * pdpte base 是32-byte对齐). 如果>>5 再 <<2 比直接 >> 3 可以保证[4, 3]
     * 这两位是0, 满足手册中 ignored 的语义.
     */
+	unsigned offset = ((cr3 & (PAGE_SIZE-1)) >> 5) << 2;
 	int i;
 	u64 pdpte;
 	u64 *pdpt;
+	int ret;
 	struct kvm_memory_slot *memslot;
 
 	spin_lock(&vcpu->kvm->lock);
@@ -313,16 +316,23 @@ static int pdptrs_have_reserved_bits_set(struct kvm_vcpu *vcpu,
 	/* FIXME: !memslot - emulate? 0xff? */
 	pdpt = kmap_atomic(gfn_to_page(memslot, pdpt_gfn), KM_USER0);
 
+	ret = 1;
 	for (i = 0; i < 4; ++i) {
 		pdpte = pdpt[offset + i];
-		if ((pdpte & 1) && (pdpte & 0xfffffff0000001e6ull))
-			break;
+		if ((pdpte & 1) && (pdpte & 0xfffffff0000001e6ull)) {
+			ret = 0;
+			goto out;
+		}
 	}
 
+	for (i = 0; i < 4; ++i)
+		vcpu->pdptrs[i] = pdpt[offset + i];
+
+out:
 	kunmap_atomic(pdpt, KM_USER0);
 	spin_unlock(&vcpu->kvm->lock);
 
-	return i != 4;
+	return ret;
 }

 /*
  * intel sdm 4.4.1 中有提到 hardware load pdpte 的行为, 都是
  * 伴随着 load cr0/cr3/cr4
  */
 void set_cr0(struct kvm_vcpu *vcpu, unsigned long cr0)
@@ -368,8 +378,7 @@ void set_cr0(struct kvm_vcpu *vcpu, unsigned long cr0)
 			}
 		} else
 #endif
-		if (is_pae(vcpu) &&
-			    pdptrs_have_reserved_bits_set(vcpu, vcpu->cr3)) {
+		if (is_pae(vcpu) && !load_pdptrs(vcpu, vcpu->cr3)) {
 			printk(KERN_DEBUG "set_cr0: #GP, pdptrs "
 			       "reserved bits\n");
 			inject_gp(vcpu);
@@ -411,7 +420,7 @@ void set_cr4(struct kvm_vcpu *vcpu, unsigned long cr4)
 			return;
 		}
 	} else if (is_paging(vcpu) && !is_pae(vcpu) && (cr4 & CR4_PAE_MASK)
-		   && pdptrs_have_reserved_bits_set(vcpu, vcpu->cr3)) {
+		   && !load_pdptrs(vcpu, vcpu->cr3)) {
 		printk(KERN_DEBUG "set_cr4: #GP, pdptrs reserved bits\n");
 		inject_gp(vcpu);
 	}
@@ -443,7 +452,7 @@ void set_cr3(struct kvm_vcpu *vcpu, unsigned long cr3)
 			return;
 		}
 		if (is_paging(vcpu) && is_pae(vcpu) &&
-		    pdptrs_have_reserved_bits_set(vcpu, cr3)) {
+		    !load_pdptrs(vcpu, cr3)) {
 			printk(KERN_DEBUG "set_cr3: #GP, pdptrs "
 			       "reserved bits\n");
 			inject_gp(vcpu);
-- 
2.42.0

```
