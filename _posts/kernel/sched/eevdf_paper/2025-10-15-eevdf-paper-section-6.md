---
layout: post
title:  "eevdf paper -- section 6"
author: fuqiang
date:   2025-10-15 21:40:00 +0800
categories: [schedule, paper]
tags: [sched]
math: true
---

## 6 Fairness Analysis of the EEVDF Algorithm

In this section we determine bounds for the service time lag. First we show that
during any time interval in which there is at least one active client, there is
also at least one eligible pending request (Lemma 2). A direct consequence of
this result is that the EEVDF algorithm is work-conserving, i.e., as long as
there is at least one active client the resource cannot be idle. By using this
result, in Theorem 1 we give tight bounds for the lag of any client in a steady
system (see Denitions 1 and 2 below). Finally, we show that in the particular
case when all the requests have durations no greater than a time quantum q, our
algorithm achieves tight bounds which are optimal with respect to any
proportional share allocation algorithm (Lemma 5).

> 本节我们将确定服务时间 lag 的界限。首先，我们证明在任何存在至少一个活跃客户端
> 的时间区间内，必然也存在至少一个符合条件的待处理请求（见引理2）。这一结果的直
> 接推论是，EEVDF 算法是 work-conserving 的，也就是说，只要有至少一个活跃客户端，
> 资源就不会空闲。基于这一结果，我们在定理1中为稳态系统中任意客户端的 lag 给出了
> 严格界限（见下方定义1和定义2）。最后，我们还证明，在所有请求的持续时间均不超过
> 一个时间片 q 的特殊情况下，我们的算法能够实现最优的严格界限，与任何比例分配算
> 法相比都是最优的（见引理5）。
>
> > work-conserving 调度算法会确保资源始终被分配给等待的任务，不会让资源空闲，除
> > 非队列里没有任务。
> {: .prompt-tip}
{: .prompt-trans}

Throughout this section we refer to any event that can change the state of the
system, i.e., a client joining or leaving the competition, and changing the
client's weight, simply as event. We introduce now some definitions to help us
in our analysis.

> 在本节中，我们将任何可能改变系统状态的事件——即客户端加入或离开竞争，以及更改客
> 户端权重——统称为事件。接下来，我们将引入一些定义以辅助我们的分析。
{: .prompt-trans}

### Definition 1

**Definition 1** A system is said to be **steady** if all the events occurring
in that system involve only clients with $zero$

> 给出了 **steady system** 的定义: 所有event 均发生在 client with zero lag.
{: .prompt-tip}

Thus, in a steady system the lag of any client that joins, leaves, or has its
weight changed, is zero. Recall that in a system in which all events involve
only clients having zero lags the virtual time is continuous. As we will see,
this is the basic property we use to determine tight bounds for the client lag.
The following definition restricts the notion of steadiness.

> 因此，在一个稳态系统中，任何加入、离开或权重发生变化的客户端，其 lag 都为零。
> 请注意，在一个所有事件仅涉及 lag 为零的客户端的系统中，虚拟时间是连续的。正如
> 我们将看到的，这正是我们用来确定客户端 lag 严格界限的基本性质。下面的定义对
> steadiness 的概念进行了限定。
{: .prompt-trans}

### Definition 2

**Definition 2** An interval is said to be **steady** if all the events
occurring in that interval involve only client with zero lag

> 给出了 **steady interval** 的定义: 在某个 interval 内，所有event
> 均在 client with zero lag 发生。
{: .prompt-tip}

We note that a steady system could be alternatively defined as a system for
which any time interval is steady. The next lemma gives the  condition for a
client request to be eligible.

> 结合 **steady interval** 和 **steady system**, 可以推导出, 在在任意时间的
> interval 都是 steady 的可以成为 **steady system**. 
{: .prompt-tip}

### lemma 1

**Lemma 1** Consider an active client $k$ with a positive $lag$ at time $t$,
i.e.,

$$
lag_k(t) \geq 0;
$$

*Then client k has a pending eligible request at time t*

> 下面给出了这条引理的证明:
{: .prompt-tip}

**Proof**. Let r be the length of the pending request of client k at time t
(recall that an active client has always a pending request), and let $ve$ and
$vd$ denote the virtual eligible time and the virtual deadline of the request.
For the sake of contradiction, assume the request is not eligible at time t,
i.e.,

> 证明：设 r 为客户端 k 在时刻 t 的待处理请求的长度（注意，活跃客户端始终有一个
> 待处理请求），令 $ve$ $vd$ 分别表示该请求的虚拟可执行时间和虚拟截止时间。为
> 进行反证，假设该请求在时刻 t 不具备可执行资格，即，
{: .prompt-trans}

$$
ve > V(t)
$$

Let $t'$ be the time when the request was initiated. Then from Eq. (7) we have

> r : 客户端k 在t 时刻待处理请求的长度
> 
> t': 为发起请求的时刻
> > 注意，这里的发起请求，是指new request， 也就是next)
> {: .prompt-info}
{: .prompt-tip}

$$
ve = V(t_0^k) + \frac{s_k(t_0^k, t')}{w_k}
$$

Since between $t'$ and $t$ the request was not eligible, it follows that the
client has not received any service time in the interval $[t', t)$, and
therefore $s_k(t_0^k, t') = s_k(t_0^k, t)$ . By substituting $s_k(t_0^k, t')$ to
$s_k(t_0^k, t)$ in Eq. (23) and by using Eq. (3) and (6) we obtain

$$
\begin{align}
lag_k(t) &= w_k(V(t) - V(t_0^k)) - s_k(t_0^k, t) \\
&= w_k(V(t) - V(t_0^k)) - w_k(ve - V(t_0^k)) \\
&= w_k(V(t) - ve)
\end{align}
$$

> 我们详细推导下:
>
> $$
> \begin{align}
> s_k(t_0^k,t') &=  we*w_k + V(t_0^k) \\
> lag_k(t) &= S_k(t_0^k, t) - s_k(t_0^k, t) \\
> &= S_k(t_0^k, t) - s_k(t_0^k, t')  \\
> &= w_k(V(t) - V(t_0^k)) - w_k(ve - V(t_0^k)) \\
> &= w_k(V(t) - ve)
> \end{align}
> $$
{: .prompt-tip}

Finally, from Ineq. (22) it follows that $lag_k (t) < 0$, which contradicts the
hypothesis and therefore proves the lemma.

> 由上面的等式可以得出 $V(t) - ve < 0$, 从而得出 $lag_k(t) < 0$
>
> 我们具体来思考下他是怎么证明的:
> 
> 需要证明的引理是: 如果一个客户端k, 在t时刻有一个正的lag, 那么客户端一定有一个
> pending的 eligible request.
>
> 那么证明的方法是，反证。
>
> 证明: 如果一个客户端k，在t时刻有一个正的lag, 客户端不一定有一个pending的eligible
> request. 如果没有eligible request，会是什么样的场景呢?
>
> $$
> ve > V(t)
> $$
>
> 结果推导出来，发一定是现$lag < 0$, 与假设矛盾，原来的定理成立。
{: .prompt-tip}

From Lemma 1 and from the fact that any zero sum has at least a nonnegative term,
we have the following corollary.

### Corollary 1

**Corollary 1** Let A(t) be the set of al l active clients at time t, such that

$$
\sum_{\substack{i\in A(t)}} lag_i(t) = 0
$$

Then there is at least one eligible request at time t.

> 这里的意思是，只要 $\sum_{\substack{i\in A(t)}} lag_i(t) = 0$, 至少有一个
> eligible request
>
> > **Corollary**: 表示推论, 不需要复杂证明
{: .prompt-tip}

The next lemma shows that at any time $t$ the sum of the lags over all active
clients is zero. An immediate consequence of this result and the above corollary
is that at any time t at which there is at least one active client, there is
also at least one pending eligible request in the system. Thus, in the sense of
the definition given in [23], the EEVDF algorithm is *work-conserving*, i.e., as
long as there are active clients the resource is busy

> 下一个引理表明，在任意时刻 ( t )，所有活跃客户端的滞后量之和为零。由此结果以及
> 上面的推论可以直接得出，在任何存在至少一个活跃客户端的时刻，系统中也必然存在至
> 少一个待处理且符合条件的请求。因此，根据[23]中给出的定义，EEVDF算法是工作保持
> （work-conserving）的，也就是说，只要有活跃客户端，资源就始终处于忙碌状态。
{: .prompt-trans}

### Lemma 2

Lemma 2 At any moment of time t, the sum of the lags of al l active clients is zero

$$
\sum_{\substack{i\in A(t)}} lag_i(t) = 0  \tag{26}
$$

**Proof**. The proof goes by induction. First, we assume that at time t = 0
there is no active client and therefore Eq. (26) is trivially true. Next, for
the induction step, we show that Eq. (26) remains true after each one of the
following events occurs: (i) a client joins the competition, (ii) a client
leaves the competition, (iii) a client changes its weight. Finally, we show that
(iv) during any interval $[t, t')$ in which none of the above events occurs if
Eq. (26) holds at time t, then it a n it also holds at time $t'$

> 证明。该证明采用归纳法。首先，我们假设在时间 t = 0 时没有活跃的客户端，因此公
> 式（26）显然成立。接下来，在归纳步骤中，我们证明在以下每一种事件发生后，公式
> （26）仍然成立：（i）有客户端加入竞争；（ii）有客户端离开竞争；（iii）有客户端
> 改变其权重。最后，我们证明（iv）在任意一个区间 [t, t′) 内，如果上述事件都没有
> 发生，且公式（26）在时间 t 时成立，那么它在时间 t′ 时也成立。
{: .prompt-trans}

**Case (i)**. Assume that client j joins the competition at time t with lag
$lag_j(t) $. Let $t^-$ denote the time immediately before, and let $t^+$ denote
the time immediately after client $j$ joins the competition, where $t^+$ and
$t^-$ are asymptotically close to t. Next, let $W(t)$ denote the total sum over
the weights of all active clients at time t, i.e., $W(t) = \sum_{i \in
\mathcal{A}(t)} w_i (t)$ and by convenience let us take $lag_j (t^-) = lag_j(t)$
. Since $t^- \rightarrow t^+$ we have $s_i(t_0^i, t^-) = s_i(t_0^i, t^+)$. Then
from Eq. (3) we obtain

> * $t^-$ : client j 加入前的很接近的时间
> * $t^+$ : client j 加入后的很接近的时间
>
> 并且为了方便让 $lag_j (t^-) = lag_j(t)$(这相当于一个策略让 任务j, $lag_j$
>
> 另外由于 $t^-$ 和 $t^+$ 两个时间很接近， 可以让 $s_i(t_0^i, t^-) = s_i(t_0^i,
> t^+)$
{: .prompt-tip}

$$
lag_i(t^+) = lag_i(t^-) + S_i(t_0^i, t^+) - S_i(t_0^i, t^-)
$$

Further, by using Eq. (6) and (19), the lag of any active client i at time $t^+$
(including client j) is

$$
lag_i(t^+) = lag_i(t^-) + lag_i(t) \frac{w_i}{W(t^+)}
$$

> 我们来推导下这部分:
> 
> $$
> \begin{align}
> lag_i(t^+) &= S_i(t_0^i, t^+) - s_i(t_0^i, t^+) \\
> &= S_i(t_0^i, t^-) + S_i(t^-, t^+) - s_i(t_0 ^ i, t^-) \\
> &= S_i(t_0^i, t^-) - s_i(t_0 ^ i, t^-)  + S_i(t^-, t^+) \\
> &= (S_i(t_0^i, t^-) - s_i(t_0 ^ i, t^-))  + (S_i(t^i_0, t^+) - S_i(t^i_0, t^-)) \\
> & = lag_i(t^-) + S_i(t^i_0, t^+) - S_i(t^i_0, t^-) \\
> & = lag_i(t^-) + w_i(V(t^+) - V(t_0^i)) - w_i(V(t^-) - V(t_0^i)) \\
> & = lag_i(t^-) + w_i(V(t^+) - V(t^-))
> \end{align}
> $$
> 
> 由于 $t^- \rightarrow t$ 并没有任务加入，两个时间又非常接近, 所以其 $V(t)$ 不会
> 发生跳变, 所以$V(t^-) = V(t)$, 从而得到
> 
> $$
> \begin{align}
> V(t^+) &= V(t) + \frac{lag_j(t)}{W(t^+)} \\
> &= V(t^-) + \frac{lag_j(t)}{W(t^+)}
> \end{align}
> $$
> 
> 带入可得:
> 
> $$
> \begin{align}
> lag_i(t^+) &= lag_i(t^-) + w_i(V(t^+) - V(t^-)) \\
> &= lag_i(t^-) + w_i(V(t^-) + \frac{lag_j(t)}{W(t^+)} - V(t^-)) \\
> &= lag_i(t^-) + \frac{lag_j(t)}{W(t^+)}
> \end{align}
> $$
{: .prompt-tip}

Since $\mathcal{A}(t^+) = \mathcal{A}{(t^-)} \cup {j}$,  and since from the
induction hypothesis we have $\sum{_{i \in{\mathcal{A}(t^-)}} lag_i(t^-)} = 0$,
by using Eq. (27), we obtain:

$$
\begin{align}
\sum _{\substack{i\in\mathcal{A}(t^+)}} lag_i(t^+) &=
\sum_{\substack{i\in\mathcal{A}(t^+)}} (lag_i(t) - lag_j(t)\frac{w_i}{W(t+)}) \\
&= \sum_{\substack{i\in\mathcal{A}(t^+)}} lag_i(t^-) - 
lag_j(t) \frac{\sum_{_{i\in\mathcal{A}(t^+)} }w_i}{W(t^+)} \\
&= \sum_{\substack{i\in\mathcal{A}(t^+)}} lag_i(t^-) + lag_j(t^-) - lag_j(t) = 0
\end{align}
$$

> 这里我们可以简单想下，为什么任务 $j$ 带有 $lag_j$ 进入竞争, 而
> $\sum_{\substack{i\in A(t)}} lag_i(t)$ 仍然不变等于0呢 ? 这部分 $lag$ 的变化，
> 被谁反向抵消了呢?
>
> A: 很直观，被其他的任务的 $lag$ 变化抵消了, 所以我们可以看下所有任务（包括j），
> 在j加入后的 $lag$ 变化来变相证明下.
>
> $$
> \begin{align}
> lag_i(t^+) &= lag_i(t) - w_i\frac{lag_j(t)}{\sum_{i \in \mathcal(A)} w_i} \\
> \sum_{\substack{i\in\mathcal{A}(t^+)}}\Delta{lag_i} &=
> \sum_{\substack{i\in\mathcal{A}(t^-)}}\Delta{lag_i} + lag_j(t) \\
> &= \sum_{\substack{i\in\mathcal{A}(t^-)}}\Delta{lag_i} + lag_j(t) \\
> &= - w_1\frac{lag_j(t)}{\sum_{i \in \mathcal{A}} w_i} - w_2\frac{lag_j(t)}{\sum_{i
> \in \mathcal{A}} w_i} +...+ log_j(t) \\
> &= -\frac{\sum{_{i\in\mathcal{A}(t^-)}w_i}} {\sum{_{i\in\mathcal{A}(t^-)}w_i}}lag_j(t)
> +lag_j(t) = 0
> \end{align}
> $$
>
> 其实, $lag_j(t)$ 和 $V(t)$ 的逻辑是相似的，带有非0 $lag_j(t)$ 的j任务离开/加入后, 其需要
> 别人付出代价，lag比较直接，让别的任务的lag承担。而V(t) 比较含蓄，只做V(t)的跳
> 变, 这样其他的 任务的$ve$也就近似发生转变...
{: .prompt-tip}

**Case (ii)**. The proof of this case is very similar to the one of the previous
case; therefore we omit it here.

> 这个和 Case(i) 很相似，作者将其省略, 可以想象成上面的等式中的
> $\sum_{\substack{i\in\mathcal{A}(t^-)}}\Delta{lag_i}$ 和 $lag_j(t)$ 符号相反，
> 得出的结果也是0.
{: .prompt-tip}

**Case (iii)**. Changing the weight of a client $j$ from $w_j$ to $w_j'$ $j$ at
time $t$ can be viewed as a sequence of two events: first, client $j$ leaves the
competition at time $t$; second, it joins the competition at the same time $t$,
but with weight $w_j'$. Thus, the proof of this case reduces to the previous two
case.

> 这里也好理解，将改变权重分为两部分, 任务 $j$ 带着$lag_{j1}(t)$离开，几乎在同一
> 时刻, 任务 $j$ 带着$lag_{j2}(t)$ 加入竞争. 虽然 $lag_{j1}(t)$ 和 $lag_{j2}(t)$
> 不相同, 但是不影响。因为离开加入作为独立event时，每个event执行后，
> $\sum_{\substack{i\in A(t)}} lag_i(t)$ 均不变。
{: .prompt-tip}

Case (iv). Consider an interval $[t, t')$ in which no event occurs, i.e., no
client leaves or joins the competition and no weight is changed during the
interval $[t, t')$ . Next, assume that $\sum_{\substack{i\in A(t')}} lag_i(t') =
0$, By using Eq. (3) and (6) we obtain:

$$
\begin{align}
\sum_{\substack{i\in\mathcal{A}(t')}}lag_i(t') &= \sum_{\substack{i\in\mathcal{A}(t')}}
(S_i(t_0^i - t') - s_i(t_0^i - t') \\
&= \sum_{\substack{i\in\mathcal{A}(t)}}((S_i(t_0^i - t) - s_i(t_0^i - t)) +
  \sum_{\substack{i\in\mathcal{A}(t)}}((S_i(t - t') - s_i(t - t')) \\
&= \sum_{\substack{i\in\mathcal{A}(t)}} lag_i(t) + 
\sum_{\substack{i\in\mathcal{A}(t)}}S_i(t - t') - \sum_{\substack{i\in\mathcal{A}(t)}}s_i(t - t') \\
&= \sum_{\substack{i\in\mathcal{A}(t)}}w_i(V(t') - V(t)) - \sum_{\substack{i\in\mathcal{A}(t)}}s_i(t, t') \\
&= (t' - t) - \sum_{\substack{i\in\mathcal{A}(t)}}s_i(t, t') 
\end{align}
$$

Next we show that the resource is busy during the entire interval $[t, t')$. For
contradiction assume this is not true. Let $l$ denote the earliest time in the
interval $[t, t')$ when the resource is idle. Similarly to Eq. (29) we have:

$$
\sum_{\substack{i\in\mathcal{A}(l)}}lag_i(l) = (l - t) -
  \sum_{\substack{i\in\mathcal{A}(l)}}s_i(t, l)
$$

Since the resource is not idle at any time between $t$ and $l$, it follows that
the total service time allocated to all active clients during the interval $[t,
t')$ (i.e., $\sum_{i\in\mathcal{A}(l)}s_i(t, l)$ is equal to $l - t$. Further,
from the above equation we have $\sum_{i\in\mathcal{A}(l)}lag_i(l) = 0$. But
then from Lemma 1 it follows that there is at least one eligible request at time
$l$, and therefore the resource cannot be idle at time $l$, which proves our
claim. Further, with a similar argument, it is easy to show that
$\sum_{i\in\mathcal{A}(t')}lag_i(t') = 0$ which completes the proof of this
case.

> > 第一个 $[t, t')$ 应该是 $[t, l)$ 
> {: .prompt-info} 
>
> 最终的目标是证明
> $\sum_{\substack{i\in\mathcal{A}(l)}}lag_i(l) = 0$, 从上面的等式可以看出，如果
> 等于0，也就意味着所有任务实际的运行时间之和一定等于时间的流逝. 也就意味着在
> $[t, t')$这段时间内, 资源总是繁忙的。这里作者用了反证法, 假设在 $[t, t')$ 时间
> 段中，有最早的一个时刻$l$, 该时刻是空闲的. 那么根据引理1: 如果一个client 有
> $lag >= 0$, 则一定有pending的请求。那么，我们就需要需要证明，在这个时刻，所有
> 的任务的lag 都是负值 ($lag_i < 0 ,i \in\mathcal{A}(l)$). 但是所有的lag 都是负
> 值，就意味着 $\sum_{\substack{i\in\mathcal{A}(l)}}lag_i(l) < 0$, 
>
> 这样就和假设推出来的 $\sum_{\substack{i\in\mathcal{A}(l)}}lag_i(l) = 0$ 矛盾了。
> 从而反证成功
{: .prompt-tip}

Since these are the only cases in which the lags of the active clients may
change, the proof of the lemma follows.

The following lemma gives the upper bound for the maximum delay of fulfilling a
request in a steady system. We note that this result is similar to the one
obtained by Parekh and Gallager [23] for their Generalized Processor Sharing
algorithm, i.e., in a communication network, a packet is guaranteed not to miss
its deadline by more than the time required to send a the time required to send
a packet of maximum length.

> 由于只有在这些情况下，活跃客户的滞后值才可能发生变化，因此引理的证明即告完成。
>
> 下一个引理给出了在稳定系统中满足请求的最大延迟的上界。我们注意到，这一结果与
> Parekh和Gallager [23]为其广义处理器共享（Generalized Processor Sharing）算法所
> 获得的结果类似，即在通信网络中，一个数据包保证不会错过其截止时间超过发送一个最
> 大长度数据包所需的时间。
{: .prompt-trans}

### Lemma 3

**Lemma 3** In a steady system any request of any active client k is fulfilled
no later than $d + q$, where d is the request's deadline, and q is the size of
a time quantum.

> 引理 3 在一个稳态系统中，任何活跃客户端 k 的任何请求都不迟于 $d+q$
> 得到满足，其中 d 是请求的截止时间，q 是时间片的大小。
{: .prompt-trans}

**Proof**. Let $e$ be the eligible time associated to the request (with deadline
$d$) of client $k$. Consider the partition of all the active clients at time $d$,
into two sets $B$ and $C$, where set $B$ contains all the clients that have at
least a deadline in the interval $[e, d]$ , and set $C$ contains all the other
active clients (see Figure 3). Let t be the latest time no greater than d at
which a client in $C$ receives a time quantum, if any. Further we consider two
cases whether such a t exists or not.

> 证明。设 $e$ 为与客户端 $k$ 的请求（截止时间为 $d$）相关的可用时间。考虑在时间
> $d$ 时，将所有活跃客户端划分为两个集合 $B$ 和 $C$，其中集合 $B$ 包含所有在区间
> $[e, d]$ 内至少有一个截止时间的客户端，而集合 $C$ 包含所有其他活跃客户端（见图
> 3）。设 $t$ 为不大于 $d$ 的最新时间，在该时间集合 $C$ 中的某个客户端获得时间片
> （如果存在的话）。接下来我们考虑两种情况：这样的 $t$ 是否存在。
{: .prompt-trans}

![Figure_3](pic/Figure_3.png)

**Case 1** (t exists). Here we consider two sub-cases whether $t \in [e, d)$, or
$t < e$. First assume that a client in C receives a time quantum at a time $t \in
[e, d)$. Since all the deadlines of the pending requests issued by clients in C
are larger than d, this means that at time t the pending request of client k is
already fulfilled. Consequently, in the first sub-case the request of client k
k is fulfilled before time d.

> **案例1(t存在)** 。我们考虑两种子情况：t∈[e,d) 或 t<e。首先假设某个属于集合C的
> 客户在时间 t∈[e,d) 时获得了一个时间片。由于集合C中所有待处理请求的截止时间都大
> 于 d，这意味着在时间t时，客户k的待处理请求已经被满足。因此，在第一个子情况下，
> 客户k的请求在时间d之前就被满足了
>
> > 这个证明很直观, 因为C集合中的 $V(d_C^i) > V(d_B^k)$, EEVDF调度算法会优先选择
> > $V(d)$ 小的任务, 所以在C集合中的任务被调度到时(获得时间片), 那就说明任务k
> > 肯定已经在$t$之前fulfilled, $t < d$, 所以任务k在 $d$之前 fullfilled, 在deadline
> > 之前完成任务
> {: .prompt-tip}
{: .prompt-trans}

For the second sub-case, let us $D$ denote all the active clients that have at
least one eligible request with the deadline in the interval $[t, d)$ (see
Figure 3). Further, let $D(\mathcal{T})$ denote the subset of $D$ containing the
active clients at time $\mathcal{T}$. Since a time quantum is allocated to a
client in $C$ at time $t$, it follows that no other client with an earlier
deadline is eligible at $t$. For any client j belonging to $D(t)$, let $e_j$ be
the eligible time of its pending request at time $t$. Since the deadlines of
these requests are no greater than $d$ (and therefore smaller than any deadline
of any client in $C$), it follows that all these pending requests are not
eligible at time $t$, i.e., $t < e_j$ . Notice that besides the clients in $D(t)
$, the other clients that belong to $D$ are those that eventually join the
competition after time $t$. For any client $j$ in $D$ that joins the competition
after time $t$, we take $e_j$ to be the eligible time of its first request. 

> 对于第二种子情况，令 $D$ 表示所有在区间 $[t, d)$ 内至少有一个可用请求截止时间
> 的活跃客户端（见图3）。进一步，令 $D(T)$ 表示在时刻 $T$ 处属于 $D$ 的活跃客户
> 端子集。由于在时刻 $t$ 为集合 $C$ 中的某个客户端分配了时间片，因此在 $t$ 时没
> 有其他截止时间更早的客户端是可用的。对于属于 $D(t)$ 的任意客户端 $j$，令 $e_j$
> 表示其在时刻 $t$ 时未完成请求的eligible time。由于这些请求的截止时间都不超过
> $d$（因此也小于集合 $C$ 中任何客户端的截止时间），所以这些未完成的请求在时刻
> $t$ 都不可用，即 $t < e_j$。注意，除了属于 $D(t)$ 的客户端之外，属于 $D$ 的其
> 他客户端是在时刻 $t$ 之后才加入竞争的。对于在 $t$ 之后加入竞争的任意客户端 $j$，
> 我们取其第一个请求的可用时间为 $e_j$。
{: .prompt-trans}


Next, for any client $j$ belonging to $D$, let $d_j$ denote the largest deadline
no great Next, for any client $j$ belonging to $D$, let $d_j$ denote the largest
deadline no greater than d of any of its requests (notice that the eligible time
$e_j$ and the deadline $d_j$ might not be associated to the same request). From
Eq. (10) it easy to see that after client $j$ receives $S_j(e_j, d_j)$ time
units, all its requests in the interval $[e_j, d_j)$ are fulfilled. Thus, the
service time needed to fulfill all the requests which have deadlines in the
interval $[t, d)$ is.

> 接下来，对于属于 $D$ 的任意客户端 $j$，令 $d_j$ 表示其所有请求中不超过 $d$ 的
> 最大截止时间（注意，可用时间 $e_j$ 与截止时间 $d_j$ 可能并不属于同一个请求）。
> 由公式 (10) 可以很容易看出，当客户端 $j$ 获得 $S_j(e_j, d_j)$ 个时间单位的服务
> 后，其在区间 $[e_j, d_j)$ 内的所有请求都已被满足。因此，满足所有截止时间在区间
> $[t, d)$ 内的请求所需的服务时间为：
{: .prompt-trans}

$$
\sum_{\substack{j \in D}} S_j(e_j, d_j) = 
\sum_{\substack{j\in D}} \int_{d_j} ^{e_j} \frac{w_i}{\sum_{i \in \mathcal{A}
(\mathcal{T})}w_i}d(\mathcal{T})
$$

> 通过将上述求和分解到一组互不相交的区间 $J_l = [a_l, b_l)$ $(1 \leq l \leq m)$
> 上，这些区间覆盖了 $[t, d)$，并且每个区间都不包含属于 $D$ 的任何客户端的可用时
> 间或截止时间，我们可以将公式 (30) 重写为：
{: .prompt-trans}

$$
\sum_{j \in D} S_j(e_j, d_j) = \sum_{l=1}^{m}
(\int^{b_l}_{a_l}\frac{\sum_{i \in \mathcal{D}(a_l)} w_i}
{\sum_{i \in \mathcal{A}(a_l)} w_i}d\mathcal{T}) <
\sum_{l=1}^{m}(\int^{b_l}_{a_l}d\mathcal{T}) = 
\sum_{i \in \mathcal{A}(a_l)}(b_l - a_l) = d -t
$$


The above inequality results from the fact that $D(\mathcal{T})$ is a proper
subset of $\mathcal{A}(\mathcal{T})$ at least for some subintervals $J_l$
(otherwise, if $\mathcal{A}(\mathcal{T})$ is identical to $D(\mathcal{T})$ over
the entire interval $[t, d)$, sets $C$ and $C'$ would be empty).

> 上述不等式成立，是因为在至少某些子区间 $J_l$ 上，$D(T)$ 是 $A(T)$ 的真子集。否
> 则，如果在整个区间 $[t, d)$ 上 $A(T)$ 与 $D(T)$ 完全相同，那么集合 $C$ 和 $C'$ 
> 就会为空。
>
> > 这里的关键在于$D(\mathcal{T})$ 是 $\mathcal{A}(\mathcal{T})$ 的真子集，是因为
> > 假设C集合中有成员，从而
> > $\frac{\sum_{i \in \mathcal{D}(a_l)} w_i}{\sum_{i \in \mathcal{A}(a_l)} w_i}
> > $ < 1.
> >
> > 这里也可以直观的理解, $\sum_{j \in D} S_j(e_j, d_j)$ 表示D集合中所有task的服
> > 务时间，因为在$[t, d)$这段时间内，有一些服务时间要留给集合C中的任务使用，所以
> > 其值要小于总的服务时间$d - t$
> {: .prompt-tip}
{: .prompt-trans}

Assume that at time $d + q$ the request of client $k$ (having the deadline $d$)
is not fulfilled yet. Since no client in $C$ can be served before the request of
client $k$ is fulfilled, it follows that the service time between $t + q$ and 
$d + q$ is allocated only to the clients in $D$. Consequently, during the entire
interval $[t + q, d + q)$, there are $d - t$ service time units to be
allocated to all clients in $D$. Next, recall that any client $j$ belonging to
$D$ will not receive any other time quantum after its request having deadline
$d_j$ is eventually fulfilled, as long as the request of client $k$ is not
fulfilled. This is simply because the next request of client $j$ will have a
deadline greater than $d$. But according to Eq. (31) the service time required
to fulfill al $l$ the requests having the deadlines in the interval $[t, d)$
is less than $d - t$, which means that at some point the resource is idle
during the interval $[t + q, d + q)$. But this contradicts the fact that EEVDF
is work-conserving, and therefore proves this case.

> 假设在时刻 $d+q$，客户端 $k$ 的请求（其截止时间为 $d$）尚未被满足。由于在客户
> 端 $k$ 的请求被满足之前，集合 $C$ 中的任何客户端都无法被服务，因此在区间 $[t+q,
> d+q)$ 内的服务时间只能分配给集合 $D$ 中的客户端。因此，在整个区间 $[t+q, d+q)$
> 内，共有 $d-t$ 个服务时间单位需要分配给集合 $D$ 的所有客户端。
>
> 接下来，回忆一下，属于集合 $D$ 的任意客户端 $j$，在其截止时间为 $d_j$ 的请求最
> 终被满足后，只要客户端 $k$ 的请求尚未被满足，客户端 $j$ 将不会再获得任何时间片。
> 这是因为客户端 $j$ 的下一个请求的截止时间会大于 $d$。
>
> 但是根据公式 (31)，满足所有截止时间在区间 $[t, d)$ 内的请求所需的服务时间少于
> $d-t$，这意味着在区间 $[t+q, d+q)$ 的某个时刻，资源会处于空闲状态。但这与
> EEVDF 算法是工作保守型（work-conserving）的事实相矛盾，因此证明了该情况不可能
> 发生。
{: .prompt-trans}

Case 2. (t does not exist) In this case we take $t$ to be the time when the
first client joins the competition. From here the proof is similar to the one
for the first case, with the following diference. Since set $C$ is empty, all
the time quanta between $t$ and $d$ are allocated to the clients in $D$, and
therefore, in this case, we show that in fact client $k$ does not miss the
deadline $d$.

Following we give a similar result for a steady interval. Mainly, we show that
for certain subintervals of a steady interval the same bound holds. This shows
that a system which allows clients with non-zero lag to join, leave, or to
change their weight, will eventually reach a steady state.

> 在这种情况下，我们将 $t$ 定义为第一个客户端加入竞争的时刻。从这里开始，证明过
> 程与第一种情况类似，但有如下不同。由于集合 $C$ 为空，所有在 $t$ 和 $d$ 之间的
> 时间片都分配给了集合 $D$ 中的客户端，因此，在这种情况下，我们实际上证明了客户
> 端 $k$ 不会错过截止时间 $d$。
>
> 接下来，我们针对一个稳定区间给出类似的结果。主要地，我们证明对于稳定区间的某些
> 子区间，同样的界限成立。这说明，一个允许具有非零 $lag$ 的客户端加入、离开或更
> 改其权重的系统，最终会达到稳定状态。
{: .prompt-trans}

***

**关于lemma3的思考**

这块证明我一直没想懂，思考了相当长的时间，可能跨越了整个10月，一有额外的时间就思
考该如何证明。接下来说下我的思路(请大家辩证去看)。首先我们要思考下:

其他任务会不会在各自的$[e_j, d_j)$时间区间内，多分配了额外的时间片，从而让他们在
$d_j$ 时 $lag_j < 0$。什么情况下会出现上面的情况呢? 就是在$[e_j, d_j)$时间段不能
及时意识到自己已经不是eligible了（不能及时踩刹车）又运行了一段时间.

我这边能想到的有一种，那就是在任务的 $r < quota(timeslice)$, 或者 $r$ 不能整除
$quota$ 但是这样合理么? 我们看下图: (只举 $r < timeslice$ 的例子):

![r_le_time_slice](./pic/eevdf_r_le_time_slice.svg)

可以看到client A, B 请求服务时间为 `0.75`, 但是时间片为`1`, 这样会导致在
$[e_c, d_c)$ 范围内的 $[e_a, d_a)$, $[e_b, d_b)$都拿到了额外的时间片。
这显然是不合理的。

所以我们要明确一个限制:

**每个任务的请求服务时间 r 必须是quota的整数倍**

***

接下来, 我们需要根据下面的条件分为两种情况(前文中的case 1, case2):

**条件: 对于任务 $k$ 而言，在$[e_k, d_k)$区间，是否有活跃的任务, 在该区间没有
deadline**

**case1: 对于任务 $k$, 在 $[e_k, d_k)$区间，不存在活跃任务，在该区间没有
deadline**(文中的case2)

我们通过反证法，假设在$d_k$时，任务 $k$ 仍然没有获得足够的服务时间。


见下图, 我们取第一个任务加入竞争的时间, 也就是client a 的 $e_a$ 为区间左侧。取最
后一个任务deadline, 即client k 的 $d_k$ 为区间右侧($[e_a, d_k)$).这段区间内所有
的集合称为D.

![eevdf_lemma_3_case_2](./pic/eevdf_lemma_3_case_2.svg)

因为参与竞争的只有D集合的任务参与竞争，其

$$
\sum_{j \in D} S_j(e_a, d_k) = \sum_{j \in D} s_j(e_a, d_k) = d_k - e_a
$$

我们将除k之外的其他任务在区间$[e_a, d_k)$ 的最后一个deadline, 称为 $d_j^{last}$,
而$d_j^{last}$之前的所有request集合称为 E. 任务E在 $d_j^{last}$ 之后的下一个
request的 deadline称为 $d_j^{next}$. 我们分为下面两种subcase:

**subcase1: 任务 k 在 $d_j^{last}$ 没有拿到时间片**

如果不是任务k在该时刻拿的时间片，那就是其他任务 j ($d_j > d_k$) 获得了时间片, 而
eevdf 只选择eligible，deadline最小的任务运行。说明request k 在$d_k$ 之前 是eligible
的, 已经fullfilled, 该情况和反证条件冲突，不成立。

**subcase2: 任务 k 在 $d_j^{last}$ 拿到时间片**

如果任务k 在该时刻拿到了时间片, 说明集合E中的任务都被fullfill, 而之前的限制也表
明, 其在fullfill时，不会获取到额外的时间片。但是因为E中的任务 $d_j^{next} >
d_k$, 其必须等到 任务k fullfill之后，才会运行，而根据假设，任务k没有fullfill,
所以在 $[d_j^{last}, d_k]$ 区间, 只有$k$任务在运行. 而集合E中任务的
$d_j^{last}$ 后的 request, 图中红色加粗部分。其不会运行，所以这些request的

$$
\begin{align*}
s_j(e_j^{last}, d_k) &= 0 \\
S_j(e_a, d_j^{last}) &= s_j(e_a, d_j^{last})  \\
&= s_j(e_a, d_k) - s_j(e_j^{last}, d_k) \\
&= s_j(e_a, d_k) - 0 \\
&= s_j(e_a, d_k)
\end{align*}
$$

所以:

$$
\begin{align*}
\sum_{j \in E} S_j(e_a, d_k) &= \sum_{j \in E} S_j(e_a, d_j^{last})
+ \sum_{j \in E} S_j(e_j^{next}, d_k) \\
&= \sum_{j \in E} s_j(e_a, d_k) + \sum_{j \in E} S_j(e_j^{next}, d_k) \\
&> \sum_{j \in E} s_j(e_a, d_k)
\end{align*}
$$

我们来计算$s_k(e_k, d_k)$

$$
\begin{align*}
s_k(e_k, d_k) &= \sum_{j \in D} s_j(e_a - d_k) - \sum_{j \in E} s_j(e_a - d_k) \\
&= \sum_{j \in D} S_j(e_a - d_k) - \sum_{j \in E} s_j(e_a - k_k) \\
&> \sum_{j \in D} S_j(e_a - d_k) - \sum_{j \in E} S_j(e_a - d_k)
= S_k(e_k, d_k)
\end{align*}
$$

可以看到得到任务k肯定是fullfill了，而且多拿了... 和条件冲突，所以反证成功!

**case2: 对于任务 $k$, 在 $[e_k, d_k)$区间，存在活跃任务，在该区间没有
deadline**

论文中将这类任务归为了集合C, 假设在 $t$ 时刻, 集合C中的任务获取到了时间片，
分为两种 subcase:

**subcase1: $t \in [e_k, d_k)$**

这种情况很直观，当集合中的任务C获取到时间片时, 由于此时任务k已经eligible, 而其
$d_k$ 小于集合C中任务的deadline，所以任务k肯定时eligible的

**subcase2: t < e_k**

同样采用反证法，假设任务k在 $d_k$ 处，未能fullfilled. 文中将 $[t, d_k]$区间中有
deadline 的任务集合称为D(k 也在其中), 集合D和集合C构成集合A. 而将 D 集合中的在
$[e_k, d_k)$ 中的第一个 request的eligible time 计做$e_j$, 可以得出下面结论 (文中
是通过积分的方式细化证明，我们直观展示下)

$$
\begin{align*}
\sum_{\substack{j \in D}} S_j(e_j, d_k) &= \sum_{j \in A} S_j(e_j, d_k) - \sum_{j
\in C} S_j(e_j, d_k) \\
&= d_k - t  - \sum_{j \in C} S_j(e_j, d_k) \\
&< d_k - t 
\end{align*}
$$

如果集合C中的任务在t时刻获取到时间片，说明D集合中的任务在t时刻是 not eligible.
而D集合中的任务deadline小于C集合，所以D集合中的任务将会在 $e_j$ 处开始获取时间片,
而如果D集合中的任务未能fullfill, C 集合中的任务不会获取时间片, 所以任务k将在
$d_k$处获取至少一个时间片, $[e_j, d_k + q]$ 获得 $d_k + q - e_j$ 个时间片 (因为C
集合中的任务$deadline > d_k$。而根据上面的公式，在这段时间内理论获取的服务时间应
小于 $d_k + q - e_j$ , 所以说明该 cpu有空闲。这和eevdf 的`work-conserving` 冲突.
所以反证成功。

### Lemma 4

**Lemma 4** Let $I = [t_1, t_2)$ be a steady interval, and let $d_m$ be the
largest dead line among all the pending requests of the clients with negative
lags which are active at $t_1$. Then any request of any active client $k$ is
fullfilled no later than $d + q$, if $d \in [d_m, t_2)$

**Proof**. Similarly to the proof of Lemma 3, we consider the partition of all
the active clients at time $d$, into two set B and C, where set B contains all
the active clients that have at least a deadline in the interval $[e, d]$ , and
set C contains all the other clients. Similarly, we let t denote the latest time
in the interval $[t_1, d)$ when a client in C receives a time quantum, if any.
Further, we consider two cases whether such t exists or not.

**Case 1**. (t exists) The proof proceeds similarly to the one for Case 1 in
Lemma 3.

Case 2. (t does not exist) In this case we consider two sub-sets of $C$: $C^-$
containing all clients in $C$ that had negative lags at time $t_1$, and $C^+$
containing all the other clients in C. Since no client belonging to $C^-$
receives any time quantum before $d_m$ it follows that no pending request of any
client in $C^-$ is fullfiled before its deadline (recall that the deadlines of
all the other clients with negative lags at $t_1$ are $\leq d_m$) and therefore
all clients in $C^-$ will have nonnegative lags at time $d_m$. On the other hand,
since all clients in $C^+$ had nonnegative lags at time $t_1$, and since they do
not receive any time quanta between $t_1$ and $d_m$, all of them will have
positive lags at $d_m$. Ttus,we have:

$$
\sum_{i \in \mathcal{C}} lag_i(d) \geq 0
$$

On the other hand, we note that if the request of client $k$ is not fulfilled
before its deadline, then no other client belonging to $B$ will receive any
other time quantum after its last request with the deadline no greater than d is
fulfilled. But then from Eq. (3) it follows that their lags as well as the lag
of client $k$ are positive at time $d$, i.e.,

$$
\sum_{i \in mathcal{B}} lag_i(d) > 0
$$

Further, by adding Eq. (32) and (33), we obtain:

$$
\sum_{i \in mathcal{A}} lag_i(d) > 0
$$

which contradicts Lemma 2, and therefore completes the proof

*The next theorem gives tight bounds for a client's lag in a steady system.*

### Theorem 1

**Theorem 1** The lag of any active client k in a steady system is bounded as
follows,

$$
-r_{max} < lag_k(d) < max(r_{max}, q)
$$

*where $r_{max}$ represents the maximum duration of any request issued by client $k$.
Moreover, these bounds are asymptotically light.*

**Proof**. Let $e$ and $d$ be the eligible time and the deadline of a request
with duration $r$ issued by client $k$. Since $S_k$ increases monotonically with
a slope no greater than one (see Eq. (4)), from Eq. (3) it follows that the lag
of client $k$ decreases as long as it receives service time, and increases
otherwise. Further, since a request is not serviced before it is eligible, it is
easy to see that the minimum lag is achieved when the client receives the
entirely service time as soon as the request becomes eligible. In other words,
the minimum lag occurs at time $e + r$, if the request is fulfilled by that
time. Further, by using Eq (3) we have

$$
\begin{align}
lag_k(e+r) &= S_k(t_0^k, e+r) - s_k(t_0^k, e+r) \\
&= S_k(t_0^k, e) + S_k(e, e+r) - (s_k(t_0^k, e) + s_k(e, e+r)) \\
&= lag_k(e) + S_k(e, e+r) - s_k(e, e+r)
\end{align}
$$

From the definition of the eligible time (see Section 2) we have $lag_k(e) \geq 0$,
and thus from the above equation we obtain

$$
lag_k(e+r) \geq S_k(e, e+r) - s_k(e, e+r) > -s_k(e, e+r) \geq -r
$$

Since this is the lower bound for the client's lag during a request with
duration $r$, and since rmax represents the maximum duration of any request
issued by client $k$, it follows that at a any time $t$ while client $k$ is
active we have

$$
lag_k(t) \geq -r_{max}
$$

Similarly, the maximum lag in the interval $[e, d)$ is obtained when the entire
service time is allocated as late as possible. Since according to Lemma 3, the
request is fullfilled no later than $d + q$, it follows that the latest time
when client k should receive the first quantum is $d + q - r$. We consider two
cases: $r \geq q$ and $r < q$. In the first case $d + q - r \leq d$, and
therefore we obtain $S_k(e, d + q- r) < S_k (e, d) = r$.

Let $t_1$ be the time at which the request is issued. Further, from the
definition of the eligible time, and from the fact that the client is assumed
that it does not receive any time quantum during the interval $[t_1, d + q - r)$,
we have for any time t while the request is pending

$$
\begin{align}
lag_k(t) &\leq S_k(t_0^k, d+q-r) - s_k(t_0^k, d+q-r) \\
&= S_k(t_0^k, e) + S_k(e,d+q-r)-s_k(t_0^k, t_1) - s_k(t_1,d+q-r) \\
&= (S_k(t_0^k, e) - s_k(t_0^k, t_1)) + S_k(e, d+q-r) - s_k(t_1, d+q-r) \\
&= S_k(e, d+q-r) < r
\end{align}
$$

Since the slope of $S_k$ is always no greater than one, in the second case we
have $S_k(e, d + q- r) = S_k (e, d) + S_k(d, d+q-r) < r+q-r=q$, and from here
we obtain

$$
lag_k(t) \leq S_k(e,d+q-r) < q
$$

Finally, by combining Eq. (39) and (40) we obtain $lag_k(t) < max(q, r)$. Thus,
at any time $t$ while the client is active

$$
lag_k(t) < max(q, r_{max})
$$

To show that the bound $lag_k(t) > -r_{max}$ is asymptotically tight, consider
the following example. Let $w_1$, $w_2$ be the weights of two active clients,
such that $w1 \ll w2$. Next, suppose that both clients become active at time
$t_0$ and their first requests have the lengths $r_{max}$ and $$r'_{max}$$
respectively. We assume that $r_{max}$ and $$r'{_{max}}$$ are chosen such that
the virtual deadline of the first client's request is smaller than the virtual
deadline of the second client's request, i.e., $$t_0 + \frac{r_{max}}{w_1} < t_0
\frac{r'_{max}}{w_2}$$.

Then client 1 receives the entire service time before client 2, and thus from
Eq. (3) we have $lag_1(r_{max}) = S_1(t_0, t_0 + r_{max})  - r_{max}$. Next, by
using Eq. (4) we obtain $S_1(t_0, t_0 + r_{max}) = \frac{w_1}{w_1+w_2}$ , which
approaches zero when $\frac{w_1}{w_2}\rightarrow \infty$, and consequently
$lag_1(rmax)$ approaches $-r_{max}$.

To show that the bound $lag_k(t) < max(r_{max}, q)$ is asymptotically tight, we use
the same example. However, in this case we assume that the virtual deadline of
the rst request of client 1 is earlier than the virtual deadline of the rst
request of client 2, such that client 1 receives its entire service time just
prior to its deadline. Since the details of the proof are similar with the
previous case we do not show them here.

Notice that the bounds given by Theorem 1 apply independently to each client and
depend only on the length of their requests. While shorter requests oer a
better allocation accuracy, the longer ones reduce the system overhead since for
the same total service time fewer requests need to be generated. It is therefore
possible to trade between the accuracy and the system overhead, depending on the
client requirements. For example, for an intensive computation task it would be
acceptable to take the length of the request to be in the order of seconds. On
the other hand, in the case of a multimedia application we need to take the
length of a request no greater than several tens of milliseconds, due to the
delay constraints. Theorem 1 shows that EEVDF can accommodate clients with
diferent requirements, while guaranteeing tight bounds for the lag of each
client during a steady interval. The following corollary follows directly from
Theorem 1.

***

### Corollary 2

**Corollary 2** *Consider a steady system and a client k such that no request of
client k is larger than a time quantum. Then at any time t, the lag of client k
is bounded as fol lows:*

$$
-q < lag_k(t) < q
$$

Next we give a simple lemma which shows that the bounds given in Corollary 3 are
optimal, i.e., they hold for any proportional share algorithm.

**Lemma 5** Given any steady system with time quanta of size q and any
proportional share algorithm, the lag of any client is bounded by -q and q.

**Proof**. Consider n clients with equal weights that become active at time 0.
We consider two cases: (i) each client receives exactly one time quantum out of
the first n quanta, and (ii) there is a client k which receives more than a time
quanta. From Eq. (3), it is easy to see that, at time q, the lag of the client
that receives the first quantum i

$$
lag(q) = \frac{q}{n} - q
$$

Similarly, the lag of the client which receives the $n^{th}$ time quantum is (at time
$n - 1$, immediately before it receives the time quantum)

$$
lag(q(n-1)) = q - \frac{q}{n}
$$

For contradiction, assume that there is a proportional share algorithm that
achieves an upper bound smaller than q, i.e., q  $q - \epsilon$ , where
$\epsilon$ is a positive real. Then by taking $n > \frac{q}{\epsilon}$ , from
Eq. (44), it follows that $lag(q(n -  1)) > q - \epsilon$ which is not possible.
Similarly, it can be shown that no algorithm can achieve a lower bound better
than -q.

For the second case (ii), notice that since client j receives more than one time
quanta, there must be another client k that does not receive any time quanta in
the first n time units. Then it is easy to see that the lag of client j is
smaller than $-q$ after it receives the second time quantum, and the lag of
client k is larger than q after just before receiving its first time quantum,
which completes our proof.

