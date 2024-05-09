---
layout: post
title:  "cache shadow page tables"
author: fuqiang
date:   2024-05-07 18:30:00 +0800
categories: [kvm,mmu_note]
tags: [virt]
---





## commit message
```
commit cea0f0e7ea54753c3265dc77f605a6dad1912cfc
Author: Avi Kivity <avi@qumranet.com>
Date:   Fri Jan 5 16:36:43 2007 -0800

    [PATCH] KVM: MMU: Shadow page table caching

    Define a hashtable for caching shadow page tables. Look up the cache on
    context switch (cr3 change) or during page faults.
    > 定义一个哈希表来缓存影子页表。 在上下文切换（cr3 更改）或page fault期间
    > 查找缓存。

    The key to the cache is a combination of
    - the guest page table frame number
      > GFN of guest page table
    - the number of paging levels in the guest
       * we can cache real mode, 32-bit mode, pae, and long mode page
         tables simultaneously.  this is useful for smp bootup.
         > 我们可以同时缓存实模式、32位模式、pae和长模式页表。 这对于 smp 
         > bootup 很有用。
    - the guest page table table
       * some kernels use a page as both a page table and a page directory.  this
         allows multiple shadow pages to exist for that page, one per level
         > 一些内核使用页同时作为页表和页目录。 这允许该页面存在多个影子页面，每个
         > 级别一个
    - the "quadrant"
       * 32-bit mode page tables span 4MB, whereas a shadow page table spans
         2MB.  similarly, a 32-bit page directory spans 4GB, while a shadow
         page directory spans 1GB.  the quadrant allows caching up to 4 shadow page
         tables for one guest page in one level.
         > 32 位模式页表跨度为 4MB，而影子页表跨度为 2MB。 同样，32 位页目录的大小为 4GB，
         > 而影子页目录的大小为 1GB。 该象限允许为一级中的一个guest page 缓存最多 4 个影子页
         > 表。
         >
         >> Why ??
         >> Because shadow page table is PAE. 4M = 2M * 2^1,  4G = 1G * 2 ^ 2.
    - a "metaphysical" bit
       * for real mode, and for pse pages, there is no guest page table, so set
         the bit to avoid write protecting the page.
         > 对于实模式和 pse page，没有guest 页表，因此设置该位以避免对页进行写保护。
```
# 参考链接

[mail list]: https://lore.kernel.org/all/459D21DD.5090506@qumranet.com/

1. [KVM: MMU: Cache shadow page tables][mail list] --- \[mail list\]
