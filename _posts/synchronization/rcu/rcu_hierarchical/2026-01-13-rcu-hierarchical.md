---
layout: post
title:  "rcu - rcu hierarchical"
author: fuqiang
date:   2026-01-13 20:44:00 +0800
categories: [os, synchronization]
tags: [os, synchronization, rcu]
media_subpath: /_posts/synchronization/rcu/rcu_hierarchical
math: true
---
<!--image: pic/merge_three_list_to_one.svg-->

## NOTE

## 数据结构

+ rcu_state(rsp)
  + qpnum: 当前正在发起的宽限期
  + completed: 已经完成的宽限期
+ + rcu_data(rdp)
  + qiescbatch
  + gpnum: 当前cpu正在处理的宽限期
  + completed: 该cpu 观测到的结束的宽限期
  + qs_pending: `true` 表示该cpu有pending的宽限期需要处理(可能
                是未进入静默状态，也可能是已经进入了静默状态，
                但是还未处理其mask, 需要进入软中断处理)
  + passed_quiesc: true 表示在当前宽限期已经进入静默状态
  + passwd_quiesc_completed: 当进入静默状态时, 当前cpu 观测到的 rdp->completed
  + beenonline:
  + n_rcu_pending_force_qs:
  + n_rcu_pending:
  + jiffies_force_qs: 强制结束宽限期的jiffies
+ rcu_node(rnp)
  + qsmask: 标记着该level还未处理的 cpu/groups
  + qsmaskinit: 每个宽限期开始时, 要设置的qsmask的值(初始值)
  + grpmask: 该node在`parent_node->qsmask`中的mask值
  + `grplo, grphi`: 该层级CPU or group lowest, highest number

### rcu_data.nxttail

kernel 注释:

> 如果 nxtlist 不为 NULL，则它会按如下方式分区。
> 任何分区都可能为空，这种情况下该分区的指针等于下一分区的指针。
> 当列表为空时，所有的 nxttail 元素都会指向 nxtlist（此时为 NULL）。
>
> + `[*nxttail[RCU_NEXT_READY_TAIL], NULL = *nxttail[RCU_NEXT_TAIL])`:
>
>   可能是在当前宽限期（GP）结束后到达的条目
> + `[*nxttail[RCU_WAIT_TAIL], *nxttail[RCU_NEXT_READY_TAIL])`
>
>   已知是在当前宽限期（GP）结束前到达的条目
> + `[*nxttail[RCU_DONE_TAIL], *nxttail[RCU_WAIT_TAIL])`:
>
>   batch # `<= ->completed - 1`：在等待当前宽限期（GP）结束的条目
>
> + `[nxtlist, *nxttail[RCU_DONE_TAIL])`
>
>   batch # `<= ->completed` 的条目
>
>   这些条目的宽限期（GP）已经完成，其他宽限期已完成的条目也可以在
>   rcu_process_callbacks() 中临时移动到这里
>
{:.prompt-ref}

各个队列加入的函数:

+ `[RCU_NEXT_READY_TAIL, RCU_NEXT_TAIL]`
  + call_rcu
  
## 代码流程笔记

### rcu_pending

```sh
__rcu_pending
=> check_cpu_stall
## 需要判断是否已经进入了静默状态，如果没有需要进入下半部判断
## 其是否进入静默状态，然后置位相关mask
=> if rdp->qs_pending
   => return 1
## donelist 中需要处理的rcu callback
=> if cpu_has_callbacks_ready_to_invoke(rdp)
   => return 1
## *rdp->nxttail[RCU_DONE_TAIL] 表示 RCU_WAIT_TAIL 链表起始
##   如果该链表不为空，表示目前有rcu callback, 需要发起新的宽限期
##   等待处理
## 当前的宽限期结束了, 但是该cpu中有新的callback在等待下一个宽限期
## 结束处理
=> cpu_needs_another_gp()
   => return *rdp->nxttail[RCU_DONE_TAIL] &&
          ACCESS_ONCE(rsp->completed) == ACCESS_ONCE(rsp->gpnum);
## 其他的cpu结束了宽限期 
## TODO 为什么要管这个呢
##
## A: 因为其他cpu 结束宽限期, 可能会涉及 nxtlist的移动, 需要在下半部
## 处理该事情
=> if ACCESS_ONCE(rsp->completed) != rdp->completed
   => return 1
## 该宽限期持续了很长时间，发IPI 尽快结束宽限期
=> if ACCESS_ONCE(rsp->completed) != ACCESS_ONCE(rsp->gpnum)
     ((long)(ACCESS_ONCE(rsp->jiffies_force_qs) - jiffies) < 0 ||
      (rdp->n_rcu_pending_force_qs - rdp->n_rcu_pending) < 0))
   => return 1
```

## 代码静态初始化 rcu_state

```cpp
struct rcu_state rcu_state = RCU_STATE_INITIALIZER(rcu_state);

#define RCU_STATE_INITIALIZER(name) { \
    //只初始化level[0]
    .level = { &name.node[0] }, \
    //初始化 levelcnt
    .levelcnt = { \
        NUM_RCU_LVL_0,  /* root of hierarchy. */ \
        NUM_RCU_LVL_1, \
        NUM_RCU_LVL_2, \
        NUM_RCU_LVL_3, /* == MAX_RCU_LVLS */ \
    }, \
    }, \
    .signaled = RCU_SIGNAL_INIT, \
    .gpnum = -300, \
    .completed = -300, \
    .onofflock = __SPIN_LOCK_UNLOCKED(&name.onofflock), \
    .fqslock = __SPIN_LOCK_UNLOCKED(&name.fqslock), \
    .n_force_qs = 0, \
    .n_force_qs_ngp = 0, \
}
```

### `__rcu_init`

```sh
__rcu_init
## init rcu_state
|=> rcu_init_one(&rcu_state);
    ## rsp->level[i]
    |=> for (i = 1; i < NUM_RCU_LVLS; i++)
        ## 根据上一级的第一个node指针+levelcnt获取下一级的第一个node 指针
        |=> rsp->level[i] = rsp->level[i - 1] + rsp->levelcnt[i - 1];
    ## 获取每一级的levelspread, 相当于上一级的node包含下一级node 数量
    |=> rcu_init_levelspread(rsp);
    |-> cpustride = 1
    |=> for (i = NUM_RCU_LVLS - 1; i >= 0; i--)
        ## 获取 cpustride (步长) 这个从最低的级别开始计算, 例如假如有三级,
        ## 则获取的次序是level[2], level[1], level[0], 越高的level(level[0]最高)
        ## 步长越大（所覆盖的cpu越多)
        |=> cpustride *= rsp->levelspread[i];
        |=> rnp = rsp->level[i]
        ## 初始化每个node, 只列取初始化不为0的字段
        |=> for (j = 0; j < rsp->levelcnt[i]; j++, rnp++)
            ## rnp->grplo 赋值为该rnp覆盖的第一个cpu
            |=> rnp->grplo = j * cpustride;
            ## rnp->grphi 赋值为该rnp覆盖的最后一个cpu
            |=> rnp->grphi = (j + 1) * cpustride - 1;
            ## 不过要注意rnp->grphi 不要超过 NR_CPUS
            |=> if (rnp->grphi >= NR_CPUS)
                |=> rnp->grphi = NR_CPUS - 1;
            |=> if i == 0
                ## level[0]
                |=> rnp->grpnum = 0
                |=> rnp->grpmask = 0
                |=> rnp->parent = NULL
            \-> else
                ## 表示level在上一级中的位置
                |=> rnp->grpnum = j % rsp->levelspread[i - 1];
                ## 将 grpnum 转换为mask
                |=> rnp->grpmask = '1UL << rnp->grpnum'
                ## 获取parent node
                |=> rnp->parent = rsp->level[i - 1] +
                              j / rsp->levelspread[i - 1];
            |=> rnp->level = i;
## 该宏的作用是为 per_cpu(rcu_data, i).my_node 赋值
|=> RCU_DATA_PTR_INIT(&rcu_state, rcu_data);
    ## 获取到最后一级level
    |=> rnp = (rsp)->level[NUM_RCU_LVLS - 1];
    |=> j = 0
    ## 循环每个cpu
    |=> for_each_possible_cpu(i)
        ## 如果 i 超过了 rnp[j].grphi
        ## 则换下一个 rnp
        |=> if (i > rnp[j].grphi)
            \-> j++
        ## 赋值rcu_data.mynode
        |=> per_cpu(rcu_data, i).mynode = &rnp[j];
        ## 回首掏
        |=> (rsp)->rda[i] = &per_cpu(rcu_data, i);
|=> rcu_init_one(&rcu_bh_state);
|=> RCU_DATA_PTR_INIT(&rcu_bh_state, rcu_bh_data);
```

### 初始化rdp

`rcu_init_percpu_data()`

```sh
rcu_init_percpu_data
=> lastcomp = rsp->completed
## 将completed 先记录为rsp中的completed
=> rdp->completed = lastcomp;
## 和上面相同，将gpnum 记录为lastcomp
=> rdp->gpnum = lastcomp
## 在新的宽限期中还未进入静默期
=> rdp->passed_quiesc = 0;

## 表示当前cpu 需要处理pending的宽限期
## 所以，根据前面gpnum 的设置, 以及 lastcomp的设置
=> rdp->qs_pending = 1
## 表示目前的rdp已经是online状态 降级
=> rdp->beenonline = 1
```

### rcu_do_batch

```sh
rcu_do_batch
## 关中断
=> local_irq_save(flags);
## nxtlist 相当于 donelist
=> list = rdp->nxtlist;
## 将list指向nxtlist，相当于donelist head, 等待callback
## 调用
=> list = rdp->nxtlist;
## 移动nxtlist到 donelist tail,
=> rdp->nxtlist = *rdp->nxttail[RCU_DONE_TAIL];
## 将nxttail设置为0， 也就是list 最后一个元素next为0
=> *rdp->nxttail[RCU_DONE_TAIL] = NULL;
## 获取nxttail, 即list最后一个元素
=> tail = rdp->nxttail[RCU_DONE_TAIL];
## 降级
=> for (count = RCU_NEXT_SIZE - 1; count >= 0; count--)
       if (rdp->nxttail[count] == rdp->nxttail[RCU_DONE_TAIL])
           ## 最后一个指向&rdp->nxtlist
           rdp->nxttail[count] = &rdp->nxtlist;
=> local_irq_restore(flags);
=> count=0
## 循环list中的元素
=> while list
   ## 和classic 逻辑一样
   => next = list->next;
   => list->func(list);
   => list = next;
      ## 如果处理的数量大于限制值交给下一次处理
      => if ++count >= rdp->blimit
         => break
=> local_irq_save(flags);
## 减去处理的
=> rdp->qlen -= count;
## 如果list没有处理完，需要再次归到rdp->nxtlist
=> if list != NULL
   ## tail之前指向的是 list 最后一个元素的next, 对其赋值，
   ## 相当于将链表拼接
   => *tail = rdp->nxtlist;
   => for count = 0; count < RCU_NEXT_SIZE; count++
      ## 这里会将之前指向 &rdp->nxtlist的链表成员，
      ## 再次指向tail
      => if &rdp->nxtlist == rdp->nxttail[count]
         => rdp->nxttail[count] = tail;
      else
         break
## 如果没有限制(说明之前解除限制了), 并且rdp数量已经比较少了，再次限制
=> if (rdp->blimit == LONG_MAX && rdp->qlen <= qlowmark)
   => rdp->blimit = blimit
=> local_irq_restore(flags);
=> if cpu_has_callbacks_ready_to_invoke(rdp)
      ## 如果nxtlist为空?
      => return &rdp->nxtlist != rdp->nxttail[RCU_DONE_TAIL];
   => raise_softirq(RCU_SOFTIRQ);
```

## `__rcu_process_callbacks`

```sh
__rcu_process_callbacks
=> force_quiescent_state()
## advance callbacks
=> rcu_process_gp_end()
## update RCU state
=> rcu_check_quiescent_state()
   ## 如果检测到有新的宽限期到达, 则进入新的宽限期，
   ## 并重置当前静默状态;
   => if check_for_new_grace_period()
         => if rdp->gpnum != rsp->gpnum
            => note_new_gpnum(rsp, rdp);
               ## 有pending的宽限期尚未处理
               => rdp->qs_pending = 1;
               ## 当前cpu还未进入静默状态
               => rdp->passed_quiesc = 0;
               => rdp->gpnum = rsp->gpnum;
               ## 和强制结束静默状态有关
               => rdp->n_rcu_pending_force_qs = rdp->n_rcu_pending +
                      RCU_JIFFIES_TILL_FORCE_QS;
      => return
   ## 如果该cpu 在该宽限期中未pending，说明其已经进入静默状态，并且
   ## 已经处理完mask，在这里直接返回
   => if !rdp->qs_pending
      => return
   ## 该cpu还未进入静默状态
   => if !rdp->passed_quiesc
      => return
   ## 已经进入静默状态，但是是pending的，处理其mask
   => cpu_quiet(rdp->cpu, rsp, rdp, rdp->passed_quiesc_completed);
      ## 要处理mask了，首先对其 rnp 加锁
      => rnp = rdp->mynode;
      => spin_lock_irqsave(&rnp->lock, flags)
      ## 上次进入静默状态时, completed 的值 和当前completed的值不一样，
      ## 说明之前的宽限期已经结束，进入了新的宽限期
      ## 这时，我们需要标记当前cpu的宽限期未结束
      ##
      ## NOTE -- TODO
      ##
      ## Someone beat us to it for this grace period, so leave.
      ## The race with GP start is resolved by the fact that we
      ## hold the leaf rcu_node lock, so that the per-CPU bits
      ## cannot yet be initialized -- so we would simply find our
      ## CPU's bit already cleared in cpu_quiet_msk() if this race
      ## occurred.
      => if lastcomp != ACCESS_ONCE(rsp->completed):
         => rdp->passed_quiesc = 0;
         => spin_unlock_irqrestore(&rnp->lock, flags);
         => return
      ## 接下来要操作mask
      => mask = rdp->grpmask;
      ## 已经被清了, 可能时因为发起新宽限期的cpu还在做set动作
      => if (rnp->qsmask & mask) == 0:
       ## 什么都不做等待下次处理
         => spin_unlock_irqrestore(&rnp->lock, flags);
      -- else
         ## 开始处理mask
         => rdp->qs_pending = 0;
         => rdp = rsp->rda[smp_processor_id()];
         ## 首先前进等待下一个宽限期的tail, 这里由当前cpu置位mask，
         ## 说明[RCU_NEXT_READY_TAIL, RCU_NEXT_TAIL], 一定是在下一个
         ## 宽限期之前添加的，所以需要等待下一个宽限期结束即可。前进!
         => rdp->nxttail[RCU_NEXT_READY_TAIL] = rdp->nxttail[RCU_NEXT_TAIL];
      ## 开始处理mask
      => cpu_quiet_msk(mask, rsp, rnp, flags);
      ## 处理的逻辑是层级处理，每到一层，拿那一层的锁
      => for (;;)
         ## 已经被清了? 这个可能存在于非叶子节点, 两个cpu都清空了各自的bit,
         ## 清父节点
         => if (!(rnp>qsmask & mask))
            => spin_unlock_irqrestore(&rnp->lock, flags);
            => return
         => rnp->qsmask &= ~mask;
         ## 说明该层级还有未处理的;
         => if rnp->qsmask != 0
            => spin_unlock_irqrestore(&rnp->lock, flags);
         => mask = rnp->grpmask;
         ## 已经到根节点，直接退出
         => if (rnp->parent == NULL)
            => break
         ## 解锁当前节点
         => spin_unlock_irqrestore(&rnp->lock, flags);
         ## 获取父节点 
         => rnp = rnp->parent;
         ## 锁父节点
       => spin_lock_irqsave(&rnp->lock, flags);
       ## 更新rsp->completed
       ##
       ## NOTE
       ##
       ## 更新completed 在已经观测到整个层级的mask都已经clear
       => rsp->completed = rsp->gpnum;
       ## 进入该宽限期结束, 前进nxttail !
       => rcu_process_gp_end(rsp, rsp->rda[smp_processor_id()]);
       ## 开启新的宽限期
       => rcu_start_gp(rsp, flags);  /* releases rnp->lock. */
```

## rcu_start_gp

```sh
## 进入该函数之前, 拿root rnp的锁
rcu_start_gp
## 是否需要发起新的宽限期
=> if (!cpu_needs_another_gp(rsp, rdp))
   => spin_unlock_irqrestore(&rnp->lock, flags);
   => return
=> rsp->gpnum++
=> rsp->signaled = RCU_GP_INIT
## 和强制结束宽限期相关
=> rsp->jiffies_force_qs = jiffies + RCU_JIFFIES_TILL_FORCE_QS
=> rdp->n_rcu_pending_force_qs = rdp->n_rcu_pending +
          RCU_JIFFIES_TILL_FORCE_QS;
=> record_gp_stall_check_time(rsp);
=> dyntick_record_completed(rsp, rsp->completed - 1);
## 更新当前cpu 的 rcu_data，宽限期状态
=> note_new_gpnum(rsp, rdp);
## 因为是该cpu发起的宽限期，所以直接将所有callback移动到
## 等待当前宽限期结束的nxttail list中
=> rdp->nxttail[RCU_NEXT_READY_TAIL] = rdp->nxttail[RCU_NEXT_TAIL];
=> rdp->nxttail[RCU_WAIT_TAIL] = rdp->nxttail[RCU_NEXT_TAIL];
## 只有一层？ 那可太简单了
=> if (NUM_RCU_NODES == 1)
   => rnp->qsmask = rnp->qsmaskinit
   => spin_unlock_irqrestore(&rnp->lock, flags);
   => return
=> spin_unlock(&rnp->lock);
=> spin_lock(&rsp->onofflock);
=> rnp_end = rsp->level[NUM_RCU_LVLS - 1];
## 在不加rnp->lock 的情况下, 更新各个group node(非叶子节点) 的qsmask
## 其他cpu 只会访问其cpu所在的叶子节点，但是此时叶子节点还未更新，qsmask为0，
## 所以这里不用加锁
=> for (rnp_cur = &rsp->node[0]; rnp_cur < rnp_end; rnp_cur++)
   => rnp_cur->qsmask = rnp_cur->qsmaskinit;
## 接下来处理各个叶子节点
## 首先我们要确保更新各个叶子节点时，持有其叶子节点的锁. 防止其他cpu更新该
## node. 另外，一旦我们更新完该mask，它所对应的cpu可能会沿着层级结构向
## 上传递. 因此，我们需要获取要操作的每个节点的锁。
##
## 另外该宽限期在次过程中不会结束，因为至少当前cpu 还未进入静默状态
=> {
    rnp_end = &rsp->node[NUM_RCU_NODES];
    rnp_cur = rsp->level[NUM_RCU_LVLS - 1];
    for (; rnp_cur < rnp_end; rnp_cur++) {
     spin_lock(&rnp_cur->lock); /* irqs already disabled. */
     rnp_cur->qsmask = rnp_cur->qsmaskinit;
     spin_unlock(&rnp_cur->lock); /* irqs already disabled. */
    }
    rsp->signaled = RCU_SIGNAL_INIT; /* force_quiescent_state now OK. */
    spin_unlock_irqrestore(&rsp->onofflock, flags);
   }

```
