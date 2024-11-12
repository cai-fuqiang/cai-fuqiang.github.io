---
layout: post
title:  "[Translate]: Migration auto-converge problem"
author: fuqiang
date:   2024-11-12 23:20:00 +0800
categories: [live_migration,auto-converge]
tags: [autoconverge]
---

```
From: "Jason J. Herne" <jjherne@linux.vnet.ibm.com>
To: "qemu-devel@nongnu.org qemu-devel" <qemu-devel@nongnu.org>,
	Christian Borntraeger <borntraeger@de.ibm.com>
Subject: [Qemu-devel] Migration auto-converge problem
Date: Mon, 02 Mar 2015 16:04:54 -0500
```

We have a test case that dirties memory very very quickly. When we run this
test case in a guest and attempt a migration, that migration never converges
even when done with auto-converge on.

> 我们有一个测试用例会非常快速地修改内存。当我们在虚拟机中运行此测试并尝试迁移时，
> 即使开启了`auto-converge` 功能，迁移仍然无法收敛。

The auto converge behavior of Qemu functions differently purpose than I had
expected. In my mind, I expected auto converge to continuously apply adaptive
throttling of the cpu utilization of a busy guest if Qemu detects that progress
is not being made quickly enough in the guest memory transfer. The idea is that
a guest dirtying pages too quickly will be adaptively slowed down by the
throttling until migration is able to transfer pages fast enough to complete
the migration within the max downtime. Qemu's current auto converge does not
appear to do this in practice.

> QEMU 的自动收敛行为与我预期的有所不同。我的设想是，当 QEMU 检测到虚拟机内存
> 传输进展不足时，auto-converge 会持续 **自适应** 地限制虚拟机的 CPU 利用率。这样，
> 对于那些脏页速度过快的虚拟机，自适应的限速将逐步降低其速度，直到迁移速度足
> 够快，能在最大停机时间内完成迁移。然而，QEMU 当前的自动收敛机制在实际操作中
> 似乎并未实现这一点。

A quick look at the source code shows the following:

> 查看源码后，逻辑如下:

- Autoconverge keeps a counter. This counter is only incremented if, for a
  completed memory pass, the guest is dirtying pages at a rate of 50% (or more)
  of our transfer rate.
- The counter only increments at most once per pass through memory.
- The counter must reach 4 before any throttling is done. (a minimum of 4
  memory passes have to occur) - Once the counter reaches 4, it is immediately
  reset to 0, and then throttling action is taken. - Throttling occurs by doing
  an async sleep on each guest cpu for 30ms, exactly one time.

> * 自动收敛维持一个计数器。仅当一个内存传输周期完成时，虚拟机脏页速率达到传输速率的 
>   50% 或以上，计数器才会增加。
> * 每个内存传输周期内计数器最多增加一次。
> * 计数器需达到 4 才会触发限速（即至少经历 4 个内存传输周期）-- 一旦计数器达到 4，
>   它会立即重置为 0，然后执行限速操作。

Now consider the scenario auto-converge is meant to solve (I think): A guest
touching lots of memory very quickly. Each pass through memory is going to be
sending a lot of pages, and thus, taking a decent amount of time to complete.
If, for every four passes, we are *only* sleeping the guest for 30ms, our guest
is still going to be able dirty pages faster than we can transfer them. We will
never catch up because the sleep time relative to guest execution time is very
very small.

> 现在考虑 auto-converge 所要解决的场景（我认为）：虚拟机快速修改大量内存。
> 在这种情况下，每次内存传输周期都会涉及大量页传输，因此需要相当长的时间才能完成。
> 如果每四个周期我们仅将虚拟机暂停 30 毫秒，那么虚拟机仍然可以比传输速度更快地修
> 改页。我们永远无法赶上，因为相对于虚拟机的执行时间，暂停时间非常短。

Auto converge, as it is implemented today, does not address the problem I
expect it solve. However, after rapid prototyping a new version of auto
converge that performs adaptive modeling I've learned something. The workload
I'm attempting to migrate is actually a pathological case. It is an excellent
example of why throttling cpu is not always a good method of limiting memory
access. In this test case we are able to touch over 600 MB of pages in 50 ms of
continuous execution. In this case, even if I throttle the guest to 5% (50ms
runtime, 950ms sleep) we still cannot even come close to catching up even with
a fairly speedy network link (which not every user will have).

> 当前 auto-converge 的实现并未解决我预期的问题。然而，在快速原型实现了一个执行
> 自适应建模的新版本后，我了解到了一些情况。实际上，我尝试迁移的工作负载是一个
> “病理”案例，它很好地说明了限速 CPU 并非限制内存访问的理想方法。在这个测试用例中，
> 虚拟机在 50 毫秒连续运行时间内可以修改超过 600 MB 的页。即便将虚拟机限速至 
> 5%（50 毫秒运行，950 毫秒暂停），我们仍无法赶上数据传输，即便使用了较高速度的网络连接
> （并不是所有用户都有这样的条件）。

Given the above, I believe that some workloads touch memory too fast and we'll
never be able to live migrate them with auto-converge. On the lower end there
are workloads that have a very small/stagnant working set size which will be
live migratable without the need for auto-converge. Lastly, we have "the
nebulous middle". These are workloads that would benefit from auto-converge
because they touch pages too fast for migration to be able to deal with them,
AND (important conditional here), throttling will(may?) actually reduce their
rate of page modifications. I would like to try and define this "middle" set of
workloads.

> 基于上述情况，我认为有些工作负载的内存修改速度过快，使用 auto-converge 无法实现实
> 时迁移。在低端情况中，工作负载的工作集很小且变化不大，无需 auto-converge 就可以迁
> 移成功。最后是所谓的“模糊中间层”。这类工作负载能够受益于 auto-converge，因为它们
> 的内存修改速度超出了迁移处理能力，并且（这是个关键条件）限速可能（？）会降低其页
> 修改速率。我希望能够定义这一“中间层”工作负载的特征。

A question with no obvious answer: How much throttling is acceptable? If I have
to throttle a guest 90% and he ends up failing 75% of whatever transactions he
is attempting to process then we have quite likely defeated the entire purpose
of "live" migration. Perhaps it would be better in this case to just stop the
guest and do a non-live migration. Maybe by reverting to non-live we actually
save time and thus more transactions would have completed. This one may take
some experimenting to be able to get a good idea for what makes the most sense.
Maybe even have max throttling be be user configurable.

> 一个没有明确答案的问题：究竟多少限速是可以接受的？如果我需要对虚拟机限速 90%，
> 而它最终有 75% 的事务处理失败，那我们很可能已经完全违背了“实时”迁移的初衷。
> 在这种情况下，也许直接停止虚拟机并进行非实时迁移会更好。或许通过回退到非实时迁移，
> 我们实际上节省了时间，从而完成了更多的事务。这一点可能需要一些实验来更好地了解最
> 合理的策略。或许最大限速应让用户自行配置。

With all this said, I still wonder exactly how big this "nebulous middle"
really is. If, in practice, that "middle" only accounts for 1% of the workloads
out there then is it really worth spending time fixing it? Keep in mind this is
a two pronged test:

> 在这一切的前提下，我仍然想知道，这个“模糊中间层”究竟有多大。如果在实际操作中，
> 这个“中间层”只占所有工作负载的 1%，那么是否真的值得花费时间去优化呢？请记住，这是
> 一个双重(two pronged)测试：

1. Guest cannot migrate because it changes memory too fast
2. Cpu throttling slows guest's memory writes down enough such that he can now
   migrate

> 1. 虚拟机无法迁移，因为它修改内存的速度太快。
> 2. 通过限速虚拟机的 CPU，降低了虚拟机的内存写入速度，从而使得它现在可以迁移。

I'm interested in any thoughts anyone has. Thanks!


## other comment

### John Snow 

This is just a passing thought since I have not invested deeply in the 
live migration convergence mechanisms myself, but:

> passing thought: 随意的想法，随便的想法
>
> 这只是一个随便的想法，因为我自己没有深入研究实时迁移收敛机制，但是：

Is it possible to apply a progressively more brutish throttle to a guest 
if we detect we are not making (or indeed /losing/) progress?

> 如果我们检测到没有取得进展（甚至是在“失去”进展），是否可以对虚拟机应
> 用逐渐加剧的强力限速？

We could start with no throttle and see how far we get, then 
progressively apply a tighter grip on the VM until we make satisfactory 
progress, then continue on until we hit our "Just pause it and ship the 
rest" threshold.

> 我们可以从不限制开始，看看能进行多远，然后逐步对虚拟机施加更紧的限制，
> 直到取得满意的进展，然后继续进行，直到达到“就暂停它然后传输剩下的部分”
> 阈值。

That way we allow ourselves the ability to throttle very naughty guests 
very aggressively (To the point of effectively even paused) without 
disturbing the niceness of our largely idle guests. In this way, even 
very high throttle caps should be acceptable.

> 通过这种方式，我们允许在不打扰大多数空闲虚拟机的情况下，对那些“顽皮”的
> 虚拟机施加非常强烈的限速（甚至可能暂停）。这样，即便是非常高的限速上限
> 也应该是可以接受的。

This will allow live migration to "fail gracefully" for cases that are 
modifying memory or disk just too absurdly fast back to essentially a 
paused migration.

> 这将允许实时迁移在那些修改内存或磁盘速度过快的情况下“优雅地失败”，
> 实际上变成暂停状态的迁移。

I'll leave it to the migration wizards to explain why I am foolhardy.
--js

> 我将把它留给迁移专家来解释为什么我这么做太愚蠢。

## 相关链接
[原文链接](https://lore.kernel.org/all/54F4D076.3040402@linux.vnet.ibm.com/)
