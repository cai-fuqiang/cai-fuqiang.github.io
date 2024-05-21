---
layout:     post
title:      "[PATCH 00/13] RFC: out of sync shadow"
author:     "fuqiang"
date:       "Tue, 23 Sep 2008 13:18:28 -0300"
categories: [kvm,out_of_sync_shadow]
tags:       [out_of_sync_shadow]
---

Keep shadow pages temporarily out of sync, allowing more efficient guest
PTE updates in comparison to trap-emulate + unprotect heuristics. Stolen
from Xen :)

> ```
> temporarily  [ˌtempəˈrerəli ]
> heuristics  [hjuˈrɪstɪks] : 启发式, 探索法
> ```
> 保持影子页面暂时不同步，与陷阱模拟+unprotect heuristics 相比，允许更有效的
> guest PTE 更新。从 Xen 偷来的:)

This version only allows leaf pagetables to go out of sync, for
simplicity, but can be enhanced.

> ```
> simplicity [sɪmˈplɪsəti]
> enhanced [ɪnˈhænst]
> ```
> 为了简单起见，这个版本只允许leaf pagetables 不同步，但可以进行增强。

VMX "bypass_guest_pf" feature on prefetch_page breaks it (since new
PTE writes need no TLB flush, I assume). Not sure if its worthwhile to
convert notrap_nonpresent -> trap_nonpresent on unshadow or just go 
for unconditional nonpaging_prefetch_page.

> prefetch_page 上的VMX "bypass_guest_pf" feature 破坏了它（因为我认为新的PTE
> 写入不需要TLB刷新）。不确定是否值得在unshadow上转换notrap_nonpresent->
> trap_nonpresent，或者只使用无条件的nonpage_prefetch_page。

* Kernel builds on 4-way 64-bit guest improve 10% (+ 3.7% for
  get_user_pages_fast). 

* lmbench's "lat_proc fork" microbenchmark latency is 40% lower (a
  shadow worst scenario test).

* The RHEL3 highpte kscand hangs go from 5+ seconds to < 1 second.

* Windows 2003 Server, 32-bit PAE, DDK build (build -cPzM 3):

Windows 2003 Checked 64 Bit Build Environment, 256M RAM
```
1-vcpu:
vanilla + gup_fast:         oos
0:04:37.375                 0:03:28.047     (- 25%)

2-vcpus:
vanilla + gup_fast          oos
0:02:32.000                 0:01:56.031     (- 23%)


Windows 2003 Checked Build Environment, 1GB RAM
2-vcpus:
vanilla + fast_gup         oos
0:02:26.078                0:01:50.110      (- 24%)

4-vcpus:
vanilla + fast_gup         oos
0:01:59.266                0:01:29.625      (- 25%)
```

And I think other optimizations are possible now, for example the guest
can be responsible for remote TLB flushing on kvm_mmu_pte_write().

> 我认为现在还可以进行其他优化，例如guest可以负责 kvm_mmu_pte_write() 上的
> 远程 TLB 刷新。

Please review.


> 该patch来自于[RFC patch 0][RFC_0]
{: .prompt-info}

[RFC_0]: https://lore.kernel.org/all/20080906184822.560099087@localhost.localdomain/
