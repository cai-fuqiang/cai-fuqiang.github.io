---
layout:     post
title:      "[PATCH 0/3] x86, apicv: Add APIC virtualization support"
author:     "fuqiang"
date:       "Fri, 25 Jan 2013 10:18:49 +0800"
categories: [kvm]
tags:       [kvm]
---


APIC virtualization is a new feature which can eliminate most of VM exit
when vcpu handle a interrupt:

> ```
> eliminata [ɪˈlɪmɪneɪt]: 消除
> ```
>
> APIC virtualization 是一个新feature, 该功能可以消除大部分的当vcpu处理一个intr
> 时的vm exit.

APIC register virtualization:

* APIC read access doesn't cause APIC-access VM exits.
* APIC write becomes trap-like.

> * APIC read access 将不会导致 VM exit.
> * APIC write 将会变成 trap-like

Virtual interrupt delivery:

Virtual interrupt delivery avoids KVM to inject vAPIC interrupts
manually, which is fully taken care of by the hardware.

> 虚拟中断传递避免了 KVM 手动注入 vAPIC 中断，这完全由硬件负责。
