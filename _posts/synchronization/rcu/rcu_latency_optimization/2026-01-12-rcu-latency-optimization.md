---
layout: post
title:  "rcu - rcu latency optimization"
author: fuqiang
date:   2026-01-12 22:13:00 +0800
categories: [os, synchronization]
tags: [os, synchronization, rcu]
media_subpath: /_posts/synchronization/rcu/rcu_latency_optimization
image: pic/merge_three_list_to_one.svg
math: true
---

## overflow

rcu callback 往往用来释放内存, 如果rcu callback调用的延迟比较高, 就会造成较高的
内存占用. 所以减少rcu callback的调用延迟也是一个很重要的优化方向。

## ORG PATCH

在最初的版本中, `rcu_data`中存放了两个链表
* `rcu_data->nxtlist`: 调用`call_rcu()` 向该链表存放数据
* `rcu_data->curlist`: 当`rcu_check_callbacks()`检测到`nxtlist`有成员但是
  `curlist`没有成员时，会将`nxtlist` 中的链表成员移动到`cur_list`中, 并且发起一个
  新的宽限期用来处理`curlist`中的数据。

两个链表均为 `list_head`数据结构，详细请看:

[rcu - classic](/posts/rcu-classic)

`list_head`为双向链表，大小为`2 * sizeof(struct list_head *)`, 大佬们感觉双向链表
有点浪费。于是将其修改为单链表。

## MODIFY list_head to single link list

修改方法也很简单, `rcu_head`修改`list_head` 为`struct rcu_head *`
```diff
 struct rcu_head {
-       struct list_head list;
+       struct rcu_head *next;
        void (*func)(void *obj);
        void *arg;
 };
```

`rcu_data` 中的链表头修改如下 :
```diff
@@ -99,8 +97,9 @@ struct rcu_data {

        /* 2) batch handling */
         long           batch;           /* Batch # for current RCU batch */
-        struct list_head  nxtlist;
-        struct list_head  curlist;
+        struct rcu_head *nxtlist;
+       struct rcu_head **nxttail;
+        struct rcu_head *curlist;
 };
```

> `rcu_data` 中的 `nxtlist` 修改为 `nxtlist`, `nxttail`, 为什么要增加`nxttail`呢,
> 因为调用`call_rcu()`添加 成员的时候，要访问tail. 这是单链表的常规操作。
{: .prompt-tip}

修改后，数据结构图如下:

![single_list](pic/single_list.svg)

## reduce the latency caused by RCU tasklets

但是随后大佬又发现, 如果`call_rcu()`调用比较频繁, 会造成`rcu tasklet`执行时间比
较长，从而造成其他流程较大延迟。于是大佬想给每次调用`rcu tasklet`设置一个最大处
理 `callback`的个数限制, 从而变相限制`rcu tasklet`的单次处理时长。

首先我们自己思考下, 如何实现这一目的:
* 既然要限制`rcu tasklet` 的处理个数, 也就意味着一次调用中，`curlist`会处理不完.
  这时需要另一个链表来记录未处理完的`curlist`.
* 另外, 为了减少延迟，我们需要及时清空`curlist`.
* 我们需要在因为处理个数限制而被动退出处理流程时，主动再次唤醒`rcu tasklet`

OK, 我们来看下大佬实现:

<details markdown=1 open>
<summary>donelist patch 细节展开</summary>

`rcu_data` 中增加额外链表，来记录未处理的rcu callback.
```diff
@@ -99,6 +99,8 @@ struct rcu_data {
        struct rcu_head **nxttail;
         struct rcu_head *curlist;
         struct rcu_head **curtail;
+        struct rcu_head *donelist;
+        struct rcu_head **donetail;
 };
```

> `curtail` 也是在该系列patch中加入的，因为donetail 要访问curtail，下面会说
{: .prompt-info}

当我们检测到`RCU_curlist()` 所处的宽限期已经完成时, 则将`curlist`中的成员移动到
`donelist`:
```diff
@@ -261,11 +271,11 @@ void rcu_restart_cpu(int cpu)
 static void rcu_process_callbacks(unsigned long unused)
 {
        int cpu = smp_processor_id();
-       struct rcu_head *rcu_list = NULL;

        if (RCU_curlist(cpu) &&
            !rcu_batch_before(rcu_ctrlblk.completed, RCU_batch(cpu))) {
-               rcu_list = RCU_curlist(cpu);
+               *RCU_donetail(cpu) = RCU_curlist(cpu);
+               RCU_donetail(cpu) = RCU_curtail(cpu);
                RCU_curlist(cpu) = NULL;
                RCU_curtail(cpu) = &RCU_curlist(cpu);
        }
```
并且在`rcu_process_callbacks()`函数中，只要`donelist`中有成员，都会调用
`rcu_do_batch(cpu)`处理下:
```diff
@@ -300,8 +310,8 @@ static void rcu_process_callbacks(unsigned long unused)
                local_irq_enable();
        }
        rcu_check_quiescent_state();
-       if (rcu_list)
-               rcu_do_batch(rcu_list);
+       if (RCU_donelist(cpu))
+               rcu_do_batch(cpu);
 }
```

另外, `rcu_pending()`也修改了逻辑, `RCU_donelist()`为真说明上次处理中，因为处理
数量限制而被动退出，所以也认为有rcu相关事务需要处理:
```diff
 static inline int rcu_pending(int cpu)
 {
@@ -127,6 +131,9 @@ static inline int rcu_pending(int cpu)
        if (!RCU_curlist(cpu) && RCU_nxtlist(cpu))
                return 1;

+       if (RCU_donelist(cpu))
+               return 1;
+
```

最主要的，在`rcu_do_batch()`中增加处理数量限制的逻辑，如果达到限制，强行break
循环，并且唤醒`RCU_tasklet`等待下个`rcu tasklet`再处理。
```diff
-static void rcu_do_batch(struct rcu_head *list)
+static void rcu_do_batch(int cpu)
 {
-       struct rcu_head *next;
+       struct rcu_head *next, *list;
+       int count = 0;

+       list = RCU_donelist(cpu);
        while (list) {
-               next = list->next;
+               next = RCU_donelist(cpu) = list->next;
                list->func(list);
                list = next;
+               if (++count >= maxbatch)
+                       break;
        }
+       if (!RCU_donelist(cpu))
+               RCU_donetail(cpu) = &RCU_donelist(cpu);
+       else
+               tasklet_schedule(&RCU_tasklet(cpu));
 }
```
</details>

相关图示如下:

<details markdown=1 open>
<summary>donelist 图示</summary>

初始状态, `rcu_head` 1, 2, 3 目前位于`curlist`，等待当前宽限期结束，而`nxtlist`
中新增了4,5,6.

![rcu_donelist_1](pic/rcu_donelist_1.svg)

宽限期结束，将`curlist`中的成员移动到`donelist`等待释放，但是由于设置的
`maxbatch=1`, 每次最多释放一个，所以最终释放`rcu_head(1)`

![rcu_donelist_2](pic/rcu_donelist_2.svg)

进入下个`rcu tasklet`时, 发现`nxtlist`中有成员，但是`curlist`中没有,
所以`move nxtlist to curlist`, 并发起下个宽限期，同时由于donelist中有成员，
`maxbatch=1`, 释放`rcu_head(2)`

![rcu_donelist_3](pic/rcu_donelist_3.svg)

新的宽限期又结束了, 将`curlist`(`rcu_head(4)(5)(6)`)串联到`donelist`上，并在4个
`rcu tasklet`周期中一次将`rcu_head(3),(4),(5)(6)`释放.

![rcu_donelist_4](pic/rcu_donelist_4.svg)

</details>

目前链表有三条了, 这三条链表还是相对独立的，我们再回忆下这三条链表的作用:

* ***curlist***: 存放等待当前宽限期结束的object
* ***nxtlist***: 调用`call_rcu()`添加到该list, **还未等待宽限期**.
* ***donelist***: 宽限期已经结束，等待释放

## record rcu_head quiescent version earlier(本文重点)

回忆下，从调用`call_rcu()`到 `object` 释放需要经历哪些步骤:
1. `call_rcu()` 链入 `nxtlist`;
2. 该cpu进入 `rcu tasklet`, 此时`curlist`可能有成员，需要等待当前宽限期结束；释
   放`curlist`成员;
3. 宽限期结束，释放`curlist`, 同时, 将`nxtlist` moveto `curlist`, 此时该`object`
   进入`curlist`, 记录`curlist` 所需要等待的宽限期`rcu_ctrlblk.cur + 1`
4. 并等待该宽限期结束。

从这个流程中可以看出, 从调用`call_rcu()` 到为该rcu 分配宽限期中间隔了一段时间。
并且, 往往会遇到下面的情况，造成`callback`将会在当前宽限期`rcp->cur`的下两个宽
限期才释放:

```
CPU CUR                          Quiescent
                                 rcp->cur
call_rcu
  add rcu_head to nxtlist
  and wait rcp->cur Quiescent
  over

rcp->cur quiescent over          rcp->cur++
  move curlist to donelist
  move nxtlist to curlist
  set RCU_batch(cpu) = 
    (rcp->cur++) + 1

wait rcp->cur++ quiescent over

wait ((rcp->cur++) + 1) quiescent over
```

可以看到等待了几个宽限期呢?

大约是`2.5`个宽限期(等待`rcp->cur` 算半个). 但实际上, 该`rcu_head`  只需要等待
`rcp->cur++`宽限期结束就可以释放，那也就是`1.5`个宽限期左右。

overflow 中提到过: `如果rcu callback`调用延迟比较高，会造成内存处于较高的占用.
所以尽快释放`rcu_head`对于优化内存占用十分重要。

那怎么优化这段逻辑呢? 比较方便的做法是在`rcu_head`中增加字段，记录其所需要
等待宽限期的版本. 但是这样做有点浪费内存, 而且没有必要:

**我们并不需要关心`rcu_head` 具体的rcu宽线期版本，只需要关心其可以在哪个宽限期
释放, 并且最早释放的`rcu_head`肯定是最早添加的(fifo)**

如下图所示: 

![merge_three_list_to_one](pic/merge_three_list_to_one.svg)

我们可以结合之前`curlist`,`nxtlist`, `donelist`来看:
* **donelist**: 最早添加的，其等待释放的宽限期为`< RCP->rcu`
* **nxtlist**: `call_rcu()` 次早添加的，其等待释放的宽限期为`= RCP->rcu`
* **curlist**: 最新添加的，其等待释放的宽限期 为 `RCP->rcu + 1`

所以在记录是，我们也可以分为三个部分记录。

而`Lai Jiangshan`大佬想了一个方法。添加的时候仍向`nxtlist`链表添加，
不过。当随着宽限期inc，将某些object "降级":

例如:
* nxtlist->curlist
* curlist->donelist

如下图所示:

![rcu list downgrade](pic/rcu_list_downgrade.svg)

在每一次宽限期结束时，需要做上面的降级动作. 

我们来看下具体实现:

<details markdown=1 open>
<summary>具体patch</summary>

数据结构改动:
```diff
 struct rcu_data {
        /* 1) quiescent state handling : */
        long            quiescbatch;     /* Batch # for grace period */
@@ -78,12 +74,24 @@ struct rcu_data {
        int             qs_pending;      /* core waits for quiesc state */

        /* 2) batch handling */
-       long            batch;           /* Batch # for current RCU batch */
+       /*
+        * if nxtlist is not NULL, then:
+        * batch:
+        *      The batch # for the last entry of nxtlist
+        * [*nxttail[1], NULL = *nxttail[2]):
+        *      Entries that batch # <= batch
+        * [*nxttail[0], *nxttail[1]):
+        *      Entries that batch # <= batch - 1
+        * [nxtlist, *nxttail[0]):
+        *      Entries that batch # <= batch - 2
+        *      The grace period for these entries has completed, and
+        *      the other grace-period-completed entries may be moved
+        *      here temporarily in rcu_process_callbacks().
+        */
+       long            batch;
        struct rcu_head *nxtlist;
-       struct rcu_head **nxttail;
+       struct rcu_head **nxttail[3];
```
首先更改batch的逻辑:
原来batch表示当前`curlist`所需等待结束的宽限期版本。

而现在batch表示当前`nxtlist` 所有`rcu_head`所需等待的最大的宽限期版本. 也就是最
新加入nxtlist rcu_head object所等待的宽限期。

关于list部分，不再需要`curlist`, 而是将`nxtlist`拆成了三个数组:
* **[nxtlist, *nxttail[0])** : 这些`rcu_head` 所需等待的宽限期 `<=batch - 2`
* **[*nxttail[0], *nxttail[1])**: 这些`rcu_head` 所需等待的宽限期 `<=batch - 1`
* **[*nxttail[1], NULL = *nxttail[2])**: 这些`rcu_head` 所需要等待的宽限期`<=batch`

而在`call_rcu()` 和`__rcu_process_callbacks()`都会观测宽限期是否更改，如果更改则
需要move链表:

首先看 `call_rcu()`
```cpp
static void __call_rcu(struct rcu_head *head, struct rcu_ctrlblk *rcp,
               struct rcu_data *rdp)
{
       long batch;
       smp_mb(); /* reads the most recently updated value of rcu->cur. */

       /*
        * Determine the batch number of this callback.
        *
        * Using ACCESS_ONCE to avoid the following error when gcc eliminates
        * local variable "batch" and emits codes like this:
        *      1) rdp->batch = rcp->cur + 1 # gets old value
        *      ......
        *      2)rcu_batch_after(rcp->cur + 1, rdp->batch) # gets new value
        * then [*nxttail[0], *nxttail[1]) may contain callbacks
        * that batch# = rdp->batch, see the comment of struct rcu_data.
        */
       //获取最后一个元素(新加入)的成员所等待的宽限期
       batch = ACCESS_ONCE(rcp->cur) + 1;

       //这个说明链表中的最后一个元素等待宽限期小于`<= batch 1`, 需要将其移动到
       //[*nxttail[0], *nxttail[1]), 
       //同样的也需要将上面列表移动 [*nxtlist, *nxtlist[0]]
       if (rdp->nxtlist && rcu_batch_after(batch, rdp->batch)) {
               /* process callbacks */
               rdp->nxttail[0] = rdp->nxttail[1];
               rdp->nxttail[1] = rdp->nxttail[2];
               //说明已经过期了两个宽限期，所以可以移动两次。
               if (rcu_batch_after(batch - 1, rdp->batch))
                       //索性直接将nxttail[0], 指向nxttail[2]
                       rdp->nxttail[0] = rdp->nxttail[2];
       }

       //赋值rdp->batch
       rdp->batch = batch;
       //追加到nxttail
       *rdp->nxttail[2] = head;
       rdp->nxttail[2] = &head->next;

       if (unlikely(++rdp->qlen > qhimark)) {
               rdp->blimit = INT_MAX;
               force_quiescent_state(rdp, &rcu_ctrlblk);
       }
}
```

图示如下:

下图标记了`nxttail[]`指向的位置, 以及执行`*nxttail[]`所取得的值.

![rcu_nxttail_overflow](pic/rcu_nxttail_overflow.svg)

下图展示了调用`call_rcu()`添加`rcu_head`所带来的`nxttail[2]`的改动

![rcu_nxttail_add_rcu_head](pic/rcu_nxttail_add_rcu_head.svg)

下图展示了，在调用`call_rcu()`添加`rcu_head`所检测到宽限期前进，
而移动链表的流程:

![rcu_nxttail_movelist](pic/rcu_nxttail_movelist.svg)

***

再看下`__rcu_process_callbacks()`流程:

```diff
 static void __rcu_process_callbacks(struct rcu_ctrlblk *rcp,
                                        struct rcu_data *rdp)
 {
-       if (rdp->curlist && !rcu_batch_before(rcp->completed, rdp->batch)) {
-               *rdp->donetail = rdp->curlist;
-               rdp->donetail = rdp->curtail;
-               rdp->curlist = NULL;
-               rdp->curtail = &rdp->curlist;
-       }
-
-       if (rdp->nxtlist && !rdp->curlist) {
+       if (rdp->nxtlist) {
                local_irq_disable();
-               rdp->curlist = rdp->nxtlist;
-               rdp->curtail = rdp->nxttail;
-               rdp->nxtlist = NULL;
-               rdp->nxttail = &rdp->nxtlist;
-               local_irq_enable();

                /*
-                * start the next batch of callbacks
+                * move the other grace-period-completed entries to
+                * [rdp->nxtlist, *rdp->nxttail[0]) temporarily
+                */
                //查看rdp->batch 是否已经完成，如果完成了，说明整个链表中的
                //成员都完成了, 这种情况下nxttail[0], nxttail[1] 均指向末尾
+               if (!rcu_batch_before(rcp->completed, rdp->batch))
+                       rdp->nxttail[0] = rdp->nxttail[1] = rdp->nxttail[2];
                //这种情况下说明`[*nxttail[0], *nxttail[1]) 成员已经完成, 只更改 
                //nxttail[0]
+               else if (!rcu_batch_before(rcp->completed, rdp->batch - 1))
+                       rdp->nxttail[0] = rdp->nxttail[1];
+
+               /*
+                * the grace period for entries in
+                * [rdp->nxtlist, *rdp->nxttail[0]) has completed and
+                * move these entries to donelist
                 */
                //说明 `[curlist, *nxtlist[0])` 不为空，需要将其移动到donelist中
+               if (rdp->nxttail[0] != &rdp->nxtlist) {
                        //将donelist链接上nxtlist
+                       *rdp->donetail = rdp->nxtlist;
                        //重新设置donetail
+                       rdp->donetail = rdp->nxttail[0];
                        //nxtlist赋值为 *rdp->nxttail[0]
+                       rdp->nxtlist = *rdp->nxttail[0];
                        //将其于原来的curlist断开
+                       *rdp->donetail = NULL;
+
                        //我们需要重新赋值这些tail (如果这些tail 等于rdp->
                        //nxttail[0], 另外nxttail[0] 肯定重新赋值因为其被清
                        //空了)
+                       if (rdp->nxttail[1] == rdp->nxttail[0])
+                               rdp->nxttail[1] = &rdp->nxtlist;
+                       if (rdp->nxttail[2] == rdp->nxttail[0])
+                               rdp->nxttail[2] = &rdp->nxtlist;
+                       rdp->nxttail[0] = &rdp->nxtlist;
+               }

-               /* determine batch number */
                //这里不再需要赋值rdp->batch, 因为rdp->batch 含义变了，需要在
                //call_rcu()赋值(在call_rcu()中取rcp->cur+1)
-               rdp->batch = rcp->cur + 1;
+               local_irq_enable();

                if (rcu_batch_after(rdp->batch, rcp->pending)) {
                        /* and start it/schedule start if it's a new batch */
```
该函数判断, `rdp->batch` 或者`rdp->batch - 1` 宽限期是否complete，如果
* `rdp->batch` complete: 链表中所有成员都要移动到donelist中, 此时三个链表都是空
* `rdp->batch - 1` complete: 只将`[*nxtlist[0], *nxtlist[1])`移动到`[curlist,
    *nxtlist[0])`, 移动后, `nxtlist[0] = nxtlist[1]` 该链表为空

图示如下:

![rcu_nxttail_rcu_process_callback](pic/rcu_nxttail_rcu_process_callback.svg)

</details>

## 参考链接
1. reduce rcu_head size - core
   + b659a6fbb927a79acd606c4466d03cb615879f9f
   + Dipankar Sarma <dipankar@in.ibm.com>
   + Wed Jun 23 18:50:06 2004 -0700

2. RCU: low latency rcu
   + daf86b08a178f950c0e0ec073c25cc392dbbc789
   + Dipankar Sarma <dipankar@in.ibm.com>
   + Sun Aug 22 22:57:42 2004 -0700

3. rcu classic: new algorithm for callbacks-processing(v2)
   + 5127bed588a2f8f3a1f732de2a8a190b7df5dce3
   + Lai Jiangshan <laijs@cn.fujitsu.com>
   + Sun Jul 6 17:23:59 2008 +0800
