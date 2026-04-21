---
layout: post
title:  "restrictions of VMX operation"
author: fuqiang
date:   2024-04-25 11:11:00 +0800
categories: [intel_sdm]
tags: [virt]
---

> FROM
>
> intel sdm
> ```
> CHAPTER 24 INTRODUCTION TO VIRTUAL MACHINE EXTENSIONS
>   24.8 RESTRICTIONS ON VMX OPERATION
> ```

VMX operation places restrictions on processor operation. These are detailed
below:

> VMX operation 对处理器操作施加限制。 这些详细信息如下： 

* In VMX operation, processors may fix certain bits in CR0 and CR4 to specific
  values and not support other values. VMXON fails if any of these bits
  contains an unsupported value (see “VMXON—Enter VMX Operation” in Chapter
  31). Any attempt to set one of these bits to an unsupported value while in
  VMX operation (including VMX root operation) using any of the CLTS, LMSW, or
  MOV CR instructions causes a general-protection exception. VM entry or VM
  exit cannot set any of these bits to an unsupported value. Software should
  consult the VMX capability MSRs IA32_VMX_CR0_FIXED0 and IA32_VMX_CR0_FIXED1
  to determine how bits in CR0 are fixed (see Appendix A.7). For CR4, software
  should consult the VMX capability MSRs IA32_VMX_CR4_FIXED0 and
  IA32_VMX_CR4_FIXED1 (see Appendix A.8).
  > 在VMX operation中，处理器可以将CR0和CR4中的某些位fix(固定, 相当于不能修改)为特定值并且
  > 不支持其他值。 如果这些位中的任何一个包含不支持的值，则 VMXON 失败（请参阅第 31 
  > 章中的“VMXON — Enter VMX opeartion”）。 在 VMX operation（包括 VMX root opeartion）中
  > 使用任何 CLTS、LMSW 或 MOV CR 指令将这些位之一设置为不受支持的值的任何尝试都会导致
  > 一般保护异常。 VM entry 或 VM exit无法将这些位中的任何一个设置为不受支持的值。
  > 软件应参考 VMX 功能 MSR IA32_VMX_CR0_FIXED0 和 IA32_VMX_CR0_FIXED1 以确定如
  > 何fix CR0 中的位（请参阅附录 A.7）。 对于 CR4，软件应参考 VMX 功能 
  > MSR IA32_VMX_CR4_FIXED0 和 IA32_VMX_CR4_FIXED1（请参阅附录 A.8）。

  > NOTES
  >
  > The first processors to support VMX operation require that the following
  > bits be 1 in VMX operation: CR0.PE, CR0.NE, CR0.PG, and CR4.VMXE. The
  > restrictions on CR0.PE and CR0.PG imply that VMX operation is supported
  > only in paged protected mode (including IA-32e mode). Therefore, guest
  > software cannot be run in unpaged protected mode or in real-address mode.
  >
  > > 第一批支持 VMX opeartion的处理器要求 VMX opeartion中以下位为 1：CR0.PE、
  > > CR0.NE、CR0.PG 和 CR4.VMXE。 对 CR0.PE 和 CR0.PG 的限制意味着仅在分页保护模式
  > > （包括 IA-32e 模式）下支持 VMX operation。 因此，guest软件不能在未分页保护模
  > > 式或实地址模式下运行。
  > 
  > Later processors support a VM-execution control called “unrestricted guest”
  > (see Section 25.6.2). If this control is 1, CR0.PE and CR0.PG may be 0 in
  > VMX non-root operation (even if the capability MSR IA32_VMX_CR0_FIXED0
  > reports otherwise).1 Such processors allow guest software to run in unpaged
  > protected mode or in real-address mode.
  >
  > > 更高版本的处理器支持称为“unrestricted guest”的 VM-execution control（请参
  > > 阅第 25.6.2 节）。 如果此控制字段为 1，则 CR0.PE 和 CR0.PG 在 VMX non-root 
  > > operation中可能为 0（即使 MSR IA32_VMX_CR0_FIXED0 功能另有报告）<sup>1</sup>。
  > > 此类处理器允许guest软件在未分页保护模式或实地址下运行 模式。

* VMXON fails if a logical processor is in A20M mode (see “VMXON—Enter VMX
  Operation” in Chapter 31). Once the processor is in VMX operation, A20M
  interrupts are blocked. Thus, it is impossible to be in A20M mode in VMX
  operation.
  > 如果逻辑处理器处于 A20M 模式，VMXON 将失败（请参阅第 31 章中的“VMXON—Enter
  > VMX opeartion”）。 一旦处理器处于 VMX opeartion 中，A20M 中断就会被阻止。 
  > 因此，在 VMX opeartion中不可能处于 A20M 模式。

* The INIT signal is blocked whenever a logical processor is in VMX root
  operation. It is not blocked in VMX non-root operation. Instead, INITs cause
  VM exits (see Section 26.2, “Other Causes of VM Exits”).
  > 只要逻辑处理器处于 VMX root operation中，INIT signal 就会被blocked。 在 VMX 
  > non-root opeartion中不会被block。 相反，INIT 会导致 VM exit（请参见第 26.2 节
  > “VM exit的其他原因”）。

* Intel(R) Processor Trace (Intel PT) can be used in VMX operation only if
  IA32_VMX_MISC[14] is read as 1 (see Appendix A.6). On processors that support
  Intel PT but which do not allow it to be used in VMX operation, execution of
  VMXON clears IA32_RTIT_CTL.TraceEn (see “VMXON—Enter VMX Operation” in
  Chapter 31); any attempt to write IA32_RTIT_CTL while in VMX operation
  (including VMX root operation) causes a general- protection exception.
  > 略(和 INTEL PT 技术相关)
  {: .prompt-warning}
