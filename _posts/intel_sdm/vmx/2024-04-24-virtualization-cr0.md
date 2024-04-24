---
layout: post
title:  "virtualization cr0"
author: fuqiang
date:   2024-04-24 18:30:00 +0800
categories: [intel_sdm]
tags: [virt]
---

## Guest/Host Masks and Read Shadows for CR0 and CR4

> FROM intel sdm
>
> ```
> CHAPTER 25 VIRTUAL MACHINE CONTROL STRUCTURES
>   25.6 VM-EXECUTION CONTROL FIELDS
>     25.6.6
> ```

VM-execution control fields include **guest/host masks** and **read shadows** for the
CR0 and CR4 registers. These fields control executions of instructions that
access those registers (including CLTS, LMSW, MOV CR, and SMSW). They are 64
bits on processors that support Intel 64 architecture and 32 bits on processors
that do not.

> VM-execution control 字段包括对于CR0 和 CR4 寄存器的 **guest/host masks** 
> 和 **read shadows**. 这些字段控制访问这些寄存器的指令的执行（包括 CLTS、
> LMSW、MOV CR 和 SMSW）。 它们在支持 Intel 64 架构的处理器上为 64 位，在不支持 
> Intel 64 架构的处理器上为 32 位。

In general, bits set to 1 in a guest/host mask correspond to bits “owned” by
the host:

> 一般来说，`guest/host mask`中设置为 1 的位对应于host“owned(拥有)”的位：

* Guest attempts to set them (using CLTS, LMSW, or MOV to CR) to values
  differing from the corresponding bits in the corresponding read shadow cause
  VM exits.
  > guest尝试将它们（使用 CLTS、LMSW 或 MOV 到 CR）设置为与`read shadow`中的相应
  > 位不同的值，导致 VM exit

* Guest reads (using MOV from CR or SMSW) return values for these bits from the
  corresponding read shadow. Bits cleared to 0 correspond to bits “owned” by
  the guest; guest attempts to modify them succeed and guest reads return
  values for these bits from the control register itself.
  > ```
  > correspond [ˌkɔːrəˈspɑːnd]: : 相一致, 符合;相当于;类似于
  > ```
  > guest读取（使用 CR 或 SMSW 中的 MOV）从相应的`read shadow`中返回这些位的值。
  > cleared为 0 的位对应于guest “拥有”的位；guest尝试修改它们成功，并且guest从他们
  > 自己的控制寄存器读取这些位的值.

See Chapter 28 for details regarding how these fields affect VMX non-root
operation.

> 有关这些字段如何影响 VMX 非 root 操作的详细信息，请参阅第 **26** 章。
>> 这里intel sdm 中写错了, 应该是26章
> {: .prompt-info}

## MOV to CR0 cause VM Exits Conditionally

> FROM intel sdm
> ```
> CHAPTER 26 VMX NON-ROOT OPERATION
>   26.1 INSTRUCTIONS THAT CAUSE VM EXITS
>     26.1.3 Instructions That Cause VM Exits Conditionally
> ```

* **MOV to CR0.**

  The MOV to CR0 instruction causes a VM exit unless the value of its source
  operand matches, for the position of each bit set in the CR0 guest/host mask,
  the corresponding bit in the CR0 read shadow. (If every bit is clear in the
  CR0 guest/host mask, MOV to CR0 cannot cause a VM exit.)
  > MOV 到 CR0 指令会导致 VM 退出，除非其源操作数的值与CR0`guest/host mask`中设
  > 置的每个位的位置对应的 CR0 `read shadow`中相应位的值匹配。 （如果 CR0 
  > `guest/host mask`中的每一位都被清除，则 MOV 到 CR0 不会导致 VM 退出。）
  >
  >> E.g.
  >> ```
  >> CR0 guest host mask : 0 0 0 0 1 0 1 0 1 0 1
  >>                               |   |   |   |
  >>                               |   |   |   |
  >> CR0 read shadow     : 1 1 1 1 1 1 1 1 1 1 1
  >> compare bit         :         ^   ^   ^   ^
  >> source operand      : x x x x 1 x 1 x 1 x 1   ---> NO vm exit
  >> source operand      : x x x x x x x x x x 0   ---> need vm exit
  >> ```
  >> 会将设置的值和 compare bit进行比较, 如果两者一样, 则不需要vm exit, 
  >> 如果不一样, 则需要VM exit, 下面会说明原因
  > {: .prompt-tip}

## CHANGES TO "MOV from/to CR0" BEHAVIOR IN VMX NON-ROOT OPERATION

> FROM intel sdm
>
> ```
> CHAPTER 26 VMX NON-ROOT OPERATION
>   26.3 CHANGES TO INSTRUCTION BEHAVIOR IN VMX NON-ROOT OPERATION
> ```

* **MOV from CR0.**

  The behavior of MOV from CR0 is determined by the CR0 guest/host mask and
  the CR0 read shadow. For each position corresponding to a bit clear in the
  CR0 guest/host mask, the destination operand is loaded with the value of
  the corresponding bit in CR0. For each position corresponding to a bit set
  in the CR0 guest/host mask, the destination operand is loaded with the
  value of the corresponding bit in the CR0 read shadow. Thus, if every bit
  is cleared in the CR0 guest/host mask, MOV from CR0 reads normally from
  CR0; if every bit is set in the CR0 guest/host mask, MOV from CR0 returns
  the value of the CR0 read shadow. Depending on the contents of the CR0
  guest/host mask and the CR0 read shadow, bits may be set in the destination
  that would never be set when reading directly from CR0.
  > `MOV from CR0` 的行为由 CR0 `guest/host mask`和 CR0 `read shadow`决定。 
  > 对于与 CR0 `guest/host mask`中清零位相对应的每个位置，目标操作数将加载
  > CR0 中相应位的值。 对于与 CR0 `guest/host mask`中设置的位相对应的每个位置，
  > 目标操作数将加载 CR0 `read shadow`中相应位的值。 因此，如果 `CR0 guest/host 
  > mask`中的每一位都被清除，则 MOV from CR0 会正常从 CR0 读取； 如果在 CR0 
  > `guest/host mask`中设置了每个位，则`MOV from CR0` 将返回 CR0 `read shadow`的值。
  > 根据 CR0 `guest/host mask`和 CR0 `read shadow`的内容，可能会在destination设置
  > 一些 直接从 CR0 读取的永远不会设置的位。


* **MOV to CR0**

  An execution of MOV to CR0 that does not cause a VM exit (see Section 26.1.3)
  leaves unmodified any bit in CR0 corresponding to a bit set in the CR0
  guest/host mask. Treatment of attempts to modify other bits in CR0 depends on
  the setting of the “unrestricted guest” VM-execution control:
  > 执行 `MOV to CR0` 不会导致 VM 退出（请参阅第 26.1.3 节），从而使 CR0 中与 CR0
  > `guest/host mask`中设置的位相对应的任何位保持不变。 对修改 CR0 中其他位的尝试
  > 的处理取决于“unrestricted guest”VM-execution control 的设置：

  + If the control is 0, MOV to CR0 causes a general-protection exception if it
    attempts to set any bit in CR0 to a value not supported in VMX operation
    (see Section 24.8).
    > 如果控制为 0，则 `MOV to CR0` 尝试将 CR0 中的任何位设置为 VMX operation不支持
    > 的值时会导致一般保护异常（请参见第 24.8 节）。

  + If the control is 1, MOV to CR0 causes a general-protection exception if it
    attempts to set any bit in CR0 other than bit 0 (PE) or bit 31 (PG) to a
    value not supported in VMX operation. It remains the case, however, that
    MOV to CR0 causes a general-protection exception if it would result in CR0.
    > 如果控制为 1，则 `MOV to CR0` 尝试将 CR0 中除位 0 (PE) 或位 31 (PG) 之外的
    > 任何位设置为 VMX operation 不支持的值时，会导致一般保护异常。 然而，情况
    > 仍然如此，如果 MOV to CR0 会导致 CR0，则会导致一般保护异常。


## MY note

### 读取操作:

{% graphviz %}

digraph G {
  subgraph cluster_cr0 {
    cr0_bitmap [
      shape="record"
      label="<0>0|<1>0|<2>0|<3>0"
    ]
    label="cr0"
  }
  subgraph cluster_cr0_host_guest_mask {
    cr0_host_guest_mask_bitmap [
      shape="record"
      label="<0>0|<1>1|<2>1|<3>1"
    ]
    label="cr0 host/guest mask"
  }
  subgraph cluster_cr0_read_shadow {
    cr0_read_shadow_bitmap [
      shape="record"
      label="<0>1|<1>1|<2>1|<3>1"
    ]
    label="cr0 read shadow bitmap"
  }

  subgraph cluster_destination_value {
    destination_value [
      shape="record"
      label="<0>0|<1>1|<2>1|<3>1"
    ]
    label="destination value"
  }

  cr0_host_guest_mask_bitmap:0->cr0_bitmap:0
  cr0_host_guest_mask_bitmap:1->cr0_read_shadow_bitmap:1
  cr0_host_guest_mask_bitmap:2->cr0_read_shadow_bitmap:2
  cr0_host_guest_mask_bitmap:3->cr0_read_shadow_bitmap:3

  cr0_bitmap:0->destination_value:0
  cr0_read_shadow_bitmap:1->destination_value:1
  cr0_read_shadow_bitmap:2->destination_value:2
  cr0_read_shadow_bitmap:3->destination_value:3
}

{% endgraphviz %}

### write 操作

* write to `read shadow`

{% graphviz %}
digraph G {
  subgraph cluster_cr0_host_guest_mask {
    
    cr0_host_guest_mask_bitmap [
      shape="record"
      label="<0>0|<1>0|<2>0|<3>1"
    ]
    label="cr0 host/guest mask"
  }

  subgraph cluster_cr0_read_shadow {
    cr0_read_shadow_bitmap [
      shape="record"
      label="<0>0|<1>0|<2>0|<3>1"
    ]
    label="cr0 read shadow bitmap"
  }

  subgraph cluster_source_value {
    source_value [
      shape="record"
      label="<0>0|<1>0|<2>0|<3>0"
    ]
    label="source value"
  }
  subgraph cluster_source_value2 {
    source_value2 [
      shape="record"
      label="<0>0|<1>0|<2>0|<3>1"
    ]
    label="source value2"
  }
  cr0_host_guest_mask_bitmap:3->source_value:3 [
    label="indicate compare bit"
    color="red"
    fontcolor="red"
  ]

  cr0_host_guest_mask_bitmap:3->source_value2:3 [
    label="indicate compare bit"
    color="blue"
    fontcolor="blue"
  ]
  source_value2:3->cr0_read_shadow_bitmap:3 [
    label="compare equal SKIP"
    color="blue"
    fontcolor="blue"
  ]


  source_value:3->cr0_read_shadow_bitmap:3 [
    label="compare NOT equal \nvm EXIT, hypervisor \nmay execute some emulations"
    color="red"
    fontcolor="red"
  ]
}

{% endgraphviz %}

* direct write to CR3

{% graphviz %}

digraph G {
  subgraph cluster_cr0_host_guest_mask {
    cr0_host_guest_mask_bitmap [
      shape="record"
      label="<0>0|<1>0|<2>0|<3>1"
    ]
    label="cr0 host/guest mask"
  }

  subgraph cluster_source_value {
    source_value [
      shape="record"
      label="<0>1|<1>0|<2>1|<3>0"
    ]
    label="source value"
  }
  subgraph cluster_beg_write_cr0 {
    cr0_beg_w [
      shape="record"
      label="<0>x|<1>x|<2>x|<3>x"
    ]
    label="cr0 beg write"
  }
  subgraph cluster_end_write_cr0 {
    cr0_end_w [
      shape="record"
      label="<0>1|<1>0|<2>1|<3>x"
    ]
    label="cr0 : end write"
  }
  cr0_host_guest_mask_bitmap:0->source_value:0
  cr0_host_guest_mask_bitmap:1->source_value:1
  cr0_host_guest_mask_bitmap:2->source_value:2 [
    label="indicate write direct cr0 bit"
  ]

  source_value:0->cr0_beg_w:0
  source_value:1->cr0_beg_w:1
  source_value:2->cr0_beg_w:2 [
    label="write"
  ]

  cr0_beg_w:0->cr0_end_w:0
  cr0_beg_w:1->cr0_end_w:1
  cr0_beg_w:2->cr0_end_w:2 [
    label="write success"
  ]
}

{% endgraphviz %}



> 上面是 MOV from CR0的大概流程
>
> 这里需要注意的是, `cr0 host/guest mask`能决定的是
> * MOV from CR0 的这些bit 从哪个地方获取:
>   + CR0
>   + CR0 read shadow
> * MOV to CR0, 要不要VM exit.
>   + 如果修改了 cr0 host/guest mask中bit对应的 read shadow, 
>     是一定要vm exit.
>   + 当然 在 VMX OPERATION中CR0还有一些限制, 不满足这些限制也会
>     VM exit.
>
> 这里需要思考下
>
> Q: 为什么要这样设计?
>
> A: 为的就是对CR0 的某些bit进行软件(hypervisor)上的虚拟化.
>
> Q: 怎么控制虚拟化哪些呢?
>
> A: 虚拟化 `cr0 host/guest mask`为1 的bit. 
>    + **read** from read shadow 
>    + **write** cause VM-exit
>    + other bit normal read/write to CR0
{: .prompt-tip}
