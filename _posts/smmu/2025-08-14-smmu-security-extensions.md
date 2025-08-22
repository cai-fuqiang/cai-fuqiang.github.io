---
layout: post
title:  "[smmu] Security Extensions"
author: fuqiang
date:   2025-08-14 14:28:00 +0800
categories: [arm_arch,smmu]
tags: [smmu]
---

## 8.1 Sharing resources between Secure and Non-secure domains

In an implementation that includes the Security Extensions, the resources of a
System MMU are shared between Secure and Non-secure domains. For information
about the Security Extensions, see the ARM Architecture Reference Manual,
ARMv7-A and ARMv7-R edition.

> 在包含安全扩展（Security Extensions）的实现中，SMMU 的资源在安全域和非安全
> 域之间共享。关于安全扩展的详细信息，请参阅《ARM 架构参考手册，ARMv7-A 和
> ARMv7-R 版本》。
{: .prompt-trans}


The System MMU architecture permits inclusion of the Security Extensions to be
an IMPLEMENTATION DEFINED choice. SMMU_IDR0.SES indicates whether the Security
Extensions are included.

> SMMU 架构允许是否包含安全扩展由具体实现决定（IMPLEMENTATION DEFINED）。
> SMMU_IDR0.SES 用于指示是否包含安全扩展。
{: .prompt-trans}

## 8.2 Excluding the Security Extensions

A System MMU implementation might exclude the Security Extensions. However, this
does not mean that a transaction from a Secure device cannot arrive at the
System MMU. If a System MMU does not include the Security Extensions, and is
expected to receive and process any transaction from a Secure device, security
state determination must ensure that this transaction bypasses all subsequent
System MMU transaction processing.

> 一个SMMU 的实现可能不包含安全扩展（Security Extensions）。然而，这并不意味着来
> 自安全设备（Secure device）的事务无法到达SMMU。如果 SMMU 没有包含安全扩展，但
> 又需要接收并处理来自安全设备的任何事务，则必须确保安全状态的判定能让这些事务绕
> 过 SMMU 的所有后续事务处理。
{: .prompt-trans}

If SMMU_IDR0.SES is 0:

+ the System MMU implementation does not translate transactions from Secure
  devices
+ Stream match register groups, Translation context banks and interrupts are not
  reserved
+ the Secure Banked control and status registers are absent.

> * SMMU 实现不会对来自安全设备的事务进行地址转换。
> * stream match register groups、地址转换上下文库和中断不会被保留
> * 安全分组的控制和状态寄存器也不存在。
{: .prompt-trans}

## 8.3 Including the Security Extensions

If SMMU_IDR0.SES is 1, Secure software might arrange for a System MMU to process
and translate transactions from one or more Secure devices.

> ```
> arrange: 安排
> ```
>
> 如果 SMMU_IDR0.SES 为 1，安全软件可以让 SMMU 处理并转换来自一个或多个安全设备的
> 事务
{: .prompt-trans}


### 8.3.1 Translation restrictions

In a System MMU implementation that includes the Security Extensions, the
following restrictions apply to a transaction from a Secure device:

* stage 2 nested translation is not permitted
* a transaction from a Secure device must only be translated by a stage 1
  context that is reserved by Secure software.

> 在包含安全扩展（Security Extensions）的 SMMU 实现中，针对来自安全设备的事务，
> 适用以下限制：
> * 不允许进行二级嵌套地址转换（stage 2 nested translation）。
> * 来自安全设备的事务只能由被安全软件保留的一级（stage 1）上下文进行地址转换。
{: .prompt-trans}

### 8.3.2 Resource reservation

In a System MMU implementation that includes the Security Extensions, a number
of resources are shared between Secure and Non-secure domains. For some of these
resources, Secure software might reserve some or all of the resource for the
sole use of the Secure software. Such shared resources include:


* Stream mapping register groups. See SMMU_SCR1.NSNUMSMRGO.
* Context interrupts. See SMMU_SCR1.NSNUMIRPTO.
* Translation context banks. See SMMU_SCR1.NSNUMCBO.

> 在包含安全扩展（Security Extensions）的 SMMU 实现中，有许多资源在安全域和非安
> 全域之间共享。对于其中的一些资源，安全软件可以将部分或全部资源保留，仅供安全软
> 件专用。这些共享资源包括：
> * 流映射寄存器组（Stream mapping register groups）。参见 SMMU_SCR1.NSNUMSMRGO。
> * 上下文中断（Context interrupts）。参见 SMMU_SCR1.NSNUMIRPTO。
> * 地址转换上下文库（Translation context banks）。参见 SMMU_SCR1.NSNUMCBO。
{: .prompt-trans}

The SMMU_IDRx registers take into account the number of registers reserved by
Secure software when reporting the number of resources. See SMMU_IDR0-7,
Identification registers on page 10-116.

If Secure software reserves a shared System MMU resource, one of the following
generally applies:

* the reservation occurs at Secure system boot time and is static for the
  duration of system uptime
* a software interface between Secure and Non-secure domains is implemented that
  supports the dynamic partitioning of System MMU resources.

> SMMU_IDRx 寄存器在报告资源数量时，会考虑被安全软件保留的寄存器数量。参见第
> 10-116 页的 SMMU_IDR0-7 标识寄存器（Identification registers）。
>
> 如果安全软件保留了某个共享的 SMMU 资源，通常会出现以下两种情况之一：
> * 资源在安全系统启动时被保留，并在系统运行期间保持静态不变；
> * 在安全域和非安全域之间实现了一个软件接口，支持对 SMMU 资源的动态分区。
{: .prompt-trans}

As a consequence of the restrictions specified in Translation restrictions, the
following conditions apply:

* A transaction that is determined to be Secure by security state determination
  must only match a Stream mapping register group that is reserved by Secure software.

* A Stream mapping register group that is reserved by Secure software must only
  specify:
  + a Translation context bank reserved by Secure software
  + Bypass mode
  + the fault context.

* The `SMMU_CBARn` register associated with a Translation context bank reserved by
    Secure software must only specify a Context interrupt that is reserved by
    Secure software.

* Any Translation context bank reserved by Secure software must be placed above
    the Translation context bank indicated by `SMMU_IDR1.NUMS2CB`. This field
    indicates the last Translation context bank that only supports the stage 2
    translation format.

> 根据“地址转换限制”中规定的约束，需遵循以下条件：
>
> * 通过安全状态判定为安全（Secure）的事务，只能匹配由安全软件保留的流映射寄存器
>   组（Stream mapping register group）。
> * 由安全软件保留的流映射寄存器组只能指定以下内容：
>   + 由安全软件保留的地址转换上下文库（Translation context bank）
>   + 旁路模式（Bypass mode）
>   + 故障上下文（fault context）
>
> * 与由安全软件保留的地址转换上下文库关联的 SMMU_CBARn 寄存器，只能指定由安全软
>   件保留的上下文中断（Context interrupt）。
> 
> * 任何由安全软件保留的地址转换上下文库，其编号必须高于 SMMU_IDR1.NUMS2CB 字段
>   所指示的上下文库编号。该字段表示仅支持二级（stage 2）转换格式的最后一个地址
>   转换上下文库。
{: .prompt-trans}

### 8.3.3 Permitted transaction resource usage

This section specifies which resources a transaction is permitted to interact
with, in relation to the Security Extensions.

The Security Extensions in the processor architecture introduce a Secure domain
and a Non-secure domain, based on the following fundamental concepts:

* The Secure domain must be able to operate in isolation from the Non-secure
  domain.

> Note
>
> Regardless of whether a System MMU implementation excludes the Security
> Extensions, the introduction of a System MMU must not create any type of
> security loophole.



