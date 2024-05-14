---
layout:     post
title:      "[PATCH 0/33] KVM: MMU: Cache shadow page tables"
author:     "fuqiang"
date:       "Thu, 04 Jan 2007 17:48:45 +0200"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

The current kvm shadow page table implementation does not cache shadow 
page tables (except for global translations, used for kernel addresses) 
across context switches.  This means that after a context switch, every 
memory access will trap into the host.  After a while, the shadow page 
tables will be rebuild, and the guest can proceed at native speed until 
the next context switch.

> ```
> after a while: 一段时间后
> ```
> 当前的 kvm 影子页表实现不会实现跨上下文切换缓存影子页表（global 
> translations除外，用于内核地址）。 这意味着在上下文切换后，
> 每次内存访问都会trap host。 一段时间后，影子页表将被重建，
> 并且guest可以以native speed 继续，直到下一次上下文切换。

The natural solution, then, is to cache shadow page tables across 
context switches.  Unfortunately, this introduces a bucketload of problems:

> ```
> bucketload /ˈbʌkɪt/ : 桶装; 大量
> ```
> 那么，自然的解决方案是跨上下文切换缓存影子页表。不幸的是，这会带来一系列
> 问题：

+ the guest does not notify the processor (and hence kvm) that it modifies a
    page table entry if it has reason to believe that the modification will be
    followed by a tlb flush.  It becomes necessary to write-protect guest page
    tables so that we can use the page fault when the access occurs as a
    notification.

    > 如果 guest 虚拟机有理由相信修改后将进行 tlb 刷新，则不会通知处理器（以
    > 及 kvm）它修改了页表条目。 有必要对来宾页表进行写保护，以便我们可以在访
    > 问发生时使用page fault作为通知。

+ write protecting the guest page tables means we need to keep track of 
    which ptes map those guest page table. We need to add reverse mapping for
    all mapped writable guest pages.

    > 写保护guest page table 意味着我们需要跟踪哪些 ptes 映射了这些guest page 
    > table。 我们需要为所有映射的可写guest page table添加反向映射。

+ when the guest does access the write-protected page, we need to allow 
    it to perform the write in some way.  We do that either by emulating the
    write, or removing all shadow page tables for that page and allowing the
    write to proceed, depending on circumstances.

    > 当guest 确实访问写保护页面时，我们需要允许它以某种方式执行写入。 我们可
    > 以通过模拟写入或删除该页的所有影子页表并允许写入继续进行来实现这一点，
    > 具体取决于具体情况。

This patchset implements the ideas above.  While a lot of tuning remains 
to be done (for example, a sane page replacement algorithm), a guest 
running with this patchset applied is much faster and more responsive 
than with 2.6.20-rc3.  Some preliminary benchmarks are available in 
http://article.gmane.org/gmane.comp.emulators.kvm.devel/661.

> ```
> tuning /ˈtuːnɪŋ/: 调整
> preliminary /prɪˈlɪmɪneri/: 初步的
> ```
> 该补丁集实现了上述想法。 虽然仍有大量调整需要完成（例如，合理的页面替换
> 算法），但应用此补丁集运行的guest 系统比 2.6.20-rc3 运行速度更快、响应更快.
> 一些初步的 benchmarks 可以在... 获得.

The patchset is bisectable compile-wise.

> ```
> bisectable /prɪˈlɪmɪneri/: 可平分的
> ```
> 补丁集在编译时是可二分的。
