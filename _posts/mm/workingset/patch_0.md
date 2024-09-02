The VM maintains cached filesystem pages on two types of lists.  One
list holds the pages recently faulted into the cache, the other list
holds pages that have been referenced repeatedly on that first list.
The idea is to prefer reclaiming young pages over those that have
shown to benefit from caching in the past.  We call the recently used
list "inactive list" and the frequently used list "active list".

> ```
> repeatedly: 重复说或写
> ```
> 虚拟内存（VM）将缓存的文件系统页面维护在两种类型的列表中。
> 一个列表保存最近被调入缓存的页面，另一个列表保存那些在第一个列表
> 中被反复引用的页面。其理念是优先回收那些较新的页面，而不是那些过
> 去已证明从缓存中受益的页面。我们将最近使用的列表称为“非活跃列表”，
> 将频繁使用的列表称为“活跃列表”。

The tricky part of this model is finding the right balance between
them.  A big inactive list may not leave enough room for the active
list to protect all the frequently used pages.  A big active list may
not leave enough room for the inactive list for a new set of
frequently used pages, "working set", to establish itself because the
young pages get pushed out of memory before having a chance to get
promoted.

> ```
> tricky: 棘手的;狡猾的;难办的; 诡计多端的
>   "Tricky" 在这个上下文中可以翻译为“棘手的”或“难以处理的”。它用来形容某
>   事很复杂或需要小心对待。根据上下文，"tricky part" 可以理解为“棘手的部
>   分” 或“难点”
>
> working set:
>   "Working set" 在计算机科学中通常指的是程序或进程在某个时间段内所需要访
>   问的一组页面或数据集合。它代表了该进程当前活跃的内存需求量。翻译成中文
>   可以是“工作集”。
> ```
> 这个模型的难点在于找到两者之间的平衡。一个较大的非活跃列表可能无法为活跃
> 列表留下足够的空间，以保护所有频繁使用的页面。而一个较大的活跃列表可能无
> 法为非活跃列表留下足够的空间，让一组新的频繁使用的页面（即“工作集”）得以
> 建立，因为年轻的页面在有机会被提升之前就被从内存中移出了。

Historically, every reclaim scan of the inactive list also took a
smaller number of pages from the tail of the active list and moved
them to the head of the inactive list.  This model gave established
working sets more gracetime in the face of temporary use once streams,
but was not satisfactory when use once streaming persisted over longer
periods of time and the established working set was temporarily
suspended, like a nightly backup evicting all the interactive user
program data.

> ```
> gracetime: 宽限时间
> satisfactory: 令人满意的
> persisted: 坚持;执意; 持续
> ```
> 历史上，每次扫描回收非活跃列表时，也会从活跃列表的末尾取出少量页面，
> 并将它们移动到非活跃列表的开头。这个模型在应对临时性的一次性使用流时，
> 为已建立的工作集提供了更多的gracetime，但当一次性使用流持续较长时间时，
> 这种方式并不令人满意，因为已建立的工作集会被暂时中断，例如夜间备份将
> 所有交互式用户程序数据驱逐出内存的情况。

Subsequently, the rules were changed to only age active pages when
they exceeded the amount of inactive pages, i.e. leave the working set
alone as long as the other half of memory is easy to reclaim use once
pages.  This works well until working set transitions exceed the size
of half of memory and the average access distance between the pages of
the new working set is bigger than the inactive list.  The VM will
mistake the thrashing new working set for use once streaming, while
the unused old working set pages are stuck on the active list.

> ```
> Subsequently: 随后的
> leave ... alone: 不要干涉, 保持... 不变
> ```
> 随后，规则被修改为仅当活跃页面的数量超过非活跃页面的数量时才对活跃页
> 面进行老化，也就是说，只要内存的另一部分能够轻松回收一次性使用的页面，
> 就不去动工作集。这种方法效果很好，直到工作集转换超过了内存的一半，并
> 且新工作集中页面之间的平均访问距离大于非活跃列表的大小。此时，虚拟内
> 存（VM）会将频繁切换的新工作集误认为是一次性使用的流式数据，而未使用
> 的旧工作集页面则会滞留在活跃列表上。

This happens on file servers and media streaming servers, where the
popular set of files changes over time.  Even though the individual
files might be smaller than half of memory, concurrent access to many
of them may still result in their inter-reference distance being
greater than half of memory.  It's also been reported as a problem on
database workloads that switch back and forth between tables that are
bigger than half of memory.  In these cases the VM never recognizes
the new working set and will for the remainder of the workload thrash
disk data which could easily live in memory.

> ```
> concurrent: 同时发生的
> ```
> 这种情况发生在文件服务器和媒体流服务器上，因为这些服务器上的热门文件
> 集会随着时间而变化。即使单个文件可能小于内存的一半，但同时访问许多文
> 件仍可能导致它们之间的引用距离大于内存的一半。这在数据库工作负载中也
> 被报告为一个问题，当数据库在大于内存一半的表之间来回切换时也会出现这
> 种情况。在这些情况下，虚拟内存（VM）无法识别新的工作集，并将在剩余的
> 工作负载中持续发生磁盘抖动（thrashing），即使这些数据本可以轻松地驻留
> 在内存中。

This series solves the problem by maintaining a history of pages
evicted from the inactive list, enabling the VM to tell streaming IO
from thrashing and rebalance the page cache lists when appropriate.

> 这一系列解决方案通过维护从非活跃列表中被驱逐页面的历史记录，使虚拟内存
> （VM）能够区分流式I/O和抖动（thrashing），并在适当的时候重新平衡页面缓存
> 列表。


# 参考链接:

https://lore.kernel.org/all/1375827778-12357-1-git-send-email-hannes@cmpxchg.org/
