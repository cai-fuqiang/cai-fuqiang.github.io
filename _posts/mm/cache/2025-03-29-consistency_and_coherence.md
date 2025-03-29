---
layout: post
title:  "CHAPTER 1 Introduction to Consistency and Coherence"
author: fuqiang
date:   2025-03-29 10:42:00 +0800
categories: [cache]
tags: [cache]
---

##  1.2 COHERENCE (A.K.A., CACHE COHERENCE)

Unless care is taken, a coherence problem can arise if multiple actors (e.g.,
multiple cores) have access to multiple copies of a datum (e.g., in multiple
caches) and at least one access is a write. Consider an example that is similar
to the memory consistency example. A student checks the online schedule of
courses, observes that the Computer Architecture course is being held in Room
152 (reads the datum), and copies this information into her calendar app in her
mobile phone (caches the datum). Subsequently, the university registrar decides
to move the class to Room 252, updates the online schedule (writes to the
datum) and informs the students via a text message. The student’s copy of the
datum is now stale, and we have an incoherent situation. If she goes to Room
152, she will fail to find her class. Examples of incoherence from the world of
computing, but not including computer architecture, include stale web caches
and programmers using un-updated code repositories.

> 除非小心处理，否则当多个执行者（例如，多个核心）可以访问数据的多个副本（例如，
> 在多个缓存中）并且至少有一个访问是写操作时，可能会出现 coherence 问题。考虑一个
> 类似于 memory consistency 问题的例子。一个学生查看在线课程表，发现计算机体系结
> 构课程在152教室上课（读取数据），并将此信息复制到她手机上的日历应用程序中（缓存数据）。
> 随后，大学注册主任决定将课程移至252教室，更新了在线课程表（写入数据）并通过短信通知
> 学生。此时，学生的数据副本已经过时，导致了一个 incoherent 的情况。如果她去152教室，
> 就找不到她的课。来自计算机世界的 incoherence 例子（但不包括计算机体系结构）包括过时
> 的网页缓存和程序员使用未更新的代码库。

Access to stale data (incoherence) is prevented using a coherence protocol,
which is a set of rules implemented by the distributed set of actors within a
system. Coherence protocols come in many variants but follow a few themes, as
developed in Chapters 6–9. Essentially, all of the variants make one
processor’s write visible to the other processors by propagating the write to
all caches, i.e., keeping the calendar in sync with the online schedule. But
protocols differ in when and how the syncing happens. There are two major
classes of coherence protocols. In the first approach, the coherence protocol
ensures that writes are propagated to the caches synchronously. When the online
schedule is updated, the coherence protocol ensures that the student’s calendar
is updated as well. In the second approach, the coherence protocol propagates
writes to the caches asynchronously, while still honoring the consistency
model. The coherence protocol does not guarantee that when the online schedule
is updated, the new value will have propagated to the student’s calendar as
well; however, the protocol does ensure that the new value is propagated before
the text message reaches her mobile phone. This primer focuses on the first
class of coherence protocols (Chapters 6–9) while Chapter 10 discusses the
emerging second class.

> 访问过时数据（即 incoherence）通过 coherence 协议来防止，coherence 协议是
> 一组由系统中的分布式执行者实现的规则。Coherence 协议有多种变体，但遵循几
> 个基本主题，这些主题在第6到第9章中进行了讨论。本质上，所有变体都通过将一个
> 处理器的写操作传播到所有缓存，使其他处理器能够看到该写操作，也就是说，保持
> 日历与在线课程表同步。但协议在同步发生的时间和方式上有所不同。Coherence 
> 协议主要分为两大类。第一种方法中，coherence 协议确保写操作同步传播到缓存
> 中。当在线课程表被更新时，coherence 协议确保学生的日历也被更新。第二种方
> 法中，coherence 协议在遵循一致性模型的同时，异步地将写操作传播到缓存。
> Coherence 协议不保证在线课程表更新时，新值会立即传播到学生的日历；然而，
> 协议确保在短信到达她手机之前，新值已经传播。本入门书着重于第一类 
> coherence 协议（第6到第9章），而第10章讨论了新兴的第二类。

>> 
{:. prompt-tip}

## 1.3 CONSISTENCY AND COHERENCE FOR HETEROGENEOUS SYSTEMS

Modern computer systems are predominantly heterogeneous. A mobile phone
processor today not only contains a multicore CPU, it also has a GPU and other
accelerators (e.g., neural net- work hardware). In the quest for
programmability, such heterogeneous systems are starting to support shared
memory. Chapter 10 deals with consistency and coherence for such heteroge-
neous processors.

> ```
> predominantly: 主要的
> heterogeneous: 各种各样的
>   结合起来翻译：以异构为主的，这通常指的是由不同类型的组件（如不同种类的处理器
>   或加速器）组成的系统，其中异构性是其主要特征。
> ```
>
> 现代计算机系统主要是异构的。如今的手机处理器不仅包含多核 CPU，还包括 GPU
> 和其他加速器（例如神经网络硬件）。为了实现可编程性，这样的异构系统开始支持共享内存。第
> 10 章讨论了这种异构处理器的一致性和一致性问题。

The chapter starts by focusing on GPUs, arguably the most popular accelerators
today. The chapter observes that GPUs originally chose not to support hardware
cache coherence, since GPUs are designed for embarrassingly parallel graphics
workloads that do not synchronize or share data all that much. However, the
absence of hardware cache coherence leads to programmability and/or
performance challenges when GPUs are used for general-purpose work- loads with
fine-grained synchronization and data sharing. The chapter discusses in detail
some of the promising coherence alternatives that overcome these limitations—in
particular, explaining why the candidate protocols enforce the consistency
model directly rather than implementing coherence in a consistency-agnostic
manner. The chapter concludes with a brief discussion on consistency and
coherence across CPUs and the accelerators.

> ```
> promising : 有前景的，有前途的
> promising coherence alternatives: 有前景的一致性替代方案/有前途的一致性替代方案
> ```
> 本章首先关注 GPU，GPU 可以说是当今最流行的加速器。本章指出，GPU
> 最初选择不支持硬件 cache coherence，因为 GPU
> 设计用于尴尬并行的图形工作负载，这类工作负载通常不需要太多的同步或数据共享。然而，当
> GPU 被用于具有细粒度同步和数据共享的通用工作负载时，缺乏硬件 cache coherence
> 会导致可编程性和/或性能方面的挑战。本章详细讨论了一些有前景的 coherence
> 替代方案，这些方案克服了这些限制，特别是解释了为什么候选协议直接强制执行
> consistency 模型，而不是以与 consistency 无关的方式实现
> coherence。本章最后简要讨论了在 CPU 和加速器之间的 consistency 和 coherence
> 问题。

## 1.4 SPECIFYING AND VALIDATING MEMORY CONSISTENCY MODELS AND CACHE COHERENCE

Consistency models and coherence protocols are complex and subtle. Yet, this
complexity must be managed to ensure that multicores are programmable and that
their designs can be validated. To achieve these goals, it is critical that
consistency models are specified formally. A formal specification would enable
programmers to clearly and exhaustively (with tool support) understand what
behaviors are permitted by the memory model and what behaviors are not. Second,
a precise formal specification is mandatory for validating implementations.

> consistency models 和 coherence protocols 是复杂而微妙的。然而，必须管理这种
> 复杂性以确保多核处理器的可编程性及其设计的可验证性。为了实现这些目标，至关重
> 要的是要正式指定 consistency models。正式的规范将使程序员能够清晰而全面地
> （借助工具支持）理解内存模型允许和不允许的行为。其次，精确的正式规范对于验证
> 实现是必不可少的。

Chapter 11 starts by discussing two methods for specifying systems—axiomatic
and operational—focusing on how these methods can be applied for consistency
models and coherence protocols. Then the chapter goes over techniques for
validating implementations— including processor pipeline and coherence protocol
implementations—against their specification. The chapter discusses both
formal methods and informal testing.

> ```
> formal: 正式的
> ```
> 第十一章首先讨论了两种用于指定系统的方法——公理化方法和操作性方法，重点介绍了如何
> 将这些方法应用于 consistency models 和 coherence protocols。接着，本章探讨了验证
> 实现的方法，包括处理器流水线和 coherence protocol 实现与其规范的对比验证。本章讨
> 论了正式方法和非正式测试两方面的内容。

## 1.5 A CONSISTENCY AND COHERENCE QUIZ

It can be easy to convince oneself that one’s knowledge of consistency and
coherence is sufficient and that reading this primer is not necessary. To test
whether this is the case, we offer this pop quiz.

> 人们很容易说服自己认为对 consistency 和 coherence 的了解已经足够，不需要阅读这本
> 入门书。为了测试是否真是如此，我们提供了一个小测验。

> 该部分为阅读本书之前, 自己的思考
{: .prompt-tip}

> 该部分为走读完本书之后，总结书中的内容
{: .prompt-info}

Question 1: In a system that maintains sequential consistency, a core must
issue coherence requests in program order. True or false? (Answer is in Section
3.8)

> 处理器为了充分利用流水线，往往会做一些优化。例如write buffer。处理器会定义一套
> consistency 策略，例如x86 TSO 就定义了write-store 可以乱序，这都会导致处理器 
> issue conherence request 和program order 不同.
{: .prompt-tip}

Question 2: The memory consistency model specifies the legal orderings of
coherence transactions. True or false? (Section 3.8)

> 个人认为是对的。本身其就是定义规则，然后cache coherence 实现时，需要遵守这些
> 规则
{: .prompt-tip}

Question 3: To perform an atomic read–modify–write instruction (e.g.,
test-and-set), a core must always communicate with the other cores. True or
false? (Section 3.9)

> atomic read-modify-write 个人认为是在read时，去 exclusive 该cacheline, 然后
> 阻塞总线上其他的 write message, 直到该cpu的write动作完成，所以不需要always 
> communicate，例如: 如果该cache本身就是 exclusive的话，直接"lock" and modify
> 就可以了。
{: .prompt-tip}

Question 4: In a TSO system with multithreaded cores, threads may bypass values
out of the write buffer, regardless of which thread wrote the value. True or
false? (Section 4.4)

> 个人认为是不对的. 首先当前线程肯定不会bypass write buffer, 其相当于bypass memory
> 直接从write buffer中获取到值。
>
> 另外，另一个thread也可以从write buffer中load value。因为write buffer 会导致store
> 动作延后，而如果该core上的另一个thread bypass memory, 相当于其看到该core没有out of
> order，如下图
> ```
> --------------------+---------------------
> core 0 thread 1     |core 0 thread 2
> --------------------+---------------------
> P.W                 |
>                     |
>                     | R2: read new value
> R1                  | 
>                     |
>                     |
> M.W                 |
> ```
>
> * P.W 表示按照程序顺序发生写操作的点
> * M.W 表示该写动作发生在全局（memory）view 上的点
>
> 在上图中R2相当于 bypass memory, 在其看来 core 0 
> thread 1 上的P.W 的动作比R1 要早
{: .prompt-tip}

Question 5: A programmer who writes properly synchronized code relative to the
high-level language’s consistency model (e.g., Java) does not need to consider
the architecture’s memory consistency model. True or false? (Section 5.9)

> 如果java在每条指令中间都夹杂着内存屏障指令，就可以不用关心memory consistency，
> 但显然这是不可能的
{: .prompt-tip}

Question 6: In an MSI snooping protocol, a cache block may only be in one of
three coherence states. True or false? (Section 7.2)

> YES. 虽然感觉很可能不对。但认知就到这里。
{: .prompt-tip}

Question 7: A snooping cache coherence protocol requires the cores to
communicate on a bus. True or false? (Section 7.6)

> communicate on bus 在cpu特别多，尤其是某些cpu路径很长的情况下，效率会很低，
> 所以后续推出了 diectory-based conherence protocals
{: .prompt-tip}

Question 8: GPUs do not support hardware cache coherence. Therefore, they are
unable to enforce a memory consistency model. True or False? (Section 10.1).

> 如果没有支持cache coherence ，就意味着其没有办法snoop 到 CPU或者其他agent的
> 对cache的行为。但是其也需要遵守一定的 coherence， 例如GPU 做两个动作，store A，
> store B。 其一定需要保证GPU在内存上的操作顺序是上面描述的顺序。(memory consistency
> 是多个并行操作对象对一个share resource(memory) 的操作原则. 而cache conherence
> 只是实现它的一个手段。
{: .prompt-tip}

Even though the answers are provided later in this primer, we encourage readers
to try to answer the questions before looking ahead at the answers.

## 1.6 WHAT THIS PRIMER DOES NOT DO

This lecture is intended to be a primer on coherence and consistency. We expect
this material could be covered in a graduate class in about ten 75-minute
classes (e.g., one lecture per Chapter 2 to Chapter 11).

For this purpose, there are many things the primer does not cover. Some of
these include the following.

> 这堂课旨在作为coherence和consistency的入门课程。我们预计这些内容可以在研究
> 生课程中用大约十节75分钟的课程来覆盖（例如，每章从Chapter2到Chapter 11一节课）。

> 出于这个目的，有许多内容在这本入门教材中没有涉及。其中一些包括以下内容。

+ Synchronization. Coherence makes caches invisible. Consistency can make
  shared mem- ory look like a single memory module. Nevertheless, programmers
  will probably need locks, barriers, and other synchronization techniques to
  make their programs useful. Read- ers are referred to the Synthesis Lecture
  on Shared-Memory synchronization [2].
  > 同步。Coherence使缓存对程序员不可见。Consistency可以使共享内存看起来像
  > 是一个单一的内存模块。然而，程序员可能仍然需要使用锁、屏障和其他同步技
  > 术来使他们的程序有效。读者可以参考《Synthesis Lecture on Shared-Memory
  > Synchronization》来获取更多信息。

+ Commercial Relaxed Consistency Models. This primer does not cover the
  subtleties of the ARM, PowerPC, and RISC-V memory models, but does describe
  which mechanisms they provide to enforce order.

  > 商业化的放松一致性模型。本入门教材不涉及ARM、PowerPC和RISC-V内存模型的细节，
  > 但描述了它们提供的用于强制顺序的机制。


+ Parallel programming. This primer does not discuss parallel programming
  models, methodologies, or tools.
  > 并行编程。本入门教材不讨论并行编程模型、方法或工具。

+ Consistency in distributed systems. This primer restricts itself to
  consistency within a shared memory multicore, and does not cover consistency
  models and their enforcement for a general distributed system. Readers are
  referred to the Synthesis Lectures on Database Replication [1] and Quorum
  Systems [3].
  > 分布式系统中的一致性。本入门教材仅限于共享内存多核中的一致性，不涵盖一般分
  > 布式系统的一致性模型及其实施。读者可以参考《Synthesis Lectures on Database
  > Replication》和《Quorum Systems》来获取更多信息。

