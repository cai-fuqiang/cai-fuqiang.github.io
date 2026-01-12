---
layout: post
title:  "rcu - rcu list optimization"
author: fuqiang
date:   2026-01-12 22:13:00 +0800
categories: [os, synchronization]
tags: [os, synchronization, rcu]
media_subpath: /_posts/synchronization/rcu/rcu_list_optimization
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

但是随后大佬又发现, 如果`call_rcu()`调用比较频繁, 会造成`rcu tasklet`执行时间比较
长，会增加其他流程的延迟。于是大佬想给每次调用`rcu tasklet`设置一个最大处理
`callback`的个数限制, 从而变相限制`rcu tasklet`的单次处理时长。


首先我们自己思考下, 如何实现这一目的:
* 既然要限制`rcu tasklet` 的处理个数, 也就意味着一次调用中，`curlist`会处理不完.
  这时需要另一个链表来记录未处理完的`curlist`.
* 另外, 为了减少延迟，我们需要及时清空`curlist`.
* 我们需要在因为处理个数限制而被动退出处理流程时，主动再次唤醒`rcu tasklet`

OK, 我们来看下大佬实现:

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
