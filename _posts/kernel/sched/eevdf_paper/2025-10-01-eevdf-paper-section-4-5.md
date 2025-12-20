---
layout: post
title:  "eevdf paper -- section 4 - 5"
author: fuqiang
date:   2025-10-01 21:00:00 +0800
categories: [schedule, paper]
tags: [sched]
math: true
---

## 4. Fairness in Dynamic Systems

本节讨论了 **dynamic system** 的公平性问题。主要包括三种动作:

* client jion
* client leave
* client change weight

在理想环境下, 这都不是问题，因为 $lag_i = 0$(都是0)。但是在离散的时间片分配中,
任务总会带着$lag$离开加入竞争, 我们先思考两个问题:

1. 当任务带着$lag_i \ne 0$ jion, leave, reweight, 会对其他client产生什么影响
2. 当任务带着$lag_i \ne 0$ 离开竞争，过一段时间后，重新加入竞争，其$lag_i$应该是
   什么值?

直接说答案:
首先说问题一:

带有$lag < 0$的任务离开，会导致其他进程的可用服务时间减少，而带有负$lag < 0$的任务
的任务离开，会让其他进程的服务时间增大。另外, 其他任务分配负lag资源/承担正lag损失,
应该按照其权重比例分配。

该策略有一个好处，就是简单的通过调整$V(t)$就可以达到效果。怎么理解呢, 当某个
任务带有$lag < 0$, 离开时, 我们只需要计算$lag$所对应的虚拟时间，在原来的$V(t)
$上加上该时间。 相当于其他的任务看到自己的表突然变快了 $\Delta{V(t)}$，由于虚
拟时间的定义，变化的$\Delta{V(t)}$ 实际上按比例平摊给了其他client。（理解起来
非常直观，计算起来也比较方便)

这和步进算法不太一样。步进算法在client 离开或者加入竞争时。其算法只是修改了虚拟
时间的斜率，而eevdf还修改了虚拟时间的值。(但实际上，论文中的步进算法修改了加入
竞争的client 的虚拟时间, 其实也相当于变相修改了global virtual time)

> 我们来回忆下, 在步进算法论文中，其是如何处理的.
>
> 步进算法论文中其也搞了一个`global virtual time`, `global virtual time`以
> $\frac{stride1}{\sum W_i}$ 的步幅前进，而其中的client $i$ 是以
> $\frac{stride1}{W_i}$ 的步幅前进，每个调度点，都会根据该任务的步幅更新该任务
> 的虚拟时间，也根据全局的步幅，更新`global virtual time`, 那么问题来了，
> 
> > `global virtual time` 和 `per-client virtual time` 应该有什么样的关系? 
> {: .prompt-warning}
>
> 其实和eevdf的算法有点像，
> * 在理想情况下, 任务每次运行都选择 client 中最小的vruntime运行。在某一时刻，
>   所有任务的vruntime都相同。都等于`global virtual time`
> * 但现实情况是, `per-client virtual time`比`global virtual time`的步幅大
>   当`per-client virtual time > global virtual time`时，相当于其用超了时间片,
>   反之亦然。
> * 当`per-client virtual time < global virtual time`时，相当于还有一些额外的
>   时间片没有使用, 需要立即追赶`global virtual time`
>
> 所以 每个`per-client virtual time - glboal virtual time`反应了当前任务运行
> 公平性
>
> 我们简单用公式理解下, 我们假设目前有两个任务 $w_1$, $w_2$, 并且$stride1 =
> A$, 我们两个 client 的步幅 以及`global_stride`为:
>
> $$
> stride_{c1} = \frac{A}{w_1} \\
> stride_{c2} = \frac{A}{w_2} \\
> stride_{g} = \frac{A}{w_1 + w_2}
> $$
>
> 当 client 1 运行了时间 $t_0$ 后, $V_{g}$ 和 $V_{c1}$的差距:
>
> $$
> \begin{align*}
> V_{c1} - V_{g} &= \frac{A}{w_1} t_0 - \frac{A}{w_1+w_2} t_0 \\
> &= \frac{w_1+w_2 - w_1}{w_1(w_1+w_2)}A * t_0 \\
> & = \frac{w_2}{w_1(w_1+w_2)}A * t_0
> \end{align*}
> $$
>
> 而这部分时间对应的real time为:
>
> $$
> \begin{align*}
> R(t) = V(t) * \frac{w_1 + w_2}{A} = \frac{w_2}{w_i} t_0
> \end{align*}
> $$
>
> client2， 应该运行 $\frac{w_2}{w_i} t_0$, 才是公平的。
>
> **所以, 这也能看出来在步进算法中的global virtual time 和 per-client virtual
> time 的差值 跟 eevdf 的lag很像**
>
> 所以, 步进算法论文中，通过这种方式将lag计算出来:
> ```
> client_leave:
> => c->remain =  c->pass - global_pass
> ```
> 这个差值，等待下次任务再次加入时，在把这个差值加上。
> ```
> client_join:
> => c->pass += global_pass + c->remain
> ```
> 
> ***
>
> 但是Linux CFS的实现就不一样了。其并没有全局的global virtual time。所以
> 其client离开，再加入时，`per-task virtual time`如何更新就是一个很大的问题。
> 怎么衡量当前任务有没有用超时间片呢?
>
> 对此Linux 开发者，搞出了一堆启发式算法来寻找比较合适的virtual time值。
>
> 见`place_entity()`, 首先为了避免新创建client join造成的其他进程的饥饿。将
> 他们放到下一个时间片中运行。这没什么问题:
> ```
>  if (initial && sched_feat(START_DEBIT))
>     vruntime += sched_vslice(cfs_rq, se);
> ```
> 其次，唤醒的任务，则将vruntime再提前一些vruntime, 相当于让其多跑一会
> ```
>    /* sleeps up to a single latency don't count. */
>    if (!initial) {
>        unsigned long thresh = sysctl_sched_latency;
>
>        /*
>         * Halve their sleep time's effect, to allow
>         * for a gentler effect of sleepers:
>         */
>        /*
>         * 该feature会降低睡眠进程对当前任务的影响. 只让vruntime提前
>         * 半个 sysctl_sched_latency
>         */
>        if (sched_feat(GENTLE_FAIR_SLEEPERS))
>            thresh >>= 1;
>
>        vruntime -= thresh;
>    }
>
>    /* ensure we never gain time by being placed backwards. */
>    /* 
>     * 这里其实变相防止了任务在频繁schedule() 而让task一直享用min_vruntime
>     * 的问题，如果此时 任务的 se->vruntime > min_vruntime, 说明该任务没有离开
>     * 太长时间，不需要补偿
>     */
>    se->vruntime = max_vruntime(se->vruntime, vruntime);
> ```
> 可以看到，linux kernel并没有关心该任务在调度走之前的状态, 如果调度出去比较
> 长的时间，其会在min_vruntime的基础上，在额外补偿一些时间片。站在公平性的角度
> 上也可以理解，毕竟那么多的时间片都没有参与竞争，白白让给了其他竞争者，那现在
> 加入竞争了，吃点好的怎么了。可以看到linux kernel在这个地方的策略和eevdf以及
> 论文的步进算法有些不同。
{: .prompt-info}

**client leave**

论文中, 举了一个例子来看 带有 $lag_i \ne 0$ 的任务 join, leave 对其他进程$lag$
和$V(t)$的影响。

```

client 1 +-----------------+-----------------
         |                 |
client 2 +-----------------+-----------------
         |                 |
client 3 +-----------------+
         |                 |
         t_0               t
```

目前有三个client, 在 $t_0$ 时刻，这三个任务的$lag$ 都为0, 在 $t$ 时刻，client 3 
leave.并且假设，在 $[t_0, t)$ 这段时间之内，没有其他任务有 `leave`, `join`,`change
weight`的情况.

我们首先来看下每个任务的$lag$ 是如何变化的:

$$
\begin{align*}
lag_i(t) &= S_i(t_0 - t) - s_i(t_0, t) \\
&= w_i(V(t) - V(t_0)) - s_i(t_0, t) \\
&= w_i\frac{t - t_0}{w_1+w_2+w_3} - s_i(t_0, t) i=1,2,3. \tag{13}
\end{align*}
$$

因为 `eevdf` 是 `work-conserving` 算法, 所有任务在 $[t_0, t)$ 得到的实际服务时间
只和, 应等于 $t - t_0$. 因此，client 1, client 2收到的实际的服务时间为:

$$
t - t_0 - s_3(t0, t)
$$

再定义一个时间点 $t^+$, 表示client 3 刚刚leave时的时间点, 加入我们忽略调度器
本身的损耗: $t^+ \rightarrow t$, 但是这一时刻任务的总权重变了, 我们可以得到
剩余任务的应得的服务时间:

$$
S_i(t_0, t^+) = (t - t_0 - s_3(t_0, t)) \frac{w_i}{w_1+w_2}, i = 1,2  \tag{14}
$$

根据之前的公式, 可得:

$$
S_i(t_0, t) - s_3(t_0, t) = lag_3(t)
S_i(t_0, t) = (t - t_0)\frac{w_3}{w_1+w_2+w_3}
$$

结合可得:

$$
\begin{align*}
S_i(t_0, t^+) &= (t - t_0 - s_3(t_0, t)) \frac{w_i}{w_1+w_2}, i = 1, 2 \\
&=(t - t_0 - (S_3(t_0, t) - lag_3(t))) \frac{w_i}{w_1+w_2} \\
&=(t - t_0 - \frac{(t - t_0) * w_3}{w_1+w_2+w_3} + lag_3(t)) \frac{w_i}{w_1+w_2} \\
&=\frac{(t - t_0)(w_1+w_2+w_3) - (t - t_0) * w_3}{w_1+w_2+w_3} * \frac{w_i}{w_1+w_2} + w_i\frac{lag_3(t)}{w_1+w_2} \\
&= \frac{(t - t_0)(w_1+w_2)}{w_1+w_2+w_3} * \frac{w_1}{w_1+w_2} + w_i\frac{lag_3(t)}{w_1+w_2} \\
&= \frac{(t-t_0)w_1}{w_1+w_2+w_3} + w_i\frac{lag_3(t)}{w_1+w_2} \\
&= w_i(V(t) - V(t_0)) + w_i\frac{lag_3(t)}{w_1+w_2} \tag{15}
\end{align*}
$$

因为:
$$
S_i(t_0, t^+) = w_i(V(t^+) - V(t_0))
$$


推导:
$$
\begin{align*}
w_i(V(t^+) - V(t_0)) &= w_i(V(t) - V(t_0)) + w_i\frac{lag_3(t)}{w_1+w_2} \\
V(t^+) &= V(t) + \frac{lag_3(t)}{w_1+w_2} \tag{16}
\end{align*}
$$

可以看到在此刻, $V(t)$ 发生了跳变.

由于$t^+$ 和 $t$ 非常接近, 所以

$$
\begin{align*}
s_i(t_0, t) &= s_i(t_0, t^+) \\
lag_i(t^+) &= S_i(t_0, t^+) - s_i(t_0, t^+) \\
&= w_i(V(t^+)  - V(t_0)) - s_i(t_0, t) \\
&= w_i(V(t^+) - V(t_0)) - (S_i(t_0, t) - lag_i(t)) \\
&= w_i(V(t^+) - V(t_0)) - (w_i(V(t) - V(t_0)) - lag_i(t)) \\
&= w_i(V(t^+) - V(t)) + lag_i(t) \\
&= w_i\frac{lag_3(t)}{w_1+w_2} + lag_i(t) \tag{17}
\end{align*}
$$

所以，此时 $lag_i(t)$ 也发生了跳变.

因此，当客户端3离开时，它的 $lag$ 会按比例分配给剩余的客户端，这与我们对公平性的
理解是一致的。通过对`公式(9)`进行推广，我们得出了以下虚拟时间的更新规则：当某个客
户端j在时刻t退出竞争时，虚拟时间应按如下方式更新。

$$
V(t) = V(t) + \frac{lag_j(t)}{\sum_{i \in \mathcal{A}(t^+)} w_i} \tag{18}
$$


**client join**

论文中还提到:

> Correspondingly, when a client $j$ joins the competition at time $t$, the
> virtual time is updated as follows

$$
V(t) = V(t) - \frac{lag_j(t)}{\sum_{i \in \mathcal{A}(t^+)} w_i} \tag{19}
$$

我们来推导下这部分:

当task 3 任务带有 $lag_3$ 不为0时加入调度, 我们应该将$lag_j$这部分时间补偿/惩罚
给其他进程，和离开时相反:

* $lag_j$ > 0 : 补偿
* $lag_j$ < 0 : 惩罚

我们将现在的时刻记为$t$, 将来的某个时刻记做$t_n$, 进程刚进入completion的时刻为
$t^+$, 如下图所示
```
task 1 -----------
task 2 -----------
task 3 -----------
      t,t+       tn
```

我们这里要给予task3 惩罚

$$
s_3(t, t_n) = S_3(t, t_n) - lag_3(t)
$$

可以推导

$$
\begin{align}
S_i(t^+, t_n) &= ((t_n - t) - s_3(t, t_n))\frac{w_i}{w_1+w_2+w_3} \\
&= ((t_n - t) - (S_3(t_n, t) - lag_3(t)))\frac{w_i}{w_1+w_2+w_3}  \\
&= w_i(V(t_n) - V(t)) - lag3(t)\frac{w_i}{w_1+w_2+w_3} \\

w_i(V(t_n) - V(t^+)) &= w_i(V(t_n) - V(t)) + lag3(t)\frac{w_i}{w_1+w_2+w_3} \\

V(t^+) &= V(t) + \frac{lag3(t)}{w_1+w_2+w_3} 

\end{align}
$$

继而可以得出上面的公式.

任务加入和任务离开不同的是, 当任务 $j$ 再次到达时，任务 $j$ 会自带一个 $lag_j(t)$,
但是任务 $j$ 再次加入时，$lag_j(t)$应该取什么样的值. 这里我们先不考虑。

**change weight**

上面提到的是任务加入与推出，那么设想下，如果任务的权重发生了变化，那$V(t)$ 该如
何计算呢?

> We note that changing the weight of an active client is equivalent to a leave
> and a rejoin operation that take place at the same time. To be specific,
> suppose that at time $t$ the weight of client $j$ is changed from $w_j$ to
> $w'_j$ . Then this is equivalent to the following two operations: client j
> leaves the competition at time t, and rejoins it immediately (at the same time
> t) having weight $w'_j$ . By adding Eq. (18) and (19), we obtain

论文中提到，任务权重发生变化，相当于任务触发了leaves 和join 操作，只不过在加入后，
任务的权重从$w_j$ 变为了$w'_j$

那么可得下面的公式:

$$
V(t) = V(t) + \frac{lag_j(t)}{\sum{_{i \in \mathcal{A}(t^+)} w_i} - w_i} - 
   \frac{lag_j(t)}{\sum{_{i \in \mathcal{A}(t^+)} w_i} - w_j + w'_j} \tag{20}
$$

***

好, 接下来我们考虑第二个问题, client 带着 $lag_i \ne 0$, 离开，那再次加入时，应
该带 $lag$ 加入

这个并不好处理。直观上来看, 如果client $lag_i$ 离开, 那就应该带 $lag_i$加入。假
设 $lag_i$ 在离开的时候大于0，在离开时，其多分配的时间将由剩余的client承担, 这些
client 获得的服务时间将少于应得的服务时间。当client 再次加入时, 因为之前多分配了
时间片, 应该受到惩罚，而剩余的任务应该获得些奖励。但是，事情总不是那么完美，例如:
在client 1 带有 $lag_1 > 0$ 离开时，任务2, 3承担了这些代价，但是等待任务1 再次加
入时，任务2, 3 也暂时离开了，但是任务4在先前加入。这时候，如果带有原来的lag加入，
相当于任务2，3承担代价，但是任务4 得到奖励。所以，这个问题没有标准答案。在下一章
节, 论文讨论了三种策略

## 5. Algorithm Implementation

该章节主要介绍了三种策略:

* client 可以在任意时刻 join, leave, 并 $lag_{join} = lag_{leave}$

  这种策略适用于希望client 在多个周期保持公平性的系统

* client 可以在任意时刻 join, leave, 并且 $lag_{join} = 0$

  这种策略适用于那些使client 变为活跃的事件彼此独立的系统。这类似于实时系统，其
  中假定一个事件所需的处理时间与其他事件所需的处理时间是相互独立的。

  (相当于client 处理事件，但是每个事件相互独立 ---- A event 的欠帐凭什么B event
  来还)

* client 只能在 $lag = 0$ 时join, leave.

我们接下来主要讨论最后这种策略。

文章首先讨论了`undo`处理方法, `undo`的意思是撤销。其目的是撤销目前的系统状态，到
$lag = 0$时刻。

例如目前有两个服务A ,B, C. A 在 $t_1$ 时刻带有 $lag > 0$ 离开，按照要求其应该在
$lag = 0$ 离开，我们记 $lag_A = 0$ 的时刻是 $t_0$, $t_0 = t_1 - \Delta t$, 那么
在就让整个系统的状态会退到 $t_0$ 时刻. 我们设想下有哪些状态, B,C 任务的 $V(e),
V(d), s_i$ 以及全局的 V(t), 因为我们在过去的时刻不知道任务A在何时离开，所以
得维护一个类似于event log数据库(用来存放上面这些变量更改的事件信息)。这实现起
来非常 expensive.

***

作者想寻求一个比价cheap的方案达到类似的效果. 首先做了一个假设限制: join, leave,
reweight 这些事件并不会在一个时间片中发生。这也符合操作系统的调度方式，这个限制
不过分。

接下来分情况讨论:

$lag \ne 0$ 离开主要包含两种:

* $lag < 0$: 表示实际服务时间大于理论服务时间（用超了) 

  我们选择让任务等待到 $lag \geq 0$时releave, 作者想到发出一个新的service_time =
  0的request，等待该request完成在离开。

  首先当前时刻 $lag < 0$, 该client在达到$ve{(k+1)}$ 时都不会在发出新的请求。
  而根据公式(10):

  $$
  ve^{(k+1)} = vd^{(k)}
  $$

  因为新的 `request service time = 0`, 所以新的request:
  $$
  vd^{(k+1)} = ve^{(k+1)}
  $$

  而有根据第六章的推论:

  在一个虚拟时间连续变化的系统（如我们的系统）中，某个请求保证会在其截止时间之后
  不超过一个时间片的时间内被满足。

  我们将 $t_0 = vd^{(k+1)}$, 假设该client 在 $t_1$ 时刻完成了新的请求(任务在
  $t_1$ leave)

  $$
  \begin{align*}
  t_1 - t_0 &< q \\
  t_{leave} - t_{lag = 0} &< q
  \end{align*}
  $$

  因此，从客户端的 $lag$ 变为零的那一刻，到请求被满足的那一刻之间，不会分配其他的
  时间片。由于在这个时间片期间没有事件发生，所以无论我们是在滞后量变为零时更新虚
  拟时间，还是在时间片结束后再更新虚拟时间，实际上都没有区别。

  > 数学真的美妙，无法真正理解其内涵，只能远远欣赏。

* $lag > 0$: 表示服务事件还没有用完。

  这个作者给出了一个非常简单的处理方式: 该client的剩余的服务事件，分配给剩余的
  client，不向他们收费（不用承担任何代价）。我们可以认为，在client leave 执行了
  公式(18), 但是join 时不会执行公式(19)（因为其join时, $lag = 0$)

