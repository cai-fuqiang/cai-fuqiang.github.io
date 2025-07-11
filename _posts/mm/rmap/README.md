
## plan
* 读代码
  + no rmap:
  + pte chain:
    ```
    commit c48c43e6ed41a3bcec0155e8e4b8440a9a769a0a
    Author: Andrew Morton <akpm@zip.com.au>
    Date:   Thu Jul 18 21:08:35 2002 -0700

    [PATCH] minimal rmap
    ```
  + anon_vma:
  + anon_vma_chain:
* 看mail
* 写文章

## 参考链接
1. [The case of the overly anonymous anon_vma](https://lwn.net/Articles/383162/)
2. [Virtual Memory II: the return of objrmap](https://lwn.net/Articles/75198/)
3. [RFC anon_vma previous (i.e. full objrmap)](https://lwn.net/Articles/75098/)
4. [匿名反向映射的前世今生](https://richardweiyang-2.gitbook.io/kernel-exploring/nei-cun-guan-li/00-index/01-anon_rmap_history)



<!-- 2002-07-17 -->
5. [\[patch 1/13\] minimal rmap](https://lore.kernel.org/all/3D3500AA.131CE2EB@zip.com.au/)

<!-- 2002-08-02 -->
[[PATCH] Rmap speedup](https://lore.kernel.org/all/E17aiJv-0007cr-00@starship/)

<!--2004-02-04-->
2.4.23aa1 
https://lkml.iu.edu/0312.0/0977.html

2004-02-03
2.4.23 includes Andrea's VM?
https://lkml.iu.edu/0312.0/0502.html
似乎不安装aa的补丁, 在12G内存内核, 就会因为内存不足崩溃??

2004-02-27
2.4.23aa2 (bugfixes and important VM improvements for the high end)
https://lore.kernel.org/all/20040227013319.GT8834@dualathlon.random/

<!-- 2004-01-20 Rik van Riel --->

[[PATCH] 2.4.25-pre6-rmap15](https://lore.kernel.org/all/Pine.LNX.4.44.0401200810560.15071-100000@chimarrao.boston.redhat.com/)

<!-- 2004-03-03 -->
[230-objrmap fixes for 2.6.3-mjb2](https://lore.kernel.org/all/20040303070933.GB4922@dualathlon.random/)

<!--2004-03-08-->
[objrmap-core-1 (rmap removal for file mappings to avoid 4:4 in <=16G machines)](https://lore.kernel.org/all/20040308202433.GA12612@dualathlon.random/)

<!--2004-03-11-->
[anon_vma RFC2](https://lore.kernel.org/all/20040311065254.GT30940@dualathlon.random/)

<!--2004-03-18-->
[\[PATCH\] anobjrmap 1/6 objrmap](https://lore.kernel.org/all/Pine.LNX.4.44.0403182317050.16911-100000@localhost.localdomain/)


<!--2004-03-21 -->

[[RFC][PATCH 1/3] radix priority search tree - objrmap complexity fix](https://lore.kernel.org/all/Pine.GSO.4.58.0403211634350.10248@azure.engin.umich.edu/)

<!--2004-04-08-->
[\[PATCH\] rmap 1 linux/rmap.h](https://lore.kernel.org/all/Pine.LNX.4.44.0404082349580.1586-100000@localhost.localdomain/#t)


## other
1. 似乎在这个版本引入的 inactive list
```
commit dfc52b82fee5bc6713ecce3f81767a8565c4f874
Author: Linus Torvalds <torvalds@athlon.transmeta.com>
Date:   Mon Feb 4 20:18:59 2002 -0800

    v2.4.9.11 -> v2.4.9.12

      - Alan Cox: much more merging
      - Pete Zaitcev: ymfpci race fixes
      - Andrea Arkangeli: VM race fix and OOM tweak.
      - Arjan Van de Ven: merge RH kernel fixes
      - Andi Kleen: use more readable 'likely()/unlikely()' instead of __builtin_expect()
      - Keith Owens: fix 64-bit ELF types
      - Gerd Knorr: mark more broken PCI bridges, update btaudio driver
      - Paul Mackerras: powermac driver update
      - me: clean up PTRACE_DETACH to use common infrastructure
```
2. [aa 在2.4版本大改了 vm 子系统](https://lwn.net/Articles/73100/)
3. [Kernel development - Time to thrash the 2.6 VM?](https://lwn.net/Articles/73100/)
4. [The object-based reverse-mapping VM](https://lwn.net/Articles/23732/)

> 2003-02-20 16:13 Dave McCracken  发布了在2.5.62的完整的patch, 之前就有过很多关于objrmap的讨论
>
> COMMIT message如下
>> There's been a fair amount of discussion about the advantages of doing
>> object-based rmap.  I've been looking into it, and we have the pieces to do
>> it for file-backed objects, ie the ones that have a real address_space
>> object pointed to from struct page.  The stumbling block has always been
>> anonymous pages.
>> 
>> At Martin Bligh's suggestion, I coded up an object-based implementation for
>> non-anon pages while leaving the pte_chain code intact for anon pages.  My
>> fork/exit microbenchmark shows roughly 50% improvement for tasks that are
>> composes of file-backed and/or shared pages.  This is the code that Martin
>> included in 2.5.62-mjb2 and reported his performance results on.
>>
>> 翻译:
>> 

>> 关于采用基于对象的 rmap 的优点，已经有了相当多的讨论。我对此进行了研究，我们
>> 已经具备了在 file-backed objects（即那些 struct page 指向实际 address_space
>> 对象的页面）上实现这一方案的条件。一直以来的难点都在于 anonymous pages。


>> 按照 Martin Bligh 的建议，我为非匿名页实现了一个基于对象的实现，同时对匿名页
>> 仍然保留了 pte_chain 代码。我的 fork/exit 微基准测试显示，对于由 file-backed
>> and/or share pages组成的任务，性能大约提升了 50%。这就是 Martin 收录进 2.5.62-mjb2
>> 并报告其性能结果的那段代码。
>
> 该patch针对file-backed 编写的, 匿名页还是使用pte_chain, 在file-backed / share
> pages组成的测试fork/exit的基准测试，性能大约提升50%

5. [Partial object-based rmap implementation](https://lore.kernel.org/linux-mm/Pine.LNX.4.50L.0302201415070.2329-100000@imladris.surriel.com/T/#mb31000287ab1bdcd0bf27be28a5d8d4e9e753b17)
5. [Full updated partial object-based rmap](https://lore.kernel.org/all/135130000.1045781211@baldur.austin.ibm.com/)

> Rik van Riel 关于objrmap 发表了自己的看法
>
> 大概的意思是关于objrmap确实是有优势，但是劣势也是有的
>> Unfortunately, not nearly as much about the disadvantages.

>> There are big advantages and disadvantages to both ways of
>> doing reverse mappings. I'm planning to write about both
>> for my OLS paper and analise the algorithmic complexities
>> in more detail so we've got a better idea of exactly what
>> we're facing.
>> 
>> 对这两种实现反向映射的方法，各自都有很大的优缺点。我打算在我的 OLS 论文中详
>> 细写一写这两种方案，并对它们的算法复杂度做更深入的分析，这样我们就能更清楚地
>> 了解我们到底要面对什么问题了。
>>
>> 

> Rik 他说他要写一个ols paper来讨论，见下面 <<Towards an O(1) VM>>
5. [Re: \[PATCH 2.5.62\] Partial object-based rmap implementation](https://lore.kernel.org/linux-mm/Pine.LNX.4.50L.0302201415070.2329-100000@imladris.surriel.com/)

> 2003-02-20 4:25 Martin J. Bligh 测试了 object-based rmap 补丁，取得了良好的结果
6. [Performance of partial object-based rmap](https://lore.kernel.org/all/7490000.1045715152@%5B10.10.2.4%5D/#t)

> 2023-02-20 11:51 Martin J. Bligh 发布了纳入 partial_objramp的第一个patch包 -- 2.5.61-mjb2
[2.5.61-mjb2 (scalability / NUMA patchset)](https://lwn.net/Articles/23259/)

> 2003-02-24 akpm 将 Object-based RMA 放入2.5.62-mm3 这也是我这边找到的第一个有迹可循的 linux版本
8. [2.5.62-mm3](https://lore.kernel.org/linux-mm/20030223230023.365782f3.akpm@digeo.com/)

> 2002-09-17 Peter Wong 发现了pte_chain rmap 内存占用较高的问题
7. [Examining the Performance and Cost of Revesemaps on 2.5.26 Under Heavy DB Workload](https://lore.kernel.org/all/OF6165D951.694A9B41-ON85256C36.00684F02@pok.ibm.com/)

> 2003-07-23,26 Proceedings of the Linux Symposium -- Rik van Riel
* [Towards an O(1) VM:](https://www.kernel.org/doc/ols/2003/ols2003-pages-367-372.pdf)

> 2003-07-23 2003 kernel Summit : Reverse mapping performance improvements
* [2003 Kernel Summit: Reverse mapping performance improvements](https://lwn.net/Articles/40796/)
