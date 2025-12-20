---
layout: post
title:  "unrestricted guests"
author: fuqiang
date:   2024-04-25 11:21:00 +0800
categories: [intel_sdm]
tags: [virt]
---

> FROM intel sdm
> ```
> CHAPTER 26 VMX NON-ROOT OPERATION
>   26.6 UNRESTRICTED GUESTS
> ```

The first processors to support VMX operation require CR0.PE and CR0.PG to be 1
in VMX operation (see Section 24.8). This restriction implies that guest
software cannot be run in unpaged protected mode or in real-address mode. Later
processors support a VM-execution control called “unrestricted
guest”.<sup>1</sup>If this control is 1, CR0.PE and CR0.PG may be 0 in VMX
non-root operation. Such processors allow guest software to run in unpaged
protected mode or in real-address mode. The following items describe the
behavior of such software:

> 第一个支持 VMX operation 的处理器要求 CR0.PE 和 CR0.PG 在 VMX operation中为 1
> （参见第 24.8 节）。 此限制意味着guest软件不能在未分页保护模式或实地址模式下运行。
> 更高版本的处理器支持称为“unrestricted guest”的 VM-execution control。<sup>1</sup>
> 如果此控制字段为 1，则在 VMX non-root operation中 CR0.PE 和 CR0.PG 可能为 0。
> 此类处理器允许guest软件在未分页保护模式或实地址模式下运行。 以下各项描述了此类软件
> 的行为：

* The MOV CR0 instructions does not cause a general-protection exception simply
  because it would set either CR0.PE and CR0.PG to 0. See Section 26.3 for
  details.
  > MOV CR0 指令不会仅仅因为将 CR0.PE 和 CR0.PG 设置为 0 而导致一般保护异常。
  > 有关详细信息，请参见第 26.3 节。

* A logical processor treats the values of CR0.PE and CR0.PG in VMX non-root
  operation just as it does outside VMX operation. Thus, if CR0.PE = 0, the
  processor operates as it does normally in real-address mode (for example, it
  uses the 16-bit interrupt table to deliver interrupts and exceptions). If
  CR0.PG = 0, the processor operates as it does normally when paging is
  disabled.
  > 逻辑处理器在 VMX non-root operation中处理 CR0.PE 和 CR0.PG 的值，就像在 
  > VMX operation 之外一样。 因此，如果 CR0.PE = 0，处理器将像正常在实地址模式
  > 下一样运行（例如，它使用 16 位中断表来传递中断和异常）。 如果 CR0.PG = 0，
  > 则处理器在禁用分页时将正常运行。

* Processor operation is modified by the fact that the processor is in VMX
  non-root operation and by the settings of the VM-execution controls just as
  it is in protected mode or when paging is enabled. Instructions, interrupts,
  and exceptions that cause VM exits in protected mode or when paging is
  enabled also do so in real-address mode or when paging is disabled. The
  following examples should be noted:
  > ```
  > the fact that: ...的事实, 确切的说, 事实上, 实际上
  > ```
  > 处理器 operation 是由处理器处于VMX non-root operation 以及 VM-executioni controls 
  > 的设置来修改的(这个翻译不通)，就像它处于保护模式或启用分页时一样。在保护模式下或
  > 启用分页时导致VM退出的指令、中断和异常在实际地址模式下或禁用分页时也会这样做。应注
  > 意以下示例：
  >
  >> 这里实际上是想表明, 在VMX non-root operation 下的行为由 VM-execution controls 
  >> 控制, 和guest处于什么mode无关(protect ?  paging?)
  >{: .prompt-tip}

  + If CR0.PG = 0, page faults do not occur and thus cannot cause VM exits.
    > 如果CR0.PG=0，则不会发生page fault，因此不会导致VM exit。

  + If CR0.PE = 0, invalid-TSS exceptions do not occur and thus cannot cause VM
    exits.
    > 如果CR0.PE=0，则不会发生invalid-TSS exception，因此不会导致VM exits。

  + If CR0.PE = 0, the following instructions cause invalid-opcode exceptions
    and do not cause VM exits: INVEPT, INVVPID, LLDT, LTR, SLDT, STR, VMCLEAR,
    VMLAUNCH, VMPTRLD, VMPTRST, VMREAD, VMRESUME, VMWRITE, VMXOFF, and VMXON.
    > 如果CR0.PE=0，则以下指令会导致 invalid-opcode 异常，并且不会导致VM exit：
    > ...

* If CR0.PG = 0, each linear address is passed directly to the EPT mechanism
  for translation to a physical address.<sup>2</sup> The guest memory type
  passed on to the EPT mechanism is WB (writeback).
  > 如果CR0.PG=0，则每个线性地址都直接传递给EPT机制，用于转换为物理地址。<sup>2</sup>
  > 传递到EPT机制的guest memory type 为WB（写回）。


> 1. "Unrestricted guest” is a secondary processor-based VM-execution control. If
>    bit 31 of the primary processor-based VM-execution controls is 0, VMX
>    non-root operation functions as if the “unrestricted guest” VM-execution
>    control were 0. See Section 25.6.2.
>    > "unrestricted guest" 是 secondary processor-based VM-execution 控制字段. 
>    > 如果 primary processor-based VM-execution controls 的bit 31 为1. VMX non-root
>    > operation 的function 就像“unrestricted guests”VM-execution control 为0一样。
>    > 请看Section 25.6.2.
> 
> 2. As noted in Section 27.2.1.1, the “enable EPT” VM-execution control must be
>    1 if the “unrestricted guest” VM-execution control is 1.
>    > 如Section 27.2.1.1 提到的, 如果 "unrestricted guest" VM-execution 控制字段为1, 
>    > "enable EPT" VM-execution 控制字段也必须是1.
