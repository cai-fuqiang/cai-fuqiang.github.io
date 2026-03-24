---
layout: post
title:  "eevdf code"
author: fuqiang
date:   2025-10-11 22:00:00 +0800
categories: [schedule, eevdf]
tags: [sched]
math: true
---

## 注释
### avg_vruntime_add
公平调度器能够保持 lag 不变(conserve lag):

$$
\sum{lag_i} = 0
$$

> NOTE
>
> 论文中的 **Corollary 1**
{: .prompt-info}

在eevdf中, $lag_i$ 表示，理想的service time ($S$) 和实际的 service time ($s_i$)
差值:

$$
lag_i = S - s_i = w_i * (V - v_i)
$$

$\sum{lag_i} = 0$时可以推导:

$$
\begin{align}
\sum{w_i * (V - v_i)} &= 0 \\
\sum{w_i * V - w_i * v_i }  &= 0 \\
\sum{w_i * V} - \sum {w_i * v_i } &= 0 \\
V* \sum{w_i} - \sum {w_i * v_i } &= 0 \\
\end{align}
$$
可以推导:
$$
V = \frac{\sum{w_i * v_i}}{\sum{w_i}} \\
V = \frac{\sum{w_i * v_i}}{W}
$$

$V$ 为所有任务virtual runtime 的加权平均和.

> 然而$V(t)$ 在论文中有一个计算公式:
> 
> $$
> V(t) = \int_{0}^{t} \frac{1}{\sum_{j \in \mathcal{A(T)}} w_j}d\mathcal{T}
> $$
> 
> 为什么不用上面的公式, 用per-task virtual time也能保持等式成立么.
>
> 在eevdf paper中，per-task vruntime的概念和stride sched 不太一样。stride sched算法
> 中，每个任务有自己的vruntime, 当该任务运行时，vruntime 会以根据自己权重计算
> 出的速率增长, 而到调度点时，则选择队列中最小的vruntime的任务运行。
>
> 计算$v_i$是使用一个比较大的值除$w_i$. 这样 $w_i$大的任务, $v_i$增长的较慢, 从而
> 获得更多的运行时间, 以Linux 为例:
>
> $$
> v_i = \frac{NICE\_0\_weight * 2^{32}}{w_i} * wall\_time
> $$
>
> ***
>
> 而eevdf 不是这样计算的. 这里我们大概总结下其算法:
> 1. 永远选择$V(d)$ 最小的 并且 lag > 0 的任务运行.
> 2. 运行时间由lag 决定，$lag \leq 0$ 时，则不再运行, 等待
> 3. 等待到什么时候呢? 等待到下一个eligble time
>
> 所以, 在eevdf中，所有任务的时间有一个统一的速率时间$V(t)$, 只不过大家在某段时
> 间内不同任务的调度优先级不同: 由$V(d)$决定, 并且在该服务时间中，获得的时间片
> 的比例也不同，有权重$w_i$ 决定。
>
> $$
> S_i(t_1, t_2) = w_i \int _{t_1} ^{t_2} \frac{1}{\sum_{j \in \mathcal{A(T)}}w_j} d \mathcal{T}
> $$
>
> 从这里也可以看到, 其获得的时间比例, 也满足比例分配的思想. 理想中所获得的时间，
> 是按照 该任务的权重的加权平均。
>
> 论文中最终推导的, 具体公式如下:
>
> $$
> \begin{align*}
> ve^{(1)} &= V(t_0^i) \\
> vd^{(k)} &= ve^{(k)} + \frac{r^{(k)}}{w_i} \\
> ve^{(k+1)} &= vd^{(k)}
> \end{align*}
> $$
>
> > 这里不介绍具体的推导过程。
>
> 由上面的公式，可以推导出, 在不考虑Dynamic Systems的情况下(没有任务加入退出，变
> 更权重等) 的运行逻辑:
> 1. 选择 $V(d)$ 最小的任务运行, 且 lag > 0
> 2. 计算该任务的到期时间 t ($lag_t = 0$ 当然也可能在该时间片, $lag_t < 0$), 
>    一直运行到t 时刻.
> 3. 该任务不再参与调度，一直等待到 $ve^{(k+1)}$
> 4. 获得新的请求时间，计算$vd^{(k+1)}$ 和 $ve^{(k+2)}$
>
> 一直循环。
>
> 所以从上面也可以看出, 整个过程均不需要per-task vruntime, 只需要一个全局的时间度量
> 单位 $V(t)$. 
>
> 那么问题来了，最初的公式(1)我们怎么理解呢?
>
> 这里，可以直观先理解下, $\sum{lag_t} = 0$ 表示在离散状态下，所有任务的lag 均在
> 互补的原则，某个任务用多了，其成本均摊到其他任务的头上, 其他任务就用少了. 所以
> 关键在于均摊，而不在于使用什么时间的度量单位。所以, 我们让用于计算的$V$ 和
> $v_i$, 使用统一的度量单位即可. 但是这个单位怎么设置呢? 我们来用数学公式推导下:
>
> 我们假设, eevdf 使用的virtual time 为 $v^{g}(t)$ (global virtual), 而步进算法使用
> 的 per-task virtual time为 $v(t)$, 可得下面计算公式
>
> $$
> \begin{align*}
> v^g(t) &= \frac{1}{W} * wall\_time \\
> v_i(t) &= \frac{A}{w_i}  * wall\_time \\
> \frac{v^g(t)}{v_i(t)} &= \frac{w_i}{W * A} \\
> v^g(t) &= \frac{w_i}{W * A} * v_i(t)
> \end{align*}
> $$
> 
> 同样的, 实际理想时间也用步进算法的虚拟时间单位:
>
> $$
> \begin{align}
> V^g(t) &= \frac{w_i}{W * A}V_i(t) \\
> \end{align}
> $$
> 
> 查看 注释中的式子是否等于0:
>
> $$
> \begin{align}
> \sum {w_i * (V - v_i)} &= \sum {w_i * (\frac{W * A}{w_i} V^g - \frac{W * A}{w_i}v^g)} \\
> &= W * A \sum {V^g - v^g}
> \end{align}
> $$
>
> 这不就是:
>
> $$
> W * A \sum lag_i = 0 \\
> 即 \\
> \sum log_i = 0
> $$
> 得到证明
>
>> 这个可以用数学上直观证明，关于等式求和，可以忽略常量部分(A, W)，只关注变量 $w_i, v_i$
>> 关于比变量部分$v_i = 常量 * w_i * vl_i$, 所以直接把变量部分 $w_i * vl_i$, 代
>> 入等式就成立
> {: .prompt-info}
{: .prompt-tip}

> NOTE:
>
> this is only equal to the ideal scheduler under the condition that join/leave
> operations happen at lag_i = 0, otherwise the virtual time has non-continguous
> motion equivalent to:
>
> $$
> v +-= lag_i / W
> $$
>
> Also see the comment in place_entity() that deals with this.

> 这个描述了理想的调度器, 理想调度器是什么呢? 就是不离散的, 所有任务以非常快的速度
> 无代价的切换, 也就是说, 任何任务在退出调度时，都得到了其应得的服务时间, 从而
> $lag_i = 0$。然而, 计算机是离散的。 这里采用策略1, 当在任务离开时, $lag_i > 0$, 
> 保存该lag, 而在任务加入时，任务会带着原来的$lag_i$ 加入，这里会引起$v$ 的不连续
> (跳变)
{: .prompt-info}

因为 $v_i$ 是 u64, 所以其和 $w_i$ 的乘机会轻易溢出。这里转换成一个等价的计算

$$
\begin{align}
V &= \frac{\sum{((v_i - v_0) + v_0) * w_i}}{W} \\
&= \frac{\sum{(v_i - v_0) * w_i} + \sum{v_0 * w_i}}{W} \\
&= \frac{\sum{(v_i - v_0) * w_i} + v0 * W} {W} \\
&= \frac{\sum{(v_i - v_0) * w_i}}{W} + v_0
\end{align}
$$

结合linux代码, 我们将
$$
\begin{align}
v_0 &:= cfs\_rq->min\_vruntime \\
\sum{(v_i - v_0) * w_i} &:= cfs\_rq->avg\_vruntime \\
\sum{w_i} &:= cfs\_rq->avg\_load
\end{align}
$$

> Since min_vruntime is a monotonic increasing variable that closely tracks the
> per-task service, these deltas: (v_i - v), will be in the order of the maximal
> (virtual) lag induced in the system due to quantisation.
> 
> Also, we use scale_load_down() to reduce the size.
>
> As measured, the max (key * weight) value was ~44 bits for a kernel build.z

> 由于 min_vruntime 是一个单调递增的变量，并且能够紧密地跟踪每个任务的服务进度，
> 因此这些差值 $v_i - v$ 的数量级，正好对应系统中由于量化（quantisation）所引入
> 的最大（虚拟）滞后。
> 
> 此外，我们使用 scale_load_down() 来减小数据规模。
> 
> 实际测量发现，在一次内核构建过程中，最大的（key * weight）值大约为 44 位。
{: .prompt-trans}

我们总结下, 经过上面推导，得到了$V$的计算公式:

$$
V = \frac{\sum(v_i - v_0) * w_i}{W} + v_0
$$

另外，将式子中的各个部分，保存在cfq_rq的各个成员中.

$$
\begin{align}
v_0 &:= cfs\_rq->min\_vruntime \\
\sum{(v_i - v_0) * w_i} &:= cfs\_rq->avg\_vruntime \\
W &:= cfs\_rq->avg\_load
\end{align}
$$

好，接下来我们来看下这些值的更新.

首先, 我们来关注下`min_vruntime`:

## update min_vruntime
以下面路径为例:
```sh
update_curr
=> curr->vruntime += calc_delta_fair(delta_exec, curr);
=> update_min_vruntime(cfs_rq);
   => u64_u32_store(cfs_rq->min_vruntime,
              __update_min_vruntime(cfs_rq, vruntime));
```
来看下`__update_min_vruntime`
```cpp
static u64 __update_min_vruntime(struct cfs_rq *cfs_rq, u64 vruntime)
{
    u64 min_vruntime = cfs_rq->min_vruntime;
    /*
     * open coded max_vruntime() to allow updating avg_vruntime
     */
    s64 delta = (s64)(vruntime - min_vruntime);
    if (delta > 0) {
        avg_vruntime_update(cfs_rq, delta);
        min_vruntime = vruntime;
    }
    return min_vruntime;
}
```

单`min_vruntime`的变化比较简单，其和cfs原本的算法一样, 
在`update_curr()`路径中, 每次都选择队列中最小将`min_vruntime`，
从而实现`min_vruntime`的单调递增。

但是，`min_vruntime`的更新，也会引起`avg_vruntime`的变化. 我们
在下一章介绍.

## update avg_vruntime

引起avg_vruntime 变化有多种

* update min_vruntime
* join/leave task $i$ with $lag_i > 0$

### due to update min_vruntime

首先计算`min_vruntime`前进了多少，并调用`avg_vruntime_update()`
更新`avg_vruntime`. 我们再回忆`avg_vruntime`的计算公式:

$$
\sum{(v_i - v_0) * w_i} = cfs\_rq->avg\_vruntime
$$

我们将更新后的 min_vruntime 记做 $v_0'$, 即 $v_0' = v_0 + \Delta{v_0}$

可得

$$
\begin{align}
v_0' &= v_0 + \Delta{v_0} \\
cfs\_rq->avg\_vruntime &= \sum{(v_i - v_0) * w_i)} \\
&= \sum{(v_i - (v_0' - \Delta{v_0})) * w_i} \\
&= \sum{(v_i - v_0') * w_i} - \sum{\Delta{v_0} * w_i} \\
&= \sum{(v_i - v_0') * w_i} - \Delta{v_0} * \sum{w_i} \\
&= \sum{(v_i - v_0') * w_i} - \Delta{v_0} * W \\
&= \sum{(v_i - v_0') * w_i} - delta * cfs\_rq->avg\_load
\end{align}
$$

所以, 当$v_0$ 增长了$\Delta{v_0}$后，需要将`avg_vruntime`减少
`delta * cfg_rq->avg_load`

代码如下:
```cpp
static inline
void avg_vruntime_update(struct cfs_rq *cfs_rq, s64 delta)
{
    /*
     * v' = v + d ==> avg_vruntime' = avg_runtime - d*avg_load
     */
    cfs_rq->avg_vruntime -= cfs_rq->avg_load * delta;
}
```

这里某些小伙伴可能会有些疑惑, `avg_vruntime`不应该时递增的么
(不考虑task i with $lag_i > 0$ join/leave), 为什么会减少呢?

`avg_vruntime` 不是$V(t)$, $V(t)$ 和`avg_vruntime`有一个转换公式.
最终得出的 $V(t)$ 的值和`min_vruntime`没有关系:

$$
V(t) = \frac{\sum{v_i * w_i}}{W}
$$

### due to join/leave task

在linux中，join/leave task 最终会触发入队出队:

* `__enqueue_entity`
* `__dequeue_entity`

具体的代码更改如下:

```diff
 static void __enqueue_entity(struct cfs_rq *cfs_rq, struct sched_entity *se)
 {
+	avg_vruntime_add(cfs_rq, se);
 	rb_add_cached(&se->run_node, &cfs_rq->tasks_timeline, __entity_less);
 }
 
 static void __dequeue_entity(struct cfs_rq *cfs_rq, struct sched_entity *se)
 {
 	rb_erase_cached(&se->run_node, &cfs_rq->tasks_timeline);
+	avg_vruntime_sub(cfs_rq, se);
 }
+static void
+avg_vruntime_add(struct cfs_rq *cfs_rq, struct sched_entity *se)
+{
+	unsigned long weight = scale_load_down(se->load.weight);
+	s64 key = entity_key(cfs_rq, se);
+
+	cfs_rq->avg_vruntime += key * weight;
+	cfs_rq->avg_load += weight;
+}
+
+static void
+avg_vruntime_sub(struct cfs_rq *cfs_rq, struct sched_entity *se)
+{
+	unsigned long weight = scale_load_down(se->load.weight);
+	s64 key = entity_key(cfs_rq, se);
+
+	cfs_rq->avg_vruntime -= key * weight;
+	cfs_rq->avg_load -= weight;
+}
```
在eevdf中, 论文中我们知道, 在 $lag_i > 0$的任务加入或者退出时，会引起
$V(t)$ 的跳变。

而关于任务join/leave 时，$lag_i$值的save和restore，有一些策略。论文第5章有描述:

1. In this strategy a client may leave or join the competition at any time, and
   depending on its lag it is either penalized or it receives competition
   > leave or join at any time, 并且根据其 lag 情况，惩罚或者奖励
2. any client that (re)joins the competition has zero lag
   > 任何client 在join 时，都带有zero lag
3. In this strategy a client is allowed to leave, join, or change its weight, only
   when its lag is zero.
   > 任务只能在其lag == zero 时，join 或者leave

这里的代码明显采用了策略1, 但是又不太一样。

我们来思考下, 论文中lag 的意义，lag的本意是, $S_i - s_i$, 

假设某个任务运行了请求在2s服务时间内运行1s
* 任务运行0.5s就退出了，则退出时lag 为正值(+0.5). 这多出的0.5s 可以分配给其他任
  务运行, 这些任务相当于无功而受禄。而等待其调度回来时，在多运行0.5s作为补偿, 相反
  其他任务则少运行0.5s.
* 而假设其运行了1.5s 退出, 则退出时 lag 为负值(-0.5). 这多消耗的0.5s 的代价需要其
  他任务承担。而等待其调度回来时，需要少运行0.5s作为惩罚。而其他任务则多运行0.5s
  作为其之前承担代价时的补偿。

eevdf是如何整理到数学公式上的呢? 体现在两个方面: lag, V(t), 我们来看下论文中如何
描述:

**lag:**

论文假设系统中有三个任务1,2,3。任务3在t时刻leave，$t^+$时刻是离t时刻十分接近的时
刻, 在这两个时刻 i 任务获得的实际运行时间相同(i.e., $s_i(t_0, t) = s_i(t_0, t^+)$)

最终得出:

$$
lag_i(t^+) = lag_i(t) + w_i\frac{lag_3(t)}{w_1+w_2}, i = 1,2.
$$

$lag$表示在该服务时间内,还可以实际运行的时间, 其值增加多少, 表示其实际运行时间可增加多少,
所以如果 $lag_3(t)$ 为正值, 任务1，2都可以喝点汤, 另外从公式可以看到, $lag_3(t)$ 实际被任
务1，2这哥俩加权平均分了, 吃的渣渣都不剩。

除了体现在lag上，也会体现在$V(t)$上:

**V(t)**:

直接列公式:

$$
V(t) = V(t) - \frac{lag_j(t)}{\sum_{i \in \mathcal{A(t^+)}}w_i}
$$

也就是说, 如果带有正数 $lag_j(t)$ 的任务leave，则发生电表倒转。倒转多少呢,
$lag_j(t)$ wall time 所代表的V. 所以V(t) 减少了，而其他的任务就非常高兴了，就好
像上网吧, 9 点的时候和室友充钱打算上网一个小时，结果半个小时后(9:30)，室友老婆查
水表提前下机了, 他下机后, 告诉老板，将剩余半个小时的钱冲到我的账上，老板说，没有
这么办的。室友无奈, 用毕生精力把电脑黑了，将时间修改为`9:00`, 这样我又能玩一个小
时. 但是我学到了精髓, 结果又上了一个半小时，此时怕老板查电费查出异常来，偷偷修改
了隔壁哥们的时钟，将其电表调快了半个小时...

所以，电表倒转和调整lag 所起到的效果是一致的。

再回到上面代码，他在干什么，在调整电表, 但是调整电表需要明确当前任务的lag. 将task
的lag定义为: `-lag = (vruntime - cfs_rq-> min_vruntime)`. 

***

基于此，我们在来重新理解下关于Linux虚拟时间的公式, 上面，我们证明了基于Linux 虚
拟时间的公式:

$$
V(t) = \frac{\sum {v_i * w_i}}{W}
$$

那么此时加入了一个带有lag $vl_i$ 的任务(假设lag 为正)，此时，我们期望在其他任务
运行之前，先运行 $vl_i$虚拟时间, 怎么办呢，将电表调快:

$$
V' = \frac{\sum{w_j * v_j} + w_i * v_i}{W + w_i}
$$

## 注释2  -- place_entity
```
/*
 * If we want to place a task and preserve lag, we have to
 * consider the effect of the new entity on the weighted
 * average and compensate for this, otherwise lag can quickly
 * evaporate.
 *
 * Lag is defined as:
 *
 *   lag_i = S - s_i = w_i * (V - v_i)
 *
 * To avoid the 'w_i' term all over the place, we only track
 * the virtual lag:
 *
 *   vl_i = V - v_i <=> v_i = V - vl_i
 *
 * And we take V to be the weighted average of all v:
 *
 *   V = (\Sum w_j*v_j) / W
 *
 * Where W is: \Sum w_j
 *
 * Then, the weighted average after adding an entity with lag
 * vl_i is given by:
 *
 *   V' = (\Sum w_j*v_j + w_i*v_i) / (W + w_i)
 *      = (W*V + w_i*(V - vl_i)) / (W + w_i)
 *      = (W*V + w_i*V - w_i*vl_i) / (W + w_i)
 *      = (V*(W + w_i) - w_i*l) / (W + w_i)
 *      = V - w_i*vl_i / (W + w_i)
 *
 * And the actual lag after adding an entity with vl_i is:
 *
 *   vl'_i = V' - v_i
 *         = V - w_i*vl_i / (W + w_i) - (V - vl_i)
 *         = vl_i - w_i*vl_i / (W + w_i)
 *
 * Which is strictly less than vl_i. So in order to preserve lag
 * we should inflate the lag before placement such that the
 * effective lag after placement comes out right.
 *
 * As such, invert the above relation for vl'_i to get the vl_i
 * we need to use such that the lag after placement is the lag
 * we computed before dequeue.
 *
 *   vl'_i = vl_i - w_i*vl_i / (W + w_i)
 *         = ((W + w_i)*vl_i - w_i*vl_i) / (W + w_i)
 *
 *   (W + w_i)*vl'_i = (W + w_i)*vl_i - w_i*vl_i
 *                   = W*vl_i
 *
 *   vl_i = (W + w_i)*vl'_i / W
 */
```

我们前面证明过:

$$
V = \frac{\sum{w_j * v_j}}{W}
$$

并当时说明，该等式成立的前提是, 任务都是带有 $lag_i = 0$ 离开和加入，
我们来看下, 如果$lag_i \neq 0$, 得到的结果将会有什么样的偏差。我们将
$vl_i$ 记做本次加入的任务，在之前退出竞争时的lag值, 根据上面公式可得:

$$
\begin{align*}
\sum{w_j * v_j} &= W * V \\
vl_i &= V - v_i \\
v_i &= V - vl_i
\end{align*}
$$

当任务加入时:

$$
\begin{align*}
V' &= \frac{\sum{w_j * v_j} + w_i * v_i}{W + w_i} \\
   &= \frac{W * V + w_i * v_i}{W + w_i} \\
   &= \frac{W * V + w_i * (V - vl_i)}{W + w_i} \\
   &= \frac{W * V + w_i * V -  w_i * vl_i}{W + w_i} \\
   &= \frac{V * (W + w_i)  - * w_i * vl_i}{W + w_i} \\
   &= V - \frac{w_i * vl_i}{W +w_i} \tag{1\_m}
\end{align*}
$$

我们来对比下论文中的公式:

$$
V(t) = V(t) + \frac{lag_j(t)}{\sum_{j \in \mathcal{A(t^+)}} w_i}  \tag{19}
$$

似乎有一些不同，但是需要注意的是, 论文中的$V(t)$指的是前文提到的`global virtual
time`, 而论文中的`virtual time`指的是按照`stride schedule`算法定义的`per-task
virtual time`, 我们前面解释过, $v(t)$(`per-task virtual time` 和 $v^g(t)$
`(global virtual time)`有一个比例关系

$$
v^g(t) = \frac{w_i}{W * A} v_i(t)
$$

而$lag$不同, 论文中的$lag$指的是实际时间, 其比例关系如下:
我们将论文中的lag记做: $lag_{real}$

$$
\begin{align*}
lag_g = \frac{1}{W}lag_{real} \\
lag^g(t) = \frac{w_i}{W * A} vl(t) \\
\frac{1}{W}lag_{real} = \frac{w_i}{W * A} vl(t) \\
lag_{real} = \frac { w_i * W}{W * A} vl(t) \\
vl(t) = lag_{real} \frac{W * A}{w_i * W}
\end{align*}
$$

当任务加入后, 总权重发生了变化

$$
W  = W + w_i
$$

代入, `(1_m)`后可得:

$$
\begin{align}
\frac{(W + w_i) A}{w_i}V^{g'} &= \frac{(W + w_i) A}{w_i} V^g - \frac{w_i * lag_{real} \frac{(W  + w_i)* A}{w_i * (W + w_i)}}{W + w_i} \\
V^{g'} &= V^g - \frac{\frac{w_i}{W + w_i}lag_{real}}{W+w_i} \\
\end{align}
$$


前面提到过论文公式中的$lag_j(t)$ 其实是real time，也就是上面的$lag_{real}$, 所以
我们看到, 如果使用上面的计算方式，得到的变化后的$V(t)$，根本不对，怎么修正呢? 从公式
中可以看出，我们仅修正$lag$即可, 让修正后的$vl_{fix}$为

$$
vl_{fix} = \frac{W +w_i}{w_i}vl
$$

即可

***

代码中的注释也说明了这一点. 但是其不是这么证明的。
细节如下:

首先计算lag在$V$变化为$V'$, lag值 $vl$ 发生了什么样的变化，然后再调整其值,
使$V(t)$ 符合预期。首先我们来看 $vl$ 的变化:

$$
\begin{align}
vl'_t &= V' - v_i \\
&=  (V - \frac{w_i*vl_i}{W + w_i}) - (V - vl_i) \\
&= vl_i - \frac{w_i*vl_i}{W + w_i}
\end{align}
$$

可以看到$vl'_t$比$vl_i$ 要小. 也就是强行使用该计算方式，相当于使用了一个
比任务睡眠时的$lag$ 要小一些的$lag$, 那现在怎么办呢? 我们在任务再次进入竞争时，
膨胀将$lag$变大(**inflate the lag**)， 膨胀多少呢?

我们接着上面的公式计算

$$
\begin{align*}
vl'_i &= vl_i - \frac{w_i * vl_i}{W + w_i} \\
&= \frac{vl_i (W +w_i) - w_i * vl_i}{W+w_i} \\
&= \frac{w_i}{W+w_i} vl_i \\

vl_i &= \frac{W+w_i}{w_i} vl_i'
\end{align*}
$$

既然$vl_i$变为使用上面计算公式后，变为了原来的$\frac{w_i}{W+w_i}$, 那么我们让
$vlag$在任务调度回来时膨胀到原来的 $\frac{W+w_i}{w_i}$ 即可.

具体代码:

```sh
place_entity
|-> u64 vruntime = avg_vruntime(cfs_rq);
|-> if (sched_feat(PLACE_LAG) && cfs_rq->nr_running)
    ## 相当于旧vlag, 我们要膨胀这个旧的vlag
    |-> lag = se->vlag;
    ## load相当于W
    |-> load = cfs_rq->avg_load;
    ## lag' = lag * (W + w_i)
    |-> lag *= load + scale_load_down(se->load.weight);
    ## lag' = lag * (W + w_i) / w_i
    |-> lag = div_s64(lag, load);
    ## 至此得到膨胀后的lag'
## 将虚拟时间减去lag，表示对该任务的补偿
|-> se->vruntime = vruntime - lag;
```
经过这一番折腾, 得到的结果符合论文中的公式。


## 参考链接
1. [MAIL sched: EEVDF and latency-nice and/or slice-attr](https://lore.kernel.org/all/20230531115839.089944915@infradead.org/)
2. PATCH
   ```
   d07f09a1f99c sched/fair: Propagate enqueue flags into place_entity()
   e4ec3318a17f sched/debug: Rename sysctl_sched_min_granularity to sysctl_sched_base_slice
   5e963f2bd465 sched/fair: Commit to EEVDF
   e8f331bcc270 sched/smp: Use lag to simplify cross-runqueue placement
   76cae9dbe185 sched/fair: Commit to lag based placement
   147f3efaa241 sched/fair: Implement an EEVDF-like scheduling policy
   99d4d26551b5 rbtree: Add rb_add_augmented_cached() helper
   86bfbb7ce4f6 sched/fair: Add lag based placement
   e0c2ff903c32 sched/fair: Remove sched_feat(START_DEBIT)
   af4cf40470c2 sched/fair: Add cfs_rq::avg_vruntime

   ```
3. [【管中窥豹】浅谈调度器演进的思考，从 CFS 到 EEVDF 有感](https://www.zhihu.com/people/rsy56640/posts)
4. [zzh csdn](https://blog.csdn.net/father_yingying?type=blog)
5. [MAIL: sched: EEVDF and latency-nice and/or slice-attr](https://lore.kernel.org/all/20240405102754.435410987@infradead.org/)

## 其他
1. [Ben 发现lag 存在的问题](https://lore.kernel.org/all/xm26fs2fhcu7.fsf@bsegall-linux.svl.corp.google.com/)
