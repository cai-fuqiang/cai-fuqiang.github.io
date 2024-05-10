---
layout: post
title:  "not-present guest page faults to bypass kvm"
author: fuqiang
date:   2024-05-10 13:45:00 +0800
categories: [kvm,mmu]
tags: [virt]
---


## commit message

<details markdown=1 open>
<summary>commit message </summary>

<details markdown=1>
<summary>upstream commit </summary>
```
commit c7addb902054195b995114df154e061c7d604f69
Author: Avi Kivity <avi@qumranet.com>
Date:   Sun Sep 16 18:58:32 2007 +0200

    KVM: Allow not-present guest page faults to bypass kvm
```
</details><!--upstream commit-->
There are two classes of page faults trapped by kvm:
 - host page faults, where the fault is needed to allow kvm to install
   the shadow pte or update the guest accessed and dirty bits
   > host page faults:
   >  其中需要fault 以允许 kvm 安装 shadow  pte 或更新guest accessed 和 
   >  dirty bits.
 - guest page faults, where the guest has faulted and kvm simply injects
   the fault back into the guest to handle
   > guest page fault.
   >   guest出现faulted, 而KVM 只是将fault注入回 guest来处理.

The second class, guest page faults, is pure overhead.  We can eliminate
some of it on vmx using the following evil trick:
> ```
> pure /pjʊr/: 纯的; 纯粹的
> eliminate [ɪˈlɪmɪneɪt]: 消除, 排除, 消灭; 清除
> evil /ˈiːvl/: 邪恶的
> trick /trɪk/: 技巧;戏法
> ```
>
> 第二类，guest page faults，是纯粹的开销。 我们可以使用以下邪恶技巧在 vmx 上
> 消除他们其中的一些：
 - when we set up a shadow page table entry, if the corresponding guest pte
   is not present, set up the shadow pte as not present
   > 当我们设置影子页表项时，如果对应的guest pte not present，则将影子pte设置
   > 为not present
 - if the guest pte _is_ present, mark the shadow pte as present but also
   set one of the reserved bits in the shadow pte
   > 如果guest pte 是present，则将影子 pte 标记为present，但还要设置影子 pte 中
   > 的保留位之一
 - tell the vmx hardware not to trap faults which have the present bit clear
   > 告诉vmx hardware 不要 对 present bit clear  trap fault.

With this, normal page-not-present faults go directly to the guest,
bypassing kvm entirely.

> 这样, normal page-not-present fault 将会直接到guest, 而整个bypass掉kvm.

Unfortunately, this trick only works on Intel hardware, as AMD lacks a
way to discriminate among page faults based on error code.  It is also
a little risky since it uses reserved bits which might become unreserved
in the future, so a module parameter is provided to disable it.

> ```
> lacks [læks]: 缺乏, 匮乏, 短缺
> discriminate /dɪˈskrɪmɪneɪt/: 区分, 辨别
> ```
>
> 不幸的是, 该技巧只能work在 Intel 硬件上, 因为AMD 缺乏根据error code 区分 
> page fault 的方法。它也有一点风险，因为它使用了将来可能变为非保留的保留位，
> 因此提供了一个module parameter 来禁用它。


</details>

