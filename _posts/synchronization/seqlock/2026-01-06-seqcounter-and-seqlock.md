---
layout: post
title:  "sequences counters and sequential locks"
author: fuqiang
date:   2026-01-07 16:35:00 +0800
categories: [os, synchronization]
tags: [os, synchronization, seqlock]
media_subpath: /_posts/synchronization/seqlock
math: true
---

## introduce

> **_Definination of sequence_**:
>
> In mathematics, a sequence is an infinite list $x_1, x_2, x_3$, ... (Sometimes
> finite lists are also called sequences) <sup>2</sup>
>
> > 大概的意思是序列是一个无限列表。而counter的含义是一个计数器。计数器的特点是
> > 计数前后的差值为1。那么 sequence counter 的特点是, $0,1,2,3 ...$  这样的一个
> >列表。
> {: .prompt-tip}
{: .prompt-ref}

sequences counters/locks 是一种 reader-writer  consistency
mechanism, 特点是 lockless readers(read-only retry loops),
不会有写饥饿。

> <sup>1</sup> 原文是
>
> ```
> Sequence counters are a reader-writer consistency mechanism with lockless
> readers (read-only retry loops), and no writer starvation.
> ```
> {: .prompt-ref}
>
> 关于`reader-writer consistency`，我自己的理解:
> > 大家可以想象下，完整性是对谁而言的? writer？
> > 
> > NONONO, 对于写者而言，本身没有什么一致性可言，其只负责将数据写入, 不负责
> > 观测该object完整性. 而对于读者而言肯定需要确保观测到完整的数据。
> {: .prompt-tip}
>
> 所以, 这个机制有点类似于RCU。但和RCU 达成的效果却截然相反，rcu为 lockess
> writers, no read starvation
{: .prompt-info}

该方法适合读多写少的场景, 读者愿意为读取到一致性的信息在信息发生变化时重试。

## 实现方法

`sequneces counters` 实现起来很简单:
* 读者端临界区开始处读取到偶数的序列数，并且在临界区结束处读取到相同的序列数则
  可以认为数据是一致的。否则，需要发起重试。
* 写者端, 在临界区开始处将序列号变更为奇数，并在临界区结束时将序列号变更为偶数。

内核中的同步机制，在一侧出现类似于自旋阻塞时，要很小心处理这部分。防止死锁。
这种情况一般发生在其互斥部分被强行中断，切换上下文执行到该阻塞部分。发生上下文
切换的上下文有:

* bottom half
* interrupt
* NMI
* preempt-schedule

而 `sequnece counters`场景阻塞部分为reader，和reader互斥部分为writer。所以，
**reader 绝不能抢占/中断 writer的执行! 否则如前面所说，会造成死锁**

```
writer                       reader
sequence_counter++
 sequence_counter is odd
 writing...
                             broken by interrupt
                             spin wait sequence_counter 
                             become even...
can't return back..
  write done
  sequence_count++
```

另外, 如果受保护的数据是指针，则不能使用该机制，因为writer可能因为reader正在跟踪
指针而失败..

> 为什么非指针可以，但是指针不行. 我们想象一个场景
>
> 非指针
> ```
> reader                     writer
> enter read crtial section
> LOOP:
>   A = s.a;
>   B = s.b;
>                            sequence_counter++
>                            s.a=xxx;s.b=xxx;s.c=xxx;
>                            sequence_counter++
>   C = s.c;
> sequence_counter change
>   goto LOOP;
>                            DO NOTHING FOR sequence counter
> ```
>
> 指针:
> ```
> reader                     writer
> enter read crtial section
> LOOP:
>   A = s->a;
>   B = s->b;
>                            sequence_counter++
>                            tmp_s->a=xxx, tmp_s->b=xxx, tmp_s->c=xxx;
>                            old_s=s
>                            CAN do s=tmp_s, release s..
>                              NO! the reader is in crtial section..just faulted
>                            sequence_counter++
>   C = s->c;
> sequence_counter change
>   goto LOOP;
> ```
>
> 可以看到只要用到了指针。就需要等待读者完整，倒反天罡了这是... 另外这种情况下,
> 一般采用RCU 算法。
{: .prompt-tip}

`sequence counters` 有很多的变体:
* seqcount_t(本体)
* seqcount_LOCKNAME_t
* seqcount_latch_t
* seqlock_t

我们分别介绍下:

## sequence counter (seqcount_t)

这仅是一个原始的计数机制，无法满足多个写者同时写入. 如果有多个写者，需要调用者
自己通过外部锁串行写操作。

另外, 如果 写入序列化接口未隐式关抢占，则

## 参考链接
1. [Sequence counters and sequential locks](https://docs.kernel.org/locking/seqlock.html)
2. [Sequence wiki](https://chita.us/wikipedia/nost/index.pl?Sequence)
