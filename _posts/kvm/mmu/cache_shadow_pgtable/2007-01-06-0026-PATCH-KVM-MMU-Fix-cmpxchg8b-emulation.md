---
layout:     post
title:      "[PATCH 26/33] [PATCH] KVM: MMU: Fix cmpxchg8b emulation"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:51 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```diff
From 32b35627355c3bf17e1903efd117efed7653a54e Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:51 -0800
Subject: [PATCH 26/33] [PATCH] KVM: MMU: Fix cmpxchg8b emulation

cmpxchg8b uses edx:eax as the compare operand, not edi:eax.

> intel sdm said:
> Compares the 64-bit value in EDX:EAX (or 128-bit value in RDX:RAX
> if operand size is 128 bits) with the operand
> (destination operand).

cmpxchg8b is used by 32-bit pae guests to set page table entries atomically,
and this is emulated touching shadowed guest page tables.

> cmpxchg8b 用来 32-bit pae guest 来atomically 设置 pgtable entries, 并且这是模拟
> touching影子guest 页表。

Also, implement it for 32-bit hosts.

> 同时在32-bit host实现它.
```

> 这里主要在host上emulate时, CONFIG_X86_32 所支持的数据类型只能是32-bit的, 所以
> 64-bit的操作数, 只能拆分成两次传递到 emulator_write_emulated
{: .prompt-tip}

```diff
Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm_main.c    | 27 +++++++++++++++++++++++++++
 drivers/kvm/x86_emulate.c |  2 +-
 2 files changed, 28 insertions(+), 1 deletion(-)

diff --git a/drivers/kvm/kvm_main.c b/drivers/kvm/kvm_main.c
index cec10106ce77..2e6bc5659953 100644
--- a/drivers/kvm/kvm_main.c
+++ b/drivers/kvm/kvm_main.c
@@ -936,6 +936,30 @@ static int emulator_cmpxchg_emulated(unsigned long addr,
 	return emulator_write_emulated(addr, new, bytes, ctxt);
 }
 
+#ifdef CONFIG_X86_32
+
+static int emulator_cmpxchg8b_emulated(unsigned long addr,
+				       unsigned long old_lo,
+				       unsigned long old_hi,
+				       unsigned long new_lo,
+				       unsigned long new_hi,
+				       struct x86_emulate_ctxt *ctxt)
+{
+	static int reported;
+	int r;
+
+	if (!reported) {
+		reported = 1;
+		printk(KERN_WARNING "kvm: emulating exchange8b as write\n");
+	}
+	r = emulator_write_emulated(addr, new_lo, 4, ctxt);
+	if (r != X86EMUL_CONTINUE)
+		return r;
+	return emulator_write_emulated(addr+4, new_hi, 4, ctxt);
+}
+
+#endif
+
 static unsigned long get_segment_base(struct kvm_vcpu *vcpu, int seg)
 {
 	return kvm_arch_ops->get_segment_base(vcpu, seg);
@@ -1010,6 +1034,9 @@ struct x86_emulate_ops emulate_ops = {
 	.read_emulated       = emulator_read_emulated,
 	.write_emulated      = emulator_write_emulated,
 	.cmpxchg_emulated    = emulator_cmpxchg_emulated,
+#ifdef CONFIG_X86_32
+	.cmpxchg8b_emulated  = emulator_cmpxchg8b_emulated,
+#endif
 };
 
 int emulate_instruction(struct kvm_vcpu *vcpu,
diff --git a/drivers/kvm/x86_emulate.c b/drivers/kvm/x86_emulate.c
index 1bff3e925fda..be70795b4822 100644
--- a/drivers/kvm/x86_emulate.c
+++ b/drivers/kvm/x86_emulate.c
@@ -1323,7 +1323,7 @@ twobyte_special_insn:
 							 ctxt)) != 0))
 				goto done;
 			if ((old_lo != _regs[VCPU_REGS_RAX])
-			    || (old_hi != _regs[VCPU_REGS_RDI])) {
+			    || (old_hi != _regs[VCPU_REGS_RDX])) {
 				_regs[VCPU_REGS_RAX] = old_lo;
 				_regs[VCPU_REGS_RDX] = old_hi;
 				_eflags &= ~EFLG_ZF;
-- 
2.42.0

```