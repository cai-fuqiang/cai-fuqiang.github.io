---
layout: post
title:  "rcu - classic"
author: fuqiang
date:   2026-01-05 10:00:00 +0800
categories: [os, synchronization]
tags: [os, synchronization, rcu]
media_subpath: /_posts/synchronization/rcu/rcu_classic
image: /pic/rcu_todo_overflow.svg
---

本文主要讲解 经典rcu (classical rcu) 历史. 在介绍具体实现之前, 我们先明确几个概
念:

* **_quiescent state_**:  该CPU 上运行的所有 RCU 读取端临界区都已完成<sup>1</sup>
* **_grace period_**: rcu 删除分为三部分, emoval ,Grace Period, and Reclamation. 宽限期
  结束以所有cpu rcu 读临界区完成, 即所有cpu 都经历一次 `quiescent state`
* **_rcu callback_**: 某些rcu writer将释放动作封装为一个`rcu_head`, 通过调用
    `call_rcu()`注册回调，允许异步执行释放动作。

rcu处理流程的关键点是: 
1. 如何发现新的rcu callback, 发起一个新的宽限期
2. **如何判定该宽限期结束, 调用相关rcu callback**

如下图所示:

![rcu_todo_overflow](pic/rcu_todo_overflow.svg)

这里有几个问题需要思考下:
1. 谁持有rcu read lock(和问题三相关联)
2. 什么时候需要发起一个新的宽限期
3. 怎么确定该cpu 进入静默状态
4. 怎么确定所有cpu 都经历了一次静默状态（当前宽限期结束)

我们带着这些问题看接下来的内容:

## first version

### struct

相关数据结构:

![rcu_struct_overflow](pic/rcu_struct_overflow.svg)

**_global_**:

+ **rcu_ctrblk**: 全局数据结构，和全局的宽限期"version", 以及cpu静默状态位图
  * **curbatch**: 当前宽限期的"version"
  * **maxbatch**: rcu callback "预定的" 最大宽限期 "version"
  * **rcu_cpu_mask**: 当前宽限期处于静默状态位图

**_per cpu_**:
* rcu_tasklet: 用于定义rcu_tasklet, 用户在`softirq`中处理rcu。
* **rcu_data**: 用于记录每个cpu的静默期，以及待处理的rcu callback 链表, 以及
  batch "version"
  + **qsctr**: 当前静默期"version" 
  + **last_qsctr**: 上一次记录的静默期 "version"
  + **batch**: 当前 **curlist** 处于宽限期的"version"
  + **curlist**: 处于宽限期的rcu callback列表 
  + **nxtlist**: 表示待处理的rcu callback 列表(还未发起宽限期)

### 处理流程

#### add rcu_callback to head
```cpp
void call_rcu(struct rcu_head *head, void (*func)(void *arg), void *arg)
{
    int cpu;
    unsigned long flags;

    //===(1)===
    head->func = func;
    head->arg = arg;
    //===(2)===
    local_irq_save(flags);
    cpu = smp_processor_id();
    //===(3)===
    list_add_tail(&head->list, &RCU_nxtlist(cpu));
    local_irq_restore(flags);
}
```

1. 构造`rcu_head` 数据机构
2. 关中断。因为下面要操作`RCU_nxtlist()`, 防止该流程被中断打断（中断也可能执行这部分流程)
3. 将新构造的 `head` 串到 `RCU_nxtlist()`

#### cpu experience a quiescent state

上面讲述了，如何将rcu callback 注册到相应的数据结构中。那什么时候处理(执行)rcu
callback呢? -- 等一个完整的宽限期结束. 

> 这里为什么要提完整的宽限期呢? 
>
> 那就得讨论下是否要支持全局的宽限期。可以设想下，每个cpu 都可以发起宽限期。每个
> cpu 负责记录自己的静默状态，并标记这些并在记录后，再处理每个cpu的宽限期状态。
> 这样实现起来太繁琐了。所以Linux 将宽限期定义为一个全局的状态。
>
> 举个例子, 如果rcu callback在每个时刻都会产生的话，整个的时间线将分割为不同的宽
> 限期.
>
> ```
> ======================================================================> timeline
> |--  grace period 1  --|-- grace period 2 --|-- grace period 3--|--next 
> ```
> 那假设在period 1 阶段调用`call_rcu()`, 那call_rcu()产生的callback能不能在`grace
> period 1` 结束后执行么? 不可以，因为此时已经有一些cpu 进入下一个宽限期。可能正
> 处于读临界区中。所以需要等到grace period 2 结束。
{: .prompt-tip}

那么如何判定完整的宽限期结束呢? 在发起宽限期后，所有cpu 都经历一个静默状态. 那什
么时候可以判断静默状态结束呢?

明显的答案是`rcu_read_unlock()`结束。因为这意味着读临界区结束。但是这样可能会和
Linux 本身要求rcu达到的效果相违背: 安全高效。

`rcu_read_unlock()` 的问题:

全局状态更新太频繁: 在某个流程中频繁的调用`rcu_read_lock()`, `rcu_read_unlock()`.
频繁的更新全局状态会让写端(其实是处理grace period 流程)开销陡增（cache 
conherence cost)

> 并未找到官方说明, 所以这里我只是猜测。不知道是否有其他更深层次的原因。
{: .prompt-warning}

于是开发者们, 在两个点定义静默状态:
* timer interrupt from USERSPACE, idle
* schedule()

因为rcu读临界区都发生在内核代码中，所以从userspace 触发的中断可以断定一定没有处
于rcu读临界区。另外, idle比较特殊，其虽然位于内核空间，但是其是空闲的（什么都不
做), 所以也可以认为其属于静默状态.

判断条件在`rcu_check_callback()` 代码中:
```cpp
rcu_check_callbacks
=> if (user || (idle_cpu(cpu) && !in_softirq() && hardirq_count() <= 1))
   => RCU_qsctr(cpu)++;
```

`RCU_qsctr(cpu)++` 表示当前cpu已经经历了一次静默期。关于idle分支的判断
要稍微复杂一些:

* `idle_cpu(cpu)`: 表示当前`cpu` 正在执行的任务是idle任务
* `!in_softirq()`: 不处于softirq 上下文
* `hardirq_count <= 1`: 不处于中断上下文（该时钟中断的前一个上下文，而时钟中断
  本身位于中断上下文, 所以这里要 `<=1`)


#### when to initiate a new grace period and handle

当我们通过`call_rcu()` 注册一个异步callback后，这些callback需要经历一个完整的
宽限期。我们如何将这些callback和具体的宽限期联系起来。并在宽限期结束后处理
他们呢?

![rcu_handle_overflow](pic/rcu_handle_overflow.svg)

如上图所示, 在时钟中断处理流程中，`scheduler_tick()` 会判断是否有`rcu`相关
的事情要处理, 如果有则调用 `rcu_check_callbacks()` 处理。该函数不仅会判断
是否经历了一次静默状态，同时也会调用`tasklet_schedule()` 调用`rcu_tasklet`
做进一步的下半部处理。

> 关于rcu_pending()代码:
>
> ```cpp
> static inline int rcu_pending(int cpu)
> {
>     if ((!list_empty(&RCU_curlist(cpu)) &&
>          rcu_batch_before(RCU_batch(cpu), rcu_ctrlblk.curbatch)) ||
>         (list_empty(&RCU_curlist(cpu)) &&
>              !list_empty(&RCU_nxtlist(cpu))) ||
>         test_bit(cpu, &rcu_ctrlblk.rcu_cpu_mask))
>         return 1;
>     else
>         return 0;
> }
> ```
>
> 有两种情况需要在下半部进一步处理
> 1. 当前有未处理的 rcu_callback
>    + curlist 不为空，但是curlist 所在的batch 已经expired.(说明curlist所在的
>      宽限期已经结束), 或者
>    + curlist 是空，nxtlist不为空。说明, 需要未nxtlist 发起一个新的宽限期
>    + 其他情况: 例如curlist 不为空，但是curlist 所在的batch 还没有 expired.
>      这说明curlist 所在的宽限期还没有结束。还不能为`nxtlist`分配下一个宽
>      限期
> 2. 判断`rcu_ctrlblk->rcu_cpu_mask` 是否有该cpu bit, `rcu_cpu_mask`用来标记
>    哪些cpu还没有在本次宽限期中经历静默状态; 如果为1 说明有宽限期正在等待
>    该cpu 到达静默状态。所以，需要该cpu 根据自己静默状态修改`rcu_cpu_mask`
>    这部分工作也放在了下半部处理。
{: .prompt-info}

#### work in rcu_tasklet

而位于`rcu_tasklet`中的流程，是rcu 处理的主流程, 其主要有几部分工作:
* 为新的rcu callback分配宽限期
* 判断该cpu是否处于静默状态, 并修改`rcu_cpu_mask`
* 判断该cpu curlist 所在的宽限期是否结束，如果结束执行相应的callback，并根据
  nxtlist链表情况, 要不要发起下一个宽限期.

代码并不复杂，我们直接看代码:
```cpp
static void rcu_process_callbacks(unsigned long unused)
{
    int cpu = smp_processor_id();
    LIST_HEAD(list);

    //==(1)==
    if (!list_empty(&RCU_curlist(cpu)) &&
        rcu_batch_after(rcu_ctrlblk.curbatch, RCU_batch(cpu))) {
        list_splice(&RCU_curlist(cpu), &list);
        INIT_LIST_HEAD(&RCU_curlist(cpu));
    }

    //==(2)==
    local_irq_disable();
    //==(3)==
    if (!list_empty(&RCU_nxtlist(cpu)) && list_empty(&RCU_curlist(cpu))) {
        list_splice(&RCU_nxtlist(cpu), &RCU_curlist(cpu));
        INIT_LIST_HEAD(&RCU_nxtlist(cpu));
        local_irq_enable();

        /*
         * start the next batch of callbacks
         */
        spin_lock(&rcu_ctrlblk.mutex);
        RCU_batch(cpu) = rcu_ctrlblk.curbatch + 1;
        rcu_start_batch(RCU_batch(cpu));
        spin_unlock(&rcu_ctrlblk.mutex);
    } else {
        local_irq_enable();
    }
    //==(4)==
    rcu_check_quiescent_state();
    //==(5)==
    if (!list_empty(&list))
        rcu_do_batch(&list);
}
```
1. curlist中没有成员，并且 `rcu_ctrblk.curbatch` 比 `RCU_batch(cpu)` 要高，说明
   当前全局的宽限期，已经比`cpu curlist`所在的宽限期要高，所以`cpu curlist`宽限期
   已经结束。为此可以执行该`cpu curlist`中的`rcu callback`
2. 这里比较有意思，访问 RCU_curlist() 没有关中断，但是访问RCU_nxtlist()
   却关中断, 原因是因为nxtlist 可能会在中断上下文中更新。
3. 如果nxtlist不为空，但是curlist为空, 则需要为nxtlist 分配一个新的宽限期.
   首先将nxtlist 链表转移至 curlist, 接着分配 `RCU_batch(cpu)` 宽限期"version"
   为`global current batch + 1`(`rcu_ctrlblk->curbatch + 1`). 然后调用
   `rcu_staret_batch()`（下面讲)
4. 该函数会判断当前函数是否经历一次完整的静默期.
5. 根据 1 可知，list中的rcu callback肯定经历了一次完整的静默期，可以执行release
   - rcu_callback 流程

**_rcu_start_batch()_**:
```cpp
static void rcu_start_batch(long newbatch)
{
    //maxbatch 永远记录当前"申请的" 最大的宽限期版本
    if (rcu_batch_before(rcu_ctrlblk.maxbatch, newbatch)) {
        rcu_ctrlblk.maxbatch = newbatch;
    }
    //如果maxbatch 比curbatch 早，说明 curbatch 已经涨上来了。
    //（curbatch - 1 已经结束了)
    //
    //反之，并且`rcu_ctrblk.rcu_cpu_mask == 0`, 说明旧的宽限期已经结束，并且有
    //新的宽限期需要发起.
    if (rcu_batch_before(rcu_ctrlblk.maxbatch, rcu_ctrlblk.curbatch) ||
        (rcu_ctrlblk.rcu_cpu_mask != 0)) {
        return;
    }
    //发起一个新的宽限期
    rcu_ctrlblk.rcu_cpu_mask = cpu_online_map;
}
```
怎么才算发起一个新的宽限期呢? 还记得`rcu_pending()`的条件么? 只要该cpu 的
`rcu_cpu_mask` 置位，说明该cpu 需要关注自己的静默状态, 并在达到静默状态后，
清除`rcu_cpu_mask`相应状态，所以，将`rcu_cpu_mask`全部置位，所有的cpu
都要重新关注自己的静默状态。这样算是发起了新的宽限期。

> 发起宽限期的条件之一是 `rcu_ctrlblk.maxbatch >= rcu_ctrlblk.curbatch`,
> 所以无论是curbatch改变，还是`maxbatch`改变都有可能发起新的宽限期.
>
> 而该调用路径:
> ```
> rcu_process_callback()
> => rcu_start_batch()
>    => rcu_ctrlblk.rcu_cpu_mask = cpu_online_map
> ```
> 其实是描述的`maxbatch`改变，在cpu检测到宽限期结束，自增全局curbatch时，
> 也会让这个天平倾斜
{: .prompt-tip}

**_rcu_check_quiescent_state()_**

```cpp
static void rcu_check_quiescent_state(void)
{
    int cpu = smp_processor_id();

    //未置位的原因是该cpu 在该宽限期已经是静默状态.
    if (!test_bit(cpu, &rcu_ctrlblk.rcu_cpu_mask)) {
        return;
    }

    /*
     * Races with local timer interrupt - in the worst case
     * we may miss one quiescent state of that CPU. That is
     * tolerable. So no need to disable interrupts.
     */
    //这个流程可能会和local timer interrupt 冲突??
    //冲突意味着 RCU_qsctr() 会更改, 但是结合`rcu_check_callbacks()`
    //代码来看其不会更改 RCU_qsctr()
    //
    //那还有一种可能 -- 调度, 但是softirq 不能被抢占。但是ksoftirq 可以
    //被抢占,  这里的意思难道是ksoftirq可以被抢占? 导致抢占后 RCU_qsctr
    //更改?
    //==(1)==
    if (RCU_last_qsctr(cpu) == RCU_QSCTR_INVALID) {
        RCU_last_qsctr(cpu) = RCU_qsctr(cpu);
        return;
    }

    //==(1.2)==
    //说明当前记录的宽限期(last_qsctr) 还未结束
    if (RCU_qsctr(cpu) == RCU_last_qsctr(cpu)) {
        return;
    }

    spin_lock(&rcu_ctrlblk.mutex);
    //这个地方也很奇怪, 前面也检查过该cpu的mask，确定
    //present后，才会向下执行，但是这里为什么要加自旋锁
    //再检查下
    //==(2)==
    if (!test_bit(cpu, &rcu_ctrlblk.rcu_cpu_mask)) {
        spin_unlock(&rcu_ctrlblk.mutex);
        return;
    }
    //运行到这里说明宽限期已经结束
    clear_bit(cpu, &rcu_ctrlblk.rcu_cpu_mask);

    //last_qsctr 置为 RCU_QSCTR_INVALID(0)
    RCU_last_qsctr(cpu) = RCU_QSCTR_INVALID;
    if (rcu_ctrlblk.rcu_cpu_mask != 0) {
        spin_unlock(&rcu_ctrlblk.mutex);
        return;
    }
    //处理下一个宽限期
    rcu_ctrlblk.curbatch++;

    //发起下一个宽限期,
    //==(3)==
    rcu_start_batch(rcu_ctrlblk.maxbatch);
    spin_unlock(&rcu_ctrlblk.mutex);
}
```

1. 为什么`qsctr` 要经历`RCU_QSCTR_INVAILD-> RCU_qsctr(cpu) -> RCU_qsctr()++`
   这样的变化。而不能直接在宽限期结束后，不重制`RCU_last_qsctr()`.

   当宽限期结束后，有新的宽限期发起，这时如果走到1，会将 `last_qsctr` 赋值为
   `qsctr`, 但是如果做这个流程，必须得是新的宽限期发起后才做，而宽限期发起后，
   如果执行了一次这个流程就无需在做，只需要等待`1.2`条件满足即可。

   所以这里将`qsctr`赋值为`RCU_QSCTR_INVAILD`, 为了给下次进入该函数识别新宽限期
   发起后，首次执行该函数作准备
2. 这个地方着实没看懂
3. 这里使用`maxbatch`作为参数调用`rcu_start_batch()`, `maxbatch` 前面提到过, 可
   以认为是 目前"预定的"最大版本的宽限期. 相当于pending的最大版本的宽限期，
   如果这个宽限期都处理完了，说明所有的`cpu->curlist` 都处理完了。

### 处理流程图示

<details markdown=1 open>
<summary>流程图示展开</summary>

初始状态

![first_patch_simple_process_init](pic/first_patch_simple_process_init.svg)

cpu0 rcu writer 调用 call_rcu() 异步释放object

![first_patch_simple_process_1](pic/first_patch_simple_process_1.svg)

CPU0 在时钟中断中发现有rcu事情需要处理，唤起
rcu tasklet, 将nxtlist 移动至 cutlist

![first_patch_simple_process_2](pic/first_patch_simple_process_2.svg)

发起一个新的宽限期新的宽限期为2 (maxbatch(2) 表示当前申请的最大的宽限期),
`rcu_cpu_mask` 赋值为 `cpu_online_mask`(1,1,1,1),  表示所有的cpu豆未经历静默状态。

![first_patch_simple_process_3](pic/first_patch_simple_process_3.svg)

CPU0, CPU1, CPU2, CPU3 在检测自己是否进入静默状态是，现将
`last_qsctr`重置为`qsctr`，不过后者也是0。

![first_patch_simple_process_5](pic/first_patch_simple_process_5.svg)

CPU0, CPU1, CPU2 进入静默状态，清除自己cpu的 `rcu_cpu_mask`

![first_patch_simple_process_6](pic/first_patch_simple_process_6.svg)

CPU3 进入静默状态，并清除其cpu的`rcu_cpu_mask`, 作为最后一个清除`rcu_cpu_mask`
的cpu, 最终会将`rcu_cpu_mask` 更改为0。更新至0 意味着所有的cpu 都进入静默状态。
也就是该宽限期(1)结束。

![first_patch_simple_process_7](pic/first_patch_simple_process_7.svg)

宽限期(1) 结束，但是CPU0  curlist申请的不是宽限期1而是宽限期2(maxbatch), 所以
该宽限期结束不会处理任何callback，但是会发起进入下一个宽限期.

![first_patch_simple_process_8](pic/first_patch_simple_process_8.svg)

等待所有cpu又经历一个宽限期后, cpu0的rcu callback可以得到处理。

![first_patch_simple_process_9](pic/first_patch_simple_process_9.svg)

处理过后，maxbatch仍然是2，而curbatch 更新至3，curbatch > maxbatch, 说明pending
的宽限期已经处理完成，没有必要再处理curbatch。等待maxbatch 更新上来。

可以看到这里有些流程是不太好的。例如当我们重新发起宽限期时(move nxtlist->curlist),
总是将`RCU_batch(cpu) = rcu_ctrlblk.curbatch + 1`, 并没有看当前的宽限期活不活跃。
这样就会多经历一个额外的宽限期

</details>

## 参考链接
1. [LWN: Hierarchical RCU](https://lwn.net/Articles/305782/)
