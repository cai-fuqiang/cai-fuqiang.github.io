---
layout: post
title:  "[arm] TrustZone"
author: fuqiang
date:   2025-08-13 09:39:00 +0800
categories: [coco,trustzone]
tags: [trustzone]
---

## What is TrustZone?

TrustZone is the name of the Security architecture in the Arm A-profile
architecture. First introduced in Armv6K, TrustZone is also supported in Armv7-A
and Armv8-A. TrustZone provides two execution environments with system-wide
hardware enforced isolation between them, as shown in this diagram:

> TrustZone 是 Arm A-profile 架构中的安全架构名称。TrustZone 首次在 Armv6K 中引
> 入，并且在 Armv7-A 和 Armv8-A 中也得到了支持。TrustZone 提供了两个执行环境，并
> 在系统范围内通过硬件强制实现它们之间的隔离，如下图所示：
{: .prompt-trans}

![Normal and Trusted world](./pic/normal_and_trusted_world.svg)

The Normal world runs a rich software stack. This software stack typically
includes a large application set, a complex operating system like Linux, and
possibly a hypervisor. Such software stacks are large and complex. While efforts
can be made to secure them, the size of the attack surface means that they are
more vulnerable to attack.

> 普通世界（Normal world）运行着丰富的软件栈。这个软件栈通常包括大量的应用程序、
> 一个复杂的操作系统（如 Linux），以及可能存在的虚拟机管理器（hypervisor）。这样
> 的软件栈庞大且复杂。尽管可以采取措施来提升其安全性，但由于攻击面较大，它们更容
> 易受到攻击。
{: .prompt-trans}

The Trusted world runs a smaller and simpler software stack, which is referred
to as a Trusted Execution Environment (TEE). Typically, a TEE includes several
Trusted services that are hosted by a lightweight kernel. The Trusted services
provide functionality like key management. This software stack has a
considerably smaller attack surface, which helps reduce vulnerability to attack.

> 受信任世界（Trusted world）运行着更精简、更简单的软件栈，这被称为受信任执行环
> 境（Trusted Execution Environment，TEE）。通常，TEE 包含由轻量级内核托管的若干
> 受信任服务。这些受信任服务提供诸如密钥管理等功能。这样的软件栈攻击面要小得多，
> 从而有助于降低遭受攻击的风险。
{: .prompt-trans}

> Note
> 
> You might sometimes see the term Rich Execution Environment (REE) used to
> describe the software that is running in the Normal world.
>
> > 你有时可能会看到“富执行环境（Rich Execution Environment，REE）”这个术语，用来
> > 描述运行在普通世界（Normal world）中的软件。
> {: .prompt-trans}

TrustZone aims to square a circle. As users and developers, we want the rich
feature set and flexibility of the Normal world. At the same time, we want the
higher degrees of trust that it is possible to achieve with a smaller and more
restricted software stack in the Trusted world. TrustZone gives us both,
providing two environments with hardware-enforced isolation between them.

> TrustZone 旨在实现看似矛盾的需求。作为用户和开发者，我们既希望拥有普通世界所带
> 来的丰富功能和灵活性，同时又希望获得受信任世界中通过更小、更受限制的软件栈所能
> 实现的更高程度的信任。TrustZone 让我们两者兼得，提供了两个通过硬件强制隔离的执
> 行环境。
{: .prompt-trans}

### TrustZone for Armv8-M

TrustZone is also used to refer the Security Extensions in the Armv8-M
architecture. While there are similarities between TrustZone in the A profile
architecture and the M profile architecture, there are also important
differences. This guide covers the A profile only.

> ```
> refer: 指代，取代
> ```
>
> TrustZone 也用于指代 Armv8-M 架构中的安全扩展。虽然 A profile 架构中的
> TrustZone 与 M profile 架构中的 TrustZone 有一些相似之处，但也存在重要的区别。
> 本指南仅涵盖 A profile 架构。
{: .prompt-trans}

### Armv9-A Realm Management Extension

The Armv9-A Realm Management Extension (RME) extends the concepts supported by
TrustZone. This guide does not cover RME, but you can find more information in
the Realm Management Extension Guide.

> Armv9-A 的 Realm 管理扩展（RME）扩展了 TrustZone 支持的相关概念。本指南不涉及
> RME，但你可以在《Realm 管理扩展指南》中获取更多信息。
{: .prompt-trans}

## TrustZone in the processor

In this topic, we discuss support for TrustZone within the processor. Other
sections cover support in the memory system and the software story that is built
on the processor and memory system support.

> 在本主题中，我们将讨论处理器对 TrustZone 的支持。其他章节将介绍内存系统中的支
> 持，以及基于处理器和内存系统支持构建的软件方案。
{: .prompt-trans}

### Security States

In the Arm architecture, there are two Security states: Secure and Non-secure.
These Security states map onto the Trusted and Normal worlds that we referred to
in What is TrustZone?

> 在 Arm 架构中，存在两种安全状态：安全（Secure）和非安全（Non-secure）。这些安
> 全状态分别对应于我们在“什么是 TrustZone？”中提到的受信任世界（Trusted world）
> 和普通世界（Normal world）。
{: .prompt-trans}

> Note
>
> In Armv9-A, if the Realm Management Extension (RME) is implemented, then there
> are two extra Security states. This guide does not cover the change introduced
> by RME, for more information on RME, see Realm Management Extension Guide.
>
> > 在 Armv9-A 架构中，如果实现了 Realm 管理扩展（RME），那么还会有两个额外的安全
> > 状态。本指南不涉及 RME 所带来的变化，关于 RME 的更多信息，请参阅《Realm 管理扩展
> > 指南》。
> {: .prompt-trans}

At EL0, EL1, and EL2 the processor can be in either Secure state or Non-secure
state, which is controlled by the SCR_EL3.NS bit. You often see this written as:

> 在 EL0、EL1 和 EL2 级别，处理器可以处于安全状态（Secure state）或非安全状态
> （Non-secure state），这一状态由 SCR_EL3.NS 位控制。你经常会看到这样的表述：
{: .prompt-trans}

* NS.EL1: Non-secure state, Exception level 1
* S.EL1: Secure state, Exception level 1

EL3 is always in Secure state, regardless of the value of the SCR_EL3.NS bit.
The arrangement of Security states and Exception levels is shown here:

> 无论 SCR_EL3.NS 位的取值如何，EL3 总是处于安全状态（Secure state）。安全状态和
> 异常级别的对应关系如下图所示：
{: .prompt-trans}

Figure 1. Non-secure and Secure state

![Non-secure and Secure state](./pic/non_s_and_s_state.svg)

> Note
>
> Support for Secure EL2 was first introduced in Armv8.4 - A and support remains
> optional in Armv8-A.

### Switching between Security states

If the processor is in NS.EL1 and software wants to move into S.EL1, how does it
do this?

> 如果处理器当前处于 NS.EL1，且软件希望切换到 S.EL1，该如何实现？
{: .prompt-trans}

To change Security state, in either direction, execution must pass through EL3,
as shown in the following diagram:

> 无论是从非安全状态切换到安全状态，还是反向切换，都必须经过 EL3。如下图所示，只
> 有通过 EL3，才能改变安全状态。
{: .prompt-trans}

<center><font><strong> Figure 1. Change security state</strong></font></center>

![Change security state](./pic/change_s_state.svg)

The preceding diagram shows an example sequence of the steps that are involved
in moving between Security states. Taking these one step at a time:

> 上面的图展示了在不同安全状态之间切换时涉及的步骤序列，下面我们一步一步来看：
{: .prompt-trans}


* Entering a higher Exception level requires an exception. Typically, this
  exception would be an FIQ or an SMC (Secure Monitor Call) exception. We look at
  interrupt handling and SMCs in more detail later.
* EL3 is entered at the appropriate exception vector. Software that is running in
  EL3 toggles the SCR_EL3.NS bit.
* An exception return then takes the processor from EL3 to S.EL1.

> * 进入更高的异常级别需要触发一个异常。通常，这个异常会是 FIQ 或 SMC（安全监控
>   调用，Secure Monitor Call）异常。我们将在后文更详细地介绍中断处理和 SMC。
> * 处理器通过相应的异常向量进入 EL3。在 EL3 运行的软件会切换 SCR_EL3.NS 位。
> * 异常返回后，处理器从 EL3 进入 S.EL1。
{: .prompt-trans}

There is more to changing Security state than just moving between the Exception
levels and changing the SCR_EL3.NS bit. We also must consider processor state.

> 实际上，切换安全状态不仅仅是切换异常级别和更改 SCR_EL3.NS 位，还需要考虑处理器
> 的状态。
{: .prompt-trans}

There is only one copy of the vector registers, the general-purpose registers,
and most System registers. When moving between Security states it is the
responsibility of software, not hardware, to save and restore register state. By
convention, the piece of software that does this is called the Secure Monitor.
This makes our earlier example look more like what you can see in the following
diagram:

> 向量寄存器、通用寄存器以及大多数系统寄存器都只有一份。当在安全状态之间切换时，
> 保存和恢复寄存器状态是软件的责任，而不是硬件的责任。按照惯例，负责这一工作的软
> 件被称为安全监控器（Secure Monitor）。这样，我们之前的例子实际上更接近下图所示
> 的流程。
{: .prompt-trans}

<center><font><strong>
Figure 2. Secure Monitor
</strong></font></center>

![Secure Monitor](./pic/s_monitor.svg)

Trusted Firmware, an open-source project that Arm sponsors, provides a reference
implementation of a Secure Monitor. We will discuss Trusted Firmware later in
the guide.

> Trusted Firmware 是 Arm 赞助的一个开源项目，提供了安全监控器（Secure Monitor）
> 的参考实现。我们将在本指南后面讨论 Trusted Firmware。
{: .prompt-trans}

A small number of registers are banked by Security state. This means that there
are two copies of the register, and the core automatically uses the copy that
belongs to the current Security state. These registers are limited to the ones
for which the processor needs to know both settings at all times. An example is
ICC_BPR1_EL1, a GIC register that is used to control interrupt preemption.
Banking is the exception, not the rule, and will be explicitly called out in the
Architecture Reference Manual for your processor.

> 只有少量寄存器会根据安全状态进行分组（banked）。这意味着这些寄存器有两份拷贝，
> 处理器会自动使用当前安全状态对应的那一份。这类寄存器仅限于处理器需要始终同时知
> 道两种设置的情况。例如，ICC_BPR1_EL1 是一个 GIC 寄存器，用于控制中断抢占。寄存
> 器分组是特例而不是常规做法，并且会在你的处理器的架构参考手册中明确说明。
{: .prompt-trans}

When a System register is banked, we use (S) and (NS) to identify which copy we
are referring to. For example,

> 当系统寄存器是分组（banked）时，我们会用 (S) 和 (NS) 来标识我们指的是哪一份。
> 例如：

```
ICC_BPR1_ EL1 (S) and ICC_BPR1_EL1 (NS).
```

> NOTE
>
> In Armv6 and Armv7 - A most System registers are banked by Security state, but
> general- purpose registers and vector registers are still common.
>
>> 在 Armv6 和 Armv7-A 架构中，大多数系统寄存器会根据安全状态进行分组（banked），
>> 但通用寄存器和向量寄存器仍然是共用的。
>{: .prompt-trans}

### Virtual address spaces

The memory management guide in this series introduced the idea of multiple
virtual address spaces, or translation regimes. For example, there is a
translation regime for EL0/1 and a separate translation regime for EL2, shown
here:

> ```
> regime : 制度；规则
> ```
>
> 本系列的内存管理指南介绍了多虚拟地址空间（multiple virtual address spaces）或
> 称为转换机制（translation regimes）的概念。例如，EL0/1 有一种转换机制，EL2 则
> 有单独的转换机制，如下所示：
{: .prompt-trans}

<center><font><strong>
Figure 1. Virtual address spaces
</strong></font></center>

![vas](./pic/vas.svg)

There are also separate translation regimes for the Secure and Non-secure
states. For example, there is a Secure EL0/1 translation regime and Non-secure
EL0/1 translation regime, which is shown here:

> 安全状态（Secure）和非安全状态（Non-secure）也分别拥有独立的转换机制。例如，存
> 在安全 EL0/1 的转换机制和非安全 EL0/1 的转换机制，如下所示：
{: .prompt-trans}

<center><font><strong>
Figure 2. Secure EL0/1 translation regime and Non-secure EL0/1 translation regime

图2. 安全 EL0/1 转换机制与非安全 EL0/1 转换机制
</strong></font></center>

![es_el01_and_s_el01](./pic/es_el01_and_s_el01.svg)

When writing addresses, it is convention to use prefixes to identify which
translation regime is being referred to:

> 在书写地址时，通常使用前缀来标识所指的转换机制：
{: .prompt-trans}

* NS.EL1:0x8000 - Virtual address 0x8000 in the Non-secure EL0/1 translation regime
* S.EL1:0x8000 - Virtual address 0x8000 in the Secure EL0/1 translation regime

It is important to note that S.EL1:0x8000 and NS.EL1:0x8000 are two different
and independent virtual addresses. The processor does not use a NS.EL1
translation while in Secure state, or a S.EL1 translation while in Non-secure
state.

> 需要注意的是，S.EL1:0x8000 和 NS.EL1:0x8000 是两个不同且独立的虚拟地址。处理器
> 在安全状态下不会使用 NS.EL1 的转换机制，在非安全状态下也不会使用 S.EL1 的转换
> 机制。
{: .prompt-trans}

### Physical address spaces

In addition to two Security states, the architecture provides two physical
address spaces: Secure and Non-secure.

> 除了两种安全状态之外，Arm 架构还提供了两种物理地址空间：安全（Secure）和非安全
> （Non-secure）。
{: .prompt-trans}

While in Non-secure state, virtual addresses always translate to Non-secure
physical addresses. This means that software in Non-secure state can only see
Non-secure resources, but can never see Secure resources. This is illustrated
here:

> 在非安全状态下，虚拟地址总是被转换为非安全物理地址。这意味着，处于非安全状态的
> 软件只能访问非安全资源，无法访问安全资源。如下图所示
{: .prompt-trans}

<center><font><strong>
Figure 1. Physical address spaces
</strong></font></center>

![Physical address spaces](./pic/pas.svg)

While in Secure state, software can access both the Secure and Non-secure
physical address spaces. The NS bit in the translation table entries controls
which physical address space a block or page of virtual memory translates to, as
shown in the following diagram:

> 在安全状态下，软件可以访问安全和非安全两种物理地址空间。转换表项中的 NS 位用于
> 控制虚拟内存的某个块或页应被转换到哪个物理地址空间，如下图所示：
{: .prompt-trans}

<center><font><strong>
Figure 2. NS bit
</strong></font></center>

![NS bit](./pic/ns_bit.svg)

> Note
>
> In Secure state, when the Stage 1 MMU is disabled all addresses are treated as
> Secure.
>
> > 在安全状态下，如果一级 MMU 被禁用，所有地址都会被视为安全地址。
> {: .prompt-trans}
> > 相当于在实模式下, 用物理地址访问，所有的地址都被看作安全地址
> {: .prompt-tip}

Like with virtual addresses, typically prefixes are used to identify which
address space is being referred to. For physical addresses, these prefixes are
NP: and SP:. For example:

> 与虚拟地址类似，物理地址通常也使用前缀来标识所指的地址空间。对于物理地址，这些
> 前缀是 NP: 和 SP:。例如：
{: .prompt-trans}

* NP:0x8000 – Address 0x8000 in the Non-secure physical address space
* SP:0x8000 – Address 0x8000 in the Secure physical address space

It is important to remember that Secure and Non-secure are different address
spaces, not just an attribute like readable or writable. This means that NP:
0x8000 and SP:0x8000 in the preceding example are different memory locations and
are treated as different memory locations by the processor.

> 需要注意的是，安全（Secure）和非安全（Non-secure）是不同的地址空间，而不仅仅是
> 类似“可读”或“可写”的一种属性。这意味着在前面的例子中，NP:0x8000 和 SP:0x8000
> 是两个不同的内存位置，处理器也会将它们视为不同的内存位置。
{: .prompt-trans}

> Note
>
> It can helpful to think of the address space as an extra address bit on the
> bus.
>> 可以将地址空间理解为总线上的一个额外地址位。

If the Armv9-A Realm Management Extension (RME) is implemented, the number of
physical address spaces increases to four. The extra physical address spaces are
Root and Realm. Software running in Secure state can still only access the
Non-secure and Secure physical address spaces. For more information on RME, see
Realm Management Extension Guide.

> 如果实现了 Armv9-A 的 Realm 管理扩展（RME），物理地址空间的数量会增加到四个。
> 新增的物理地址空间是 Root 和 Realm。运行在安全状态下的软件仍然只能访问非安全和
> 安全物理地址空间。关于 RME 的更多信息，请参阅《Realm 管理扩展指南》。
{: .prompt-trans}

### Data, instruction, and unified caches

In the Arm architecture, data caches are physically tagged. The physical address
includes which address space the line is from, shown here:

> 在 Arm 架构中，数据缓存是按物理方式标记的。物理地址中包含了该缓存行所属的地址
> 空间，如下所示：
{: .prompt-trans}

<center><font><strong>
Figure 1. Data-caches
</strong></font></center>

![Data-caches](./pic/data_caches.svg)

A cache lookup on NP:0x800000 never hits on a cache line that is tagged with SP:
0x800000. This is because NP:0x800000 and SP:0x800000 are different addresses.

> 对 NP:0x800000 进行缓存查找时，永远不会命中标记为 SP:0x800000 的缓存行。这是因
> 为 NP:0x800000 和 SP:0x800000 是不同的地址。
{: .prompt-trans}

This also affects cache maintenance operations. Consider the example data cache
in the preceding diagram. If the virtual address va1 maps to physical address
0x800000, what happens when software issues DC IVAC, va1 (Data or unified Cache
line Invalidate by Virtual Address) from Non-secure state?

> 这同样会影响缓存维护操作。以前面图中的数据缓存为例，如果虚拟地址 va1 映射到物
> 理地址 0x800000，当软件在非安全状态下执行 DC IVAC, va1（按虚拟地址失效数据或统
> 一缓存行）时，会发生什么？
{: .prompt-trans}

The answer is that in Non-secure state, all virtual addresses translate to
Non-secure physical addresses. Therefore, va1 maps to NP:0x800000. The cache
only operates on the line containing the specified address, in this case NP:
0x800000. The line containing SP:0x800000 is unaffected.

> 案是，在非安全状态下，所有虚拟地址都会转换为非安全物理地址。因此，va1 映射到
> NP:0x800000。缓存只会对包含指定地址的缓存行进行操作，在本例中即 NP:0x800000。
> 包含 SP:0x800000 的缓存行不会受到影响。
{: .prompt-trans}

**Check your knowledge**

**If we performed the same operation from Secure state, with va1 still mapping to
NP:0x800000, which caches lines are affected?**

> 如果我们在安全状态下执行相同的操作，va1 仍然映射到 NP:0x800000，那么哪些缓存行
> 会受到影响？
{: .prompt-trans}

Like in the earlier example, the cache invalidates the line containing the
specified physical address, NP:0x800000. The fact that the operation came from
Secure state does not matter.

> 和前面的例子一样，缓存会失效包含指定物理地址 NP:0x800000 的那一行。操作来自安
> 全状态这一事实并不会影响结果。
{: .prompt-trans}

Is it possible to perform a cache operation by virtual address from Non-secure
targeting a Secure line?

> 是否可以在非安全状态下，通过虚拟地址对安全缓存行执行缓存操作？
{: .prompt-trans}

No. In Non-secure state, virtual addresses can only ever map to Non-secure
physical addresses. By definition, a cache operation by VA from Non-secure state
can only ever target Non-secure lines.

> 不可以。在非安全状态下，虚拟地址只能映射到非安全物理地址。根据定义，通过虚拟地
> 址在非安全状态下进行的缓存操作只能作用于非安全缓存行。
{: .prompt-trans}

For set/way operations, for example DC ISW, Xt, operations that are issued in
Non-secure state will only affect lines containing Non-secure addresses. From
Secure state set/way operations affect lines containing both Secure and
Non-secure addresses.

> 对于组/路操作（如 DC ISW, Xt），在非安全状态下发起的操作只会影响包含非安全地址
> 的缓存行。而在安全状态下，组/路操作会影响包含安全和非安全地址的缓存行。
{: .prompt-trans}

This means that software can completely invalidate or clean the entire cache
only in Secure state. From Non-secure state, software can only clean or
invalidate Non-secure data.

> 这意味着，只有在安全状态下，软件才能完全失效或清除整个缓存；在非安全状态下，软
> 件只能清除或失效非安全数据。
{: .prompt-trans}

### Translation Look aside Buffer

Translation Look aside Buffer (TLBs) cache recently used translations. The
processor has multiple independent translation regimes. The TLB records which
translation regime, including the Security state, an entry represents. While the
structure of TLBs is implementation defined, the following diagram shows an
example:

> 转换后备缓冲区（Translation Lookaside Buffer，TLB）用于缓存最近使用的地址转换。
> 处理器拥有多个独立的转换机制。TLB 会记录每个条目所对应的转换机制，包括安全状态
> （Security state）。虽然 TLB 的具体结构由实现决定，但下图展示了一个示例：
{: .prompt-trans}

<center><font><strong>
Figure 1. Translation Lookaside Buffer (TLBs)
</strong></font></center>

![Translation Lookaside Buffer (TLBs)](./pic/tlb.svg)

When software issues a TLB invalidate operation (TLBI instruction) at EL1 or EL2,
the software targets the current Security state. Therefore, TLBI ALLE1 from
Secure state invalidates all cached entries for the S.EL0/1 translation regime.

> 当软件在 EL1 或 EL2 层级下发起 TLB 失效操作（TLBI 指令）时，操作对象是当前的安
> 全状态。因此，在安全状态下执行 TLBI ALLE1，会使 S.EL0/1 转换机制下所有缓存的条
> 目失效。
{: .prompt-trans}

EL3 is a special case. As covered earlier in Security states, when in EL0/1/2
the SCR_EL3.NS bit controls which Security state the processor is in. However,
EL3 is always in Secure state, regardless of the SCR_EL3.NS bit. When in EL3,
SCR_EL3.NS lets software control which Security state TLBIs operate on.

> EL3 是一个特殊情况。如前文所述，在 EL0/1/2 时，SCR_EL3.NS 位用于控制处理器所处
> 的安全状态。然而，无论 SCR_EL3.NS 位的值如何，EL3 始终处于安全状态。当处于 EL3
> 时，SCR_EL3.NS 位允许软件控制 TLB 失效操作作用于哪个安全状态。
{: .prompt-trans}

For example, executing TBLI ALLE1 at EL3 with:

* SCR_EL3.NS==0: Affects Secure EL0/1 translation regime
* SCR_EL3.NS==1: Affects Non-secure EL0/1 translation regime

### SMC exceptions

As part of the support for two Security states, the architecture includes the
Secure Monitor Call (SMC) instruction. Executing SMC causes a Secure Monitor
Call exception, which targets EL3.

> 作为对两种安全状态支持的一部分，Arm 架构引入了安全监控调用（Secure Monitor
> Call，SMC）指令。执行 SMC 会触发一个安全监控调用异常，该异常会进入 EL3 层级。
{: .prompt-trans}

SMC’s are normally used to request services, either from firmware resident in
EL3 or from a service that is hosted by the Trusted Execution Environment. The
SMC is initially taken to EL3, where an SMC dispatcher determines which entity
the call will be handled by. This is shown in the following diagram:

> SMC 通常用于请求服务，这些服务可能由驻留在 EL3 的固件提供，也可能由受信任执行
> 环境（Trusted Execution Environment）中的服务提供。SMC 指令首先会进入 EL3，在
> 那里由 SMC 分发器（dispatcher）决定由哪个实体处理该调用。如下图所示：
{: .prompt-trans}

<center><font><strong>
Figure 1. SMC dispatcher
</strong></font></center>

![SMC dispatcher](./pic/smc_dispatcher.svg)

In a bid to standardize interfaces, Arm provides the SMC Calling Convention
(DEN0028) and Power State Coordination Interface Platform Design Document
(DEN0022). These specifications lay out how SMCs are used to request services.

> 为了规范接口，Arm 提供了 SMC 调用约定（SMC Calling Convention，DEN0028）和电源
> 状态协调接口平台设计文档（Power State Coordination Interface Platform Design
> Document，DEN0022）。这些规范详细说明了如何通过 SMC 请求服务。
{: .prompt-trans}

Execution of an SMC at EL1 can be trapped to EL2. This is useful for hypervisors,
because hypervisors might want to emulate the firmware interface that is seen by
a virtual machine.

> 在 EL1 层级执行 SMC 指令时，可以被捕获到 EL2。这对于虚拟机管理器（hypervisor）
> 非常有用，因为 hypervisor 可能希望模拟虚拟机所看到的固件接口。
{: .prompt-trans}

> Note
>
> The SMC instruction is not available at EL0 in either Security state. We
> discuss exceptions later in Interrupts when we look at the interrupt
> controller.
>
> > 在任一安全状态下，EL0 都无法使用 SMC 指令。关于异常的内容，我们将在后续“中断”
> > 部分讨论中断控制器时再进行介绍。
> {: .prompt-trans}

### Secure virtualization

When virtualization was first introduced in Armv7-A, it was only added in the
Non-secure state. Until Armv8.3, the same was true for Armv8 as illustrated in
the following diagram:

> 在 Armv7-A 首次引入虚拟化时，虚拟化功能仅在非安全状态下实现。直到 Armv8.3 之前，
> Armv8 也是如此，如下图所示：
{: .prompt-trans}

<center><font><strong>
Figure 1. Secure virtualization
</strong></font></center>

![Secure virtualization](./pic/s_virt.svg)

As previously described in Switching between Security states, EL3 is used to
host firmware and the Secure Monitor. Secure EL0/1 host the Trusted Execution
Environment (TEE), which is made up of the Trusted services and kernel.

> 如前文《在安全状态之间切换》中所述，EL3 用于承载固件和安全监控器（Secure
> Monitor）。安全 EL0/1 运行受信任执行环境（TEE），该环境由受信任服务和内核组成。
{: .prompt-trans}


There was no perceived kkneed for multiple virtual machines in Secure state.
This means that support for virtualization was not necessary. As TrustZone
adoption increased, several requirements became apparent:

> 最初，人们认为在安全状态下不需要多个虚拟机。这意味着不需要为安全状态提供虚拟化
> 支持。随着 TrustZone 的广泛应用，几个新需求逐渐显现：
{: .prompt-trans}

Some trusted services were tied to specific trusted kernels. For a device to
support multiple services, it might need to run multiple trusted kernels.
Following the principle of running with least privilege, moving some of the
firmware functionality out of EL3 was required. The solution was to introduce
support for EL2 in Secure state, which came with Armv8.4-A, as you can see in
this diagram:

> 一些受信任服务与特定的受信任内核绑定。为了让设备支持多个服务，可能需要运行多个
> 受信任内核。遵循最小权限原则，需要将部分固件功能从 EL3 移出。为了解决这些需求，
> Armv8.4-A 在安全状态下引入了对 EL2 的支持，如下图所示：
{: .prompt-trans}

<center><font><strong>
Figure 2. Support for EL2 in Secure state
</strong></font></center>

![Support for EL2 in Secure state](./pic/support_el2_s_state.svg)

Rather than a full hypervisor, S.EL2 typically hosts a Secure Partition Manager
(SPM). An SPM allows the creation of the isolated partitions, which are unable
to see the resources of other partitions. A system could have multiple
partitions containing Trusted kernels and their Trusted services.

> 安全 EL2（S.EL2）通常不会运行完整的虚拟机管理器（hypervisor），而是承载安全分
> 区管理器（Secure Partition Manager，SPM）。SPM 允许创建隔离的分区，每个分区无
> 法访问其他分区的资源。这样，系统可以拥有多个分区，每个分区都包含受信任内核及其
> 受信任服务。
{: .prompt-trans}

A partition can also be created to house platform firmware, removing the need to
have that code that is run at EL3.

> 也可以创建一个分区来容纳平台固件，这样就不再需要让这些代码在 EL3 级别运行。
{: .prompt-trans}

* Enabling Secure EL2

  When S.EL2 is supported, it can be enabled or disabled. Whether S.EL2 is
  enabled is controlled by the SCR_EL3.EEL2 bit:

  > 当支持 S.EL2 时，它可以被使能或禁用。S.EL2 是否启用由 SCR_EL3.EEL2 位控制：
  {: .prompt-trans}

  + 0: S.EL2 disabled, behavior is as on a processor not supporting S.EL2
  + 1: S.EL2 enabled

* Stage 2 translation in Secure state

In Secure state, the Stage 1 translation of the Virtual Machine (VM) can output
both Secure and Non-secure addresses and is controlled by the NS bit in the
translation table descriptors. This results in two IPA spaces, Secure and
Non-secure, each with its own set of Stage 2 translation tables as you can see
in the following diagram:

> 在安全状态下，虚拟机（VM）的一级地址转换（Stage 1 translation）可以输出安全和
> 非安全地址，这由转换表描述符中的 NS 位进行控制。这样就产生了两个中间物理地址
> （IPA）空间：安全和非安全，每个空间都有自己的一套二级转换表（Stage 2
> translation tables），如下图所示：
{: .prompt-trans}

<center><font><strong>
Figure 3. Stage 2 translation in Secure state 
</strong></font></center>

![Stage 2 translation in Secure state](./pic/trans_in_s_state.svg)

Unlike the Stage 1 tables, there is no NS bit in the Stage 2 table entries. For
a given IPA space, all the translations either result in a Secure or Non-secure
physical address, which is controlled by a register bit. The Non-secure IPAs
translate to Non-secure PAs and the Secure IPAs translate to Secure PAs.

> 与一级转换表不同，二级转换表（Stage 2 table）项中没有 NS 位。对于某个特定的
> IPA 空间，所有的地址转换结果要么都是安全物理地址，要么都是非安全物理地址，这由
> 一个寄存器位进行控制。非安全 IPA 会被转换为非安全物理地址，安全 IPA 会被转换为
> 安全物理地址。
{: .prompt-trans}

## System architecture

So far in this guide, we have concentrated on the processor, but TrustZone is
much more than just a set of processor features. To take advantage of the
TrustZone features, we need support in the rest of the system as well.

> 到目前为止，本指南主要关注的是处理器，但 TrustZone 远不止是一组处理器特性。要
> 充分利用 TrustZone 的功能，系统的其他部分也需要相应的支持。
{: .prompt-trans}

Here is an example of a TrustZone-enabled system:

> 下面是一个支持 TrustZone 的系统示例：
{: .prompt-trans}

<center><font><strong>
Figure 1. System architecture
</strong></font></center>

![System  architecture](./pic/system_arch.svg)

### Completers: peripherals, and memories

Earlier in Physical address spaces we introduced the idea of two physical
address spaces, Secure and Non-secure. The processor exports the address space
that is being accessed to the memory system. The memory system uses this
information to enforce the isolation.

> 在前文“物理地址空间”部分，我们介绍了安全（Secure）和非安全（Non-secure）两种物
> 理地址空间的概念。处理器会将当前访问的地址空间类型传递给内存系统，内存系统则利
> 用这些信息来实现隔离。
{: .prompt-trans}

In this topic, we refer to bus Secure and bus Non-secure. Bus Secure means a bus
access to the Secure physical address space. Bus Non-secure means a bus access
to the Non-secure physical address space. Remember that in Secure state software
can access both physical address spaces. This means that the security of the bus
access is not necessarily the same as the Security state of the processor that
generated that access.

> 在本节中，我们提到总线安全（bus Secure）和总线非安全（bus Non-secure）。总线安
> 全指的是对安全物理地址空间的总线访问，总线非安全则指对非安全物理地址空间的总线
> 访问。请记住，在安全状态下，软件可以访问两种物理地址空间。这意味着总线访问的安
> 全属性不一定与发起访问的处理器的安全状态一致。
{: .prompt-trans}

> Note
>
> In AMBA AXI and ACE, the AxPROT[1] signal is used to specify which address
> space is being accessed. Like with the NS bit in the translation tables, 0
> indicates Secure and 1 indicates Non-secure.
> 
> > 在 AMBA AXI 和 ACE 总线协议中，AxPROT[1] 信号用于指定当前访问的是哪个物理地址
> > 空间。类似于转换表中的 NS 位，值为 0 表示安全，值为 1 表示非安全。
> {: .prompt-trans}

In theory, a system could have two entirely separate memory systems, using the
accessed physical address space (AxPROT) to select between them. In practice
this is unlikely. Instead, systems use the physical address space like an
attribute, controlling access to different devices in the memory system.

> 理论上，系统可以有两套完全独立的内存系统，通过访问的物理地址空间（AxPROT）来选
> 择使用哪一套。但实际中，这种做法并不常见。通常，系统会将物理地址空间作为一种属
> 性，用于控制对内存系统中不同设备的访问权限。
{: .prompt-trans}

In general, we can talk about two types of memories and peripherals, and bus
completers:
> 一般来说，我们可以将内存、外设和总线终端（completer）分为两类：
{: .prompt-trans}

* TrustZone aware

  This is a device that is built with some knowledge of TrustZone and uses the
  security of the access internally.

  An example is the Generic Interrupt Controller (GIC). The GIC is accessed by
  software in both Secure and Non-secure state. Non-secure accesses are only
  able to see Non-secure interrupts. Secure accesses can see all interrupts. The
  GIC implements uses the security of the bus transaction to determine which
  view to present.

  > 这类设备具备 TrustZone 相关的设计，能够在内部利用访问的安全属性。
  >
  > 一个例子是通用中断控制器（Generic Interrupt Controller, GIC）。GIC 可以被安
  > 全和非安全状态下的软件访问。非安全访问只能看到非安全中断，安全访问则可以看到
  > 所有中断。GIC 利用总线事务的安全属性来决定展示哪种视图。
  {: .prompt-trans}

* Non-TrustZone aware

  This represents most completers in a typical system. The device does not use
  the security of the bus access internally.

  > 这类设备占据了大多数典型系统中的终端。它们在内部不会利用总线访问的安全属性。
  {: .prompt-trans}

  An example is a simple peripheral like a timer, or an on-chip memory. Each
  would be either Secure or Non-secure, but not both.

  > 例如一个简单的外设（如定时器）或片上内存（on-chip memory），它们要么是安全的，
  > 要么是非安全的，但不会同时支持两种状态。
  {: .prompt-trans}


### Enforcing isolation

TrustZone is sometimes referred to as a completer-enforced protection system.
The requester signals the security of its access and the memory system decides
whether to allow the access. How is the memory system-based checking done?

> TrustZone 有时被称为“由终端强制保护的系统”（completer-enforced protection
> system）。请求方会发出其访问的安全属性信号，内存系统则决定是否允许该访问。那么，
> 内存系统是如何进行检查的呢？
{: .prompt-trans}

In most modern systems, the memory system-based checking is done by the
interconnect. For example, the Arm NIC-400 allows system designers to specify
for each connected completer:

> 在现代系统中，内存系统的检查通常由互连（interconnect）完成。例如，Arm 的
> NIC-400 互连允许系统设计者为每个连接的终端（completer）指定如下类型：
{: .prompt-trans}

* Secure

  Only Secure accesses are passed to device. Interconnect generates a fault for
  all Non-secure accesses, without the access being presented to the device.

  > 只有安全访问会被传递到设备。互连会对所有非安全访问直接产生错误（fault），而
  > 不会将该访问传递给设备。
  {: .prompt-trans}

* Non-secure

  Only Non-secure accesses are passed to device. Interconnect generates a fault
  for all Secure accesses, without the access being presented to the device.

  > 只有非安全访问会被传递到设备。互连会对所有安全访问直接产生错误，而不会将该访
  > 问传递给设备。
  {: .prompt-trans}

* Boot time configurable

  At boot time, system initialization software can program the device as Secure
  or Non-secure. The default is Secure.

  > 在系统启动时，初始化软件可以将设备配置为安全或非安全。默认配置为安全。
  {: .prompt-trans}

* TrustZone aware

  The interconnect allows all accesses through. The connected device must
  implement isolation.

  > 互连允许所有访问通过。连接的设备自身必须实现隔离机制。
  {: .prompt-trans}

For example:

<center><font><strong>
Figure 1. Implement isolation
</strong></font></center>

![Implement isolation](./pic/implement_isolation.svg)

> NOTE
>
> 这相当于将整个的ram device划分为 Trusted or unTrusted, 然后
> 相应属性的访问只能访问对应属性的target
{: .prompt-info}

This approach works well for either TrustZone-aware devices or those devices
that live entirely within one address space. For larger memories, like off-chip
DDR, we might want to partition the memory into Secure and Non-secure regions. A
TrustZone Address Space Controller (TZASC) allows us to do this, as you can see
in the following diagram:

> 这种方法对于支持 TrustZone 的设备，或者完全属于某一个地址空间的设备来说效果很
> 好。但对于更大的内存，比如片外 DDR，我们可能希望将内存划分为安全和非安全区域。
> TrustZone 地址空间控制器（TrustZone Address Space Controller，TZASC）可以帮助
> 我们实现这一目标，如下图所示：
{: .prompt-trans}

<center><font><strong>
Figure 2. Partition memory
</strong></font></center>

![Partition memory](./pic/partition_memory.svg)

The TZASC is similar to a Memory Protection Unit (MPU), and allows the address
space of a device to split into several regions. With each region specified as
Secure or Non-secure. The registers to control the TZASC are Secure access only,
permitting only Secure software to partition memory.

> TZASC 类似于内存保护单元（Memory Protection Unit，MPU），允许将设备的地址空间
> 划分为多个区域，每个区域都可以被指定为安全或非安全。用于控制 TZASC 的寄存器只
> 能通过安全访问进行操作，这样只有安全软件才能对内存进行分区。
{: .prompt-trans}

An example of a TZASC is the Arm TZC-400, which supports up to nine regions.

> Note
>
> Off-chip memory is less Secure than on-chip memory, because it is easier for
> an attacker to read or modify its contents. On-chip memories are more secure
> but are much more expensive and of limited size. As always, we must balance
> cost, usability, and security. Be careful when deciding which assets you want
> in off-chip memories and which assets need to be kept on-chip.
>
>> 片外内存（off-chip memory）比片上内存（on-chip memory）安全性更低，因为攻击者
>> 更容易读取或篡改其内容。片上内存更加安全，但成本更高且容量有限。和往常一样，我们
>> 需要在成本、可用性和安全性之间进行权衡。在决定哪些资产存放在片外内存、哪些资产需
>> 要留在片上内存时要格外小心。
> {: .prompt-trans}


When the Armv9-A Realm Management Extension (RME) is implemented, memory can by
dynamically moved between physical address spaces via the Granule Protection
Table. For more information, see Introducing Arm’s Dynamic TrustZone technology
blog.

> 当实现了 Armv9-A 的 Realm 管理扩展（RME）后，可以通过颗粒保护表（Granule
> Protection Table, GPT）在不同物理地址空间之间动态移动内存。更多信息请参见
> 《Introducing Arm’s Dynamic TrustZone technology》博客。
{: .prompt-trans}

### Bus requesters

Next, we will look at the bus requesters in the system, as you can see in the
following diagram:

<center><font><strong>
Figure 1. Bus requesters in the system
</strong></font></center>

![Bus requesters in the system](./pic/bus_requesters.svg)

The A-profile processors in the system are TrustZone aware and send the correct
security status with each bus access. However, most modern SoCs also contain
non-processor bus requesters, for example, GPUs and DMA controllers.

> 系统中的 A-profile 处理器是支持 TrustZone 的，并且每次总线访问都会携带正确的安
> 全状态。然而，大多数现代 SoC 还包含非处理器类型的总线请求方，例如 GPU 和 DMA
> 控制器。
{: .prompt-trans}

Like with completer devices, we can roughly divide the requester devices in the
system into groups:

* TrustZone aware

  Some requesters are TrustZone aware, and like the processor, provide the
  appropriate security information with each bus access. Examples of this
  include System MMUs (SMMUs) that are built to the Arm SMMUv3 specification.

  > 有些请求方是支持 TrustZone 的，就像处理器一样，每次总线访问都会提供相应的安
  > 全信息。例如，符合 Arm SMMUv3 规范的系统 MMU（SMMU）就是这样的请求方。
  {: .prompt-trans}

* Non-TrustZone aware

  Not all requesters are built with TrustZone awareness, particularly when
  reusing legacy IP. Such requesters typically provide no security information
  with its bus accesses, or always send the same value.

  > 并非所有的请求方都具备 TrustZone 感知能力，尤其是在复用旧版 IP 时。这类请求
  > 方通常不会在总线访问中提供安全信息，或者始终发送同一个固定值。
  {: .prompt-trans}

  What system resources do non-TrustZone-aware requesters need to access? Based
  on the answer to this question, we could pick one of several approaches:

  > 非 TrustZone 感知请求方需要访问哪些系统资源？根据这个问题的答案，我们可以选
  > 择以下几种方法之一：
  {: .prompt-trans}

  + Design time tie-off

    Where the requester only needs to access a single physical address space, a
    system designer can fix the address spaces to which it has access, by tying
    off the appropriate signal. This solution is simple, but is not flexible.

    > 如果请求方只需要访问单一的物理地址空间，系统设计者可以通过拉高（tie-off）
    > 相关信号，将其访问权限固定到某个地址空间。这种方案简单，但灵活性较差。
    {: .prompt-trans}

  + Configurable logic

    Logic is provided to add the security information to the requester’s bus
    accesses. Some interconnects, like the Arm NIC-400, provide registers that
    Secure software can use at boot time to set the security of an attached
    requester accesses. This overrides whatever value the requester provided
    itself. This approach still only allows the requester to access a single
    physical address space but is more flexible than a tie-off.

    > 可以通过逻辑电路为请求方的总线访问添加安全信息。有些互连（如 Arm NIC-400）
    > 提供寄存器，安全软件可以在启动时配置，设置某个连接请求方的访问安全属性，从
    > 而覆盖请求方自身提供的值。该方法仍然只能让请求方访问单一物理地址空间，但比
    > 设计时固定更灵活。
    {: .prompt-trans}

  + SMMU

    A more flexible option is an SMMU. For a trusted requester, the SMMU behaves
    like the MMU in Secure state. This includes the NS bit in the translation
    table entries, controlling which physical address space is accessed.

    > 更灵活的方案是使用 SMMU（系统内存管理单元）。对于受信任的请求方，SMMU 的行
    > 为类似于安全状态下的 MMU，包括转换表项中的 NS 位，用于控制访问哪个物理地址
    > 空间。
    {: .prompt-trans}
 
> NOTE (Bus requester information)
>
> `<<AMBA AXI and ACE Protocol Specificatio>> Section A4.7 Access permissions`
> 中讲解了AXI总线上的事物的access attr, 其中包括secure mode相关属性, 如下
>
> > AXI provides access permissions signals that can be used to protect against
> > illegal transactions:
> > * ARPROT[2:0] defines the access permissions for read accesses
> > * AWPROT[2:0] defines the access permissions for write accesses. 
> >
> > The term AxPROT refers collectively to the ARPROT and AWPROT signals.
> > 
> > ![AXI_protection_encoding](pic/AXI_protection_encoding.png)
>
> AxPROT[1]表示该属性.
>
> 那如果按照, 前面的知识来看, 在CPU 侧，是通过EL3 切换`SCR_EL3.NS` 来决定`eret` 
> 后的世界是secure world or Non-secure world, 从而决定最终MMU(可能时MMU) 向AXI
> 发送的AxPROT[1] 是什么值.
>
>> 那像上文说的SMMU 是怎么控制的呢? 难道我们通过修改SMMU pgtable就可以让device
>> 访问secure world? 那么控制SMMU的软件是secure world还是Non-secure world，还是
>> smmu像带有 TZASC 的mem一样，也分secure/Non-secure world resource, 只让CPU对应
>> 的secure mode来处理?
> {: .prompt-warning}
{: .prompt-tip}

### M and R profile Arm processors

(略)

### Interrupts

Next, we will look at the interrupts in the system, as you can see in the
following diagram:

> 接下来，我们将查看系统中的总线请求者，如下图所示：
{: .prompt-trans}

<center><font><strong>
Figure 1. Interrupts in the system
</strong></font></center>

![Interrupts in the system](./pic/intr_in_the_sys.svg)

The Generic Interrupt Controller (GIC), supports TrustZone. Each interrupt
source, called an INTID in the GIC specification, is assigned to one of three
Groups:

> 通用中断控制器（GIC）支持 TrustZone。每个中断源（在 GIC 规范中称为 INTID）被分
> 配到三个组中的一个：
{: .prompt-trans}

* Group 0: Secure interrupt, signaled as FIQ
* Secure Group 1: Secure interrupt, signaled as IRQ or FIQ
* Non-secure Group 1: Non-secure interrupt, signaled as IRQ or FIQ

> * 组 0：安全中断，以 FIQ 方式信号通知
> * 安全组 1：安全中断，以 IRQ 或 FIQ 方式信号通知
> * 非安全组 1：非安全中断，以 IRQ 或 FIQ 方式信号通知
{: .prompt-trans}

This is controlled by software writing to the `GIC[D|R]_IGROUPR<n>` and `GIC[D|R]_IGRPMODR<n>`
registers, which can only be done from Secure state. The allocation
is not static. Software can update the allocations at run-time.

> 这个分组通过软件写入 GIC[D|R]_IGROUPR 和 GIC[D|R]_IGRPMODR 寄存器来控制，且只
> 能在安全状态下进行。分配不是静态的，软件可以在运行时动态更新分配。
{: .prompt-trans}

For INTIDs that are configured as Secure, only bus Secure accesses can modify
state and configuration. Register fields corresponding to Secure interrupts are
read as 0s to Non-secure bus accesses.

> 对于被配置为安全的 INTID，只有安全总线访问才能修改其状态和配置。对应安全中断的
> 寄存器字段，对于非安全总线访问会读取为 0。
{: .prompt-trans}

For INTIDs that are configured as Non-secure, both Secure and Non-secure bus
accesses can modify state and configuration.

> 对于被配置为非安全的 INTID，安全和非安全总线访问都可以修改其状态和配置。
{: .prompt-trans}

Why are there two Secure Groups? Typically, Group 0 is used for interrupts that
are handled by the EL3 firmware. These relate to low-level system management
functions. Secure Group 1 is used for all the other Secure interrupt sources and
is typically handled by the S.EL1 or S.EL2 software.

> 为什么会有两个安全组？通常，组 0 用于由 EL3 固件处理的中断，这些中断与底层系统
> 管理功能相关。安全组 1 用于所有其他安全中断源，通常由 S.EL1 或 S.EL2 软件处理。
{: .prompt-trans}

### Handling interrupts

The processor has two interrupt exceptions, IRQ and FIQ. When an interrupt
becomes pending, the GIC uses different interrupt signals depending on the group
of the interrupt and the current Security state of the processor:

> 处理器有两种中断异常：IRQ 和 FIQ。当有中断挂起时，GIC 会根据中断所属的组以及处
> 理器当前的安全状态，使用不同的中断信号：
{: .prompt-trans}

* Group 0 interrupt
  + Always signaled as FIQ exception
* Secure Group 1
  + Processor currently in Secure state – IRQ exception 
  + Processor currently in Non-secure state – FIQ exception
* Non-secure Group 1
  + Processor currently in Secure state – FIQ exception 
  + Processor currently in Non-secure state – IRQ exception

> NOTE
>
> 当收到了一个不属于当前 secure-state的 interrupt, 都是FIQ, 否则为IRQ
> (Group 0 除外，因为Group 0都是FIQ)
>
> * Group 0 --- El3
> * Secure Group1 -- Secure state
> * Non-Secure Group1 -- Non-Secure state
>
> 其目的是想让对应的Secure state 处理相应的interrupt，但是Secure state <-->
> Non-secure state的切换需要EL3参与
{: .prompt-tip}

Remember that Group 0 interrupts are typically used for the EL3 firmware. This
means that:

> 请记住，组 0 的中断通常用于 EL3 固件。这意味着：
{: .prompt-trans}

* IRQ means a Group 1 interrupt for the current Security state.
* FIQ means that we need to enter EL3, either to switch Security state or to
  have the firmware handle the interrupt.

> * IRQ 表示当前安全状态下的组 1 中断。
> * FIQ 表示需要进入 EL3，要么是为了切换安全状态，要么是让固件处理该中断。
>   以下示例展示了异常路由控制如何进行配置：
{: .prompt-trans}

The following example shows how the exception routing controls could be
configured:

> 以下示例展示了异常路由控制可以如何配置：
{: .prompt-trans}

<center><font><strong>
Figure 1. Exception routing controls
</strong></font></center>

![Exception routing controls](./pic/exp_routing_ctrls.svg)

The preceding diagram shows one possible configuration. Another option that is
commonly seen is for FIQs to be routed to EL1 while in Secure state. The Trusted
OS treats the FIQ as a request to yield to either the firmware or to Non-secure
state. This approach to routing interrupts gives the Trusted OS the opportunity
to be exited in a controlled manor.

> 前面的图展示了一种可能的配置。另一种常见的选择是在安全状态下将 FIQ 路由到 EL1。
> 此时，受信任操作系统（Trusted OS）会将 FIQ 视为让出执行权给固件或非安全状态的
> 请求。这种中断路由方式，使得受信任操作系统能够以可控的方式退出。
{: .prompt-trans}

> 优雅switch, 让trust OS 在退出前，做一些事情
{: .prompt-tip}

## 参考链接
1. [Learn the architecture - TrustZone for AArch64](https://developer.arm.com/documentation/102418/0102/What-is-TrustZone-)
2. [ARM CoreLink TZC-400 TrustZone Address Space Controller Technical Reference Manual r0p1 Rate this page:](https://developer.arm.com/documentation/ddi0504/c/introduction/about-the-tzc-400/tzc-400-example-system?lang=en)
