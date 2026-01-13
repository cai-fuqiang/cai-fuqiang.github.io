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

## 代码流程笔记

代码静态初始化 rcu_state:
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

`__rcu_init`:
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
