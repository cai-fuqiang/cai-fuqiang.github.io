---
layout:     post
title:      "[PATCH 1/3] x86, apicv: add APICv register virtualization support"
author:     "fuqiang"
date:       "Fri, 25 Jan 2013 10:18:49 +0800"
categories: [kvm]
tags:       [kvm]
---

```diff
From 83d4c286931c9d28c5be21bac3c73a2332cab681 Mon Sep 17 00:00:00 2001
From: Yang Zhang <yang.z.zhang@intel.com>
Date: Fri, 25 Jan 2013 10:18:49 +0800
Subject: [PATCH 1/3] x86, apicv: add APICv register virtualization support

- APIC read doesn't cause VM-Exit
- APIC write becomes trap-like

Reviewed-by: Marcelo Tosatti <mtosatti@redhat.com>
Signed-off-by: Kevin Tian <kevin.tian@intel.com>
Signed-off-by: Yang Zhang <yang.z.zhang@intel.com>
Signed-off-by: Gleb Natapov <gleb@redhat.com>
---
 arch/x86/include/asm/vmx.h |  2 ++
 arch/x86/kvm/lapic.c       | 15 +++++++++++++++
 arch/x86/kvm/lapic.h       |  2 ++
 arch/x86/kvm/vmx.c         | 33 ++++++++++++++++++++++++++++++++-
 4 files changed, 51 insertions(+), 1 deletion(-)

diff --git a/arch/x86/include/asm/vmx.h b/arch/x86/include/asm/vmx.h
index e385df97bfdc..44c3f7eb4532 100644
--- a/arch/x86/include/asm/vmx.h
+++ b/arch/x86/include/asm/vmx.h
@@ -66,6 +66,7 @@
 #define EXIT_REASON_EPT_MISCONFIG       49
 #define EXIT_REASON_WBINVD              54
 #define EXIT_REASON_XSETBV              55
+#define EXIT_REASON_APIC_WRITE          56
 #define EXIT_REASON_INVPCID             58
 
 #define VMX_EXIT_REASONS \
@@ -141,6 +142,7 @@
 #define SECONDARY_EXEC_ENABLE_VPID              0x00000020
 #define SECONDARY_EXEC_WBINVD_EXITING		0x00000040
 #define SECONDARY_EXEC_UNRESTRICTED_GUEST	0x00000080
+#define SECONDARY_EXEC_APIC_REGISTER_VIRT       0x00000100
 #define SECONDARY_EXEC_PAUSE_LOOP_EXITING	0x00000400
 #define SECONDARY_EXEC_ENABLE_INVPCID		0x00001000
 
diff --git a/arch/x86/kvm/lapic.c b/arch/x86/kvm/lapic.c
index 9392f527f107..0664c138e860 100644
--- a/arch/x86/kvm/lapic.c
+++ b/arch/x86/kvm/lapic.c
@@ -1212,6 +1212,21 @@ void kvm_lapic_set_eoi(struct kvm_vcpu *vcpu)
 }
 EXPORT_SYMBOL_GPL(kvm_lapic_set_eoi);
 
+/* emulate APIC access in a trap manner */
+void kvm_apic_write_nodecode(struct kvm_vcpu *vcpu, u32 offset)
+{
+	u32 val = 0;
+
+	/* hw has done the conditional check and inst decode */
+	offset &= 0xff0;
+
+	apic_reg_read(vcpu->arch.apic, offset, 4, &val);
+
+	/* TODO: optimize to just emulate side effect w/o one more write */
+	apic_reg_write(vcpu->arch.apic, offset, val);
+}
+EXPORT_SYMBOL_GPL(kvm_apic_write_nodecode);
+
 void kvm_free_lapic(struct kvm_vcpu *vcpu)
 {
 	struct kvm_lapic *apic = vcpu->arch.apic;
diff --git a/arch/x86/kvm/lapic.h b/arch/x86/kvm/lapic.h
index e5ebf9f3571f..9a8ee22bc7a3 100644
--- a/arch/x86/kvm/lapic.h
+++ b/arch/x86/kvm/lapic.h
@@ -64,6 +64,8 @@ int kvm_lapic_find_highest_irr(struct kvm_vcpu *vcpu);
 u64 kvm_get_lapic_tscdeadline_msr(struct kvm_vcpu *vcpu);
 void kvm_set_lapic_tscdeadline_msr(struct kvm_vcpu *vcpu, u64 data);
 
+void kvm_apic_write_nodecode(struct kvm_vcpu *vcpu, u32 offset);
+
 void kvm_lapic_set_vapic_addr(struct kvm_vcpu *vcpu, gpa_t vapic_addr);
 void kvm_lapic_sync_from_vapic(struct kvm_vcpu *vcpu);
 void kvm_lapic_sync_to_vapic(struct kvm_vcpu *vcpu);
diff --git a/arch/x86/kvm/vmx.c b/arch/x86/kvm/vmx.c
index 02eeba86328d..5ad7c8531083 100644
--- a/arch/x86/kvm/vmx.c
+++ b/arch/x86/kvm/vmx.c
@@ -84,6 +84,9 @@ module_param(vmm_exclusive, bool, S_IRUGO);
 static bool __read_mostly fasteoi = 1;
 module_param(fasteoi, bool, S_IRUGO);
 
+static bool __read_mostly enable_apicv_reg = 1;
+module_param(enable_apicv_reg, bool, S_IRUGO);
+
 /*
  * If nested=1, nested virtualization is supported, i.e., guests may use
  * VMX and be a hypervisor for its own guests. If nested=0, guests may not
@@ -764,6 +767,12 @@ static inline bool cpu_has_vmx_virtualize_apic_accesses(void)
 		SECONDARY_EXEC_VIRTUALIZE_APIC_ACCESSES;
 }
 
+static inline bool cpu_has_vmx_apic_register_virt(void)
+{
+	return vmcs_config.cpu_based_2nd_exec_ctrl &
+		SECONDARY_EXEC_APIC_REGISTER_VIRT;
+}
+
 static inline bool cpu_has_vmx_flexpriority(void)
 {
 	return cpu_has_vmx_tpr_shadow() &&
@@ -2540,7 +2549,8 @@ static __init int setup_vmcs_config(struct vmcs_config *vmcs_conf)
 			SECONDARY_EXEC_UNRESTRICTED_GUEST |
 			SECONDARY_EXEC_PAUSE_LOOP_EXITING |
 			SECONDARY_EXEC_RDTSCP |
-			SECONDARY_EXEC_ENABLE_INVPCID;
+			SECONDARY_EXEC_ENABLE_INVPCID |
+			SECONDARY_EXEC_APIC_REGISTER_VIRT;
 		if (adjust_vmx_controls(min2, opt2,
 					MSR_IA32_VMX_PROCBASED_CTLS2,
 					&_cpu_based_2nd_exec_control) < 0)
@@ -2551,6 +2561,11 @@ static __init int setup_vmcs_config(struct vmcs_config *vmcs_conf)
 				SECONDARY_EXEC_VIRTUALIZE_APIC_ACCESSES))
 		_cpu_based_exec_control &= ~CPU_BASED_TPR_SHADOW;
 #endif
+
+	if (!(_cpu_based_exec_control & CPU_BASED_TPR_SHADOW))
+		_cpu_based_2nd_exec_control &= ~(
+				SECONDARY_EXEC_APIC_REGISTER_VIRT);
+
 	if (_cpu_based_2nd_exec_control & SECONDARY_EXEC_ENABLE_EPT) {
 		/* CR3 accesses and invlpg don't need to cause VM Exits when EPT
 		   enabled */
@@ -2748,6 +2763,9 @@ static __init int hardware_setup(void)
 	if (!cpu_has_vmx_ple())
 		ple_gap = 0;
 
+	if (!cpu_has_vmx_apic_register_virt())
+		enable_apicv_reg = 0;
+
 	if (nested)
 		nested_vmx_setup_ctls_msrs();
 
@@ -3829,6 +3847,8 @@ static u32 vmx_secondary_exec_control(struct vcpu_vmx *vmx)
 		exec_control &= ~SECONDARY_EXEC_UNRESTRICTED_GUEST;
 	if (!ple_gap)
 		exec_control &= ~SECONDARY_EXEC_PAUSE_LOOP_EXITING;
+	if (!enable_apicv_reg || !irqchip_in_kernel(vmx->vcpu.kvm))
+		exec_control &= ~SECONDARY_EXEC_APIC_REGISTER_VIRT;
 	return exec_control;
 }
 
@@ -4787,6 +4807,16 @@ static int handle_apic_access(struct kvm_vcpu *vcpu)
 	return emulate_instruction(vcpu, 0) == EMULATE_DONE;
 }
 
+static int handle_apic_write(struct kvm_vcpu *vcpu)
+{
+	unsigned long exit_qualification = vmcs_readl(EXIT_QUALIFICATION);
+	u32 offset = exit_qualification & 0xfff;
+
+	/* APIC-write VM exit is trap-like and thus no need to adjust IP */
+	kvm_apic_write_nodecode(vcpu, offset);
+	return 1;
+}
+
 static int handle_task_switch(struct kvm_vcpu *vcpu)
 {
 	struct vcpu_vmx *vmx = to_vmx(vcpu);
@@ -5721,6 +5751,7 @@ static int (*const kvm_vmx_exit_handlers[])(struct kvm_vcpu *vcpu) = {
 	[EXIT_REASON_VMON]                    = handle_vmon,
 	[EXIT_REASON_TPR_BELOW_THRESHOLD]     = handle_tpr_below_threshold,
 	[EXIT_REASON_APIC_ACCESS]             = handle_apic_access,
+	[EXIT_REASON_APIC_WRITE]              = handle_apic_write,
 	[EXIT_REASON_WBINVD]                  = handle_wbinvd,
 	[EXIT_REASON_XSETBV]                  = handle_xsetbv,
 	[EXIT_REASON_TASK_SWITCH]             = handle_task_switch,
-- 
2.41.0

```