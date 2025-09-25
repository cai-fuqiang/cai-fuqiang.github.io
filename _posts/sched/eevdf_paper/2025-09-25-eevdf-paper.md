---
layout: post
title:  "schedule: Directory"
author: fuqiang
date:   2025-09-15 21:40:00 +0800
categories: [schedule, paper]
tags: [sched]
math: true
---

## eevdf 公式推导

$$
\begin{align}
V(e) &= V(t^i_0) + \frac{s_i(t^i_0, t)}{w_i} \tag {7} \\
V(d) &= V(e) + \frac{r}{w_i} \tag {8} \\
\end{align}
$$

If the client uses each time the entire service time it has requested, (7) and
(8) we obtain the following reccurence which computes both the virtual eligible
time and the virtual deadline of each request:

$$
\begin{align}
ve^{(1)} &= V(t_0^i) \tag{9}\\
vd{(k)} &= ve^{(k)} + \frac{r^{(k)} }{w_i} \tag{10}\\
\end{align}
$$

因为client每次请求之前都能使用完所有的entire service, 所以

$$
\begin{align}
r &= S_i(e, d) = s_i(t_0^k, t_0^{k+1}) \tag{10.1} \\
vd^{(k)} &= ve^{(k)} + \frac{r^{(k)} }{w_i} \tag{10.2} \\
&= ve^{(k)} + \frac{s_i(t_0^k, t_0^{k+1})}{w_i} \tag{10.3} \\
&= ve^{(k+1)} \tag{11}
\end{align}
$$

## chapter 3

$$
\begin{align}
S_i(t_0, t^+) &= (t - t_0 - s_3(t_0, t)) \frac{w_i}{w_1+w_2}, i = 1, 2 \\
&=(t - t_0 - (S_3(t_0, t) - lag_3(t))) \frac{w_i}{w_1+w_2} \\
&=(t - t_0 - \frac{(t - t_0) * w_3}{w_1+w_2+w_3} + lag_3(t)) \frac{w_i}{w_1+w_2} \\
&=\frac{(t - t_0)(w_1+w_2+w_3) - (t - t_0) * w_3}{w_1+w_2+w_3} * \frac{w_i}{w_1+w_2} + w_i\frac{lag_3(t)}{w_1+w_2} \\
&= \frac{(t - t_0)(w_1+w_2)}{w_1+w_2+w_3} * \frac{w_1}{w_1+w_2} + w_i\frac{lag_3(t)}{w_1+w_2} \\
&= \frac{(t-t_0)w_1}{w_1+w_2+w_3} + w_i\frac{lag_3(t)}{w_1+w_2} \\
&= w_i(V(t) - V(t_0)) + w_i\frac{lag_3(t)}{w_1+w_2}
\end{align}
$$

因为:
$$
S_i(t_0, t^+) = w_i(V(t^+) - V(t_0))
$$


推导:
$$
\begin{align}
w_i(V(t^+) - V(t_0)) &= w_i(V(t) - V(t_0)) + w_i\frac{lag_3(t)}{w_1+w_2} \\
V(t^+) &= V(t) + \frac{lag_3(t)}{w_1+w_2}
\end{align}
$$

可以看到在此刻, $V(t)$ 发生了跳变.

由于$t^+$ 和 $t$ 非常接近, 所以

$$
\begin{align}
s_i(t_0, t) &= s_i(t_0, t^+) \\
lag_i(t^+) &= S_i(t_0, t^+) - s_i(t_0, t^+) \\
&= w_i(V(t^+)  - V(t_0)) - s_i(t_0, t) \\
&= w_i(V(t^+) - V(t_0)) - (S_i(t_0, t) - lag_i(t)) \\
&= w_i(V(t^+) - V(t_0)) - (w_i(V(t) - V(t_0)) - lag_i(t)) \\
&= w_i(V(t^+) - V(t)) + lag_i(t) \\
&= w_i\frac{lag_3(t)}{w_1+w_2} + lag_i(t)
\end{align}
$$

所以，此时 $lag_i(t)$ 也发生了跳变.

因此，当客户端3离开时，它的 $lag$ 会按比例分配给剩余的客户端，这与我们对公平性的
理解是一致的。通过对`公式(9)`进行推广，我们得出了以下虚拟时间的更新规则：当某个客
户端j在时刻t退出竞争时，虚拟时间应按如下方式更新。

$$
V(t) = V(t) + \frac{lag_j(t)}{\sum_{i \in \mathcal{A}(t^+)} w_i}
$$

> 

论文中还提到:

> Correspondingly, when a client $j$ joins the competition at time $t$, the
> virtual time is updated as follows

$$
V(t) = V(t) - \frac{lag_j(t)}{\sum_{i \in \mathcal{A}(t^+)} w_i}
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

任务加入和任务离开不同的是, 当任务 $j$ 再次到达时，任务 $j$ 会自带一个 $lag_j(t)
$,这里的 $lag_j(t)$ 和 j 任务离开时, 取同样的值.

论文的原文:

> Where $\mathcal{A}(t^+)$ contains all the active clients immediately after client j joins
> the competition, and $lag_j(t)$ represents the lag with which client j joins the
> competition. Although it might not be clear at this point, by updating the
> virtual time according to Eq. (18) and (19) we ensure that the sum over the
> lags of all active clients is always zero. This can be viewed as a
> conservation property of the service time, i.e., any time a client receives
> more service time than its share, there is at least another client that
> receives less. We note that if the lag of the client that leaves or joins the
> competition is zero, then according to Eq. (18) and (19) the virtual time does
> not change.9

大概的意思是, 所有的lag相加应该为0, 所以 任务 $j$ 离开的lag和任务j加入的lag应该
是相反值. 

但是，假设任务j离开是，只有任务1，任务2，其惩罚/奖励是针对任务1，2的，但是如果任
务j加入时，有任务1，2，3，其奖励/惩罚时针对任务1，2，3。似乎任务3享受到了额外的
甜点。但是该算法并不关注谁在补偿中得到的甜头，而是关注针对当前 加入/离开 任务的
奖励/惩罚。(幸运的是，论文该章节的最后一个段落会讲到这个事情。

上面提到的是任务加入与推出，那么设想下，如果任务的权重发生了变化，那$V(t)$ 该如
何计算呢?

> We note that changing the weight of an active client is equivalent to a leave
> and a rejoin operation that take place at the same time. To be specific,
> suppose that at time $t$ the weight of client $j$ is changed from $w_j$ to
> $w'_j$ . Then this is equivalent to the following two operations: client j
> leaves the competition at time t, and rejoins it immediately (at the same time
> t) having weight $w'_j$ . By adding Eq. (18) and (19), we obtain

论文中提到，任务权重发生变化，相当于任务触发了leaves 和json操作，只不过在加入后，任务
的权重从$w_j$ 变为了$w'_j$

那么可得下面的公式:

$$
V(t) = V(t) + \frac{lag_j(t)}{\sum{_{i \in \mathcal{A}(t^+)} w_i} - w_i} - 
   \frac{lag_j(t)}{\sum{_{i \in \mathcal{A}(t^+)} w_i} - w_j + w'_j}
$$

所以，这里也可看出来, 当一个lag 为 0 的任务，在离开和加入时，权重没有变化，则
virtual time 也不会发生变化。这种情况下，virtual time的变化时连续的。(不会发生跳
变)

> As for join and leave operations, notice that the virtual time does not change
> when the weight of a client with $zero$ lag is modified. Thus, in a system in
> which any client is allowed to join, leave, or change its weight only when its
> lag is zero, the variation of the virtual time is continuous

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
> request. 如果没有eligble request，会是什么样的场景呢?
>
> $$
> ve > V(t)
> $$
>
> 结果推导出来，发一定是现$lag < 0$, 与假设矛盾，原来的定理成立。
{: .prompt-tip}

From Lemma 1 and from the fact that any zero sum has at least a nonnegative term,
we have the following corollary.

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

Case (i). Assume that client j joins the competition at time t with lag $lag_j(t)
$. Let $t^-$ denote the time immediately before, and let $t^+$ denote the time
immediately after client $j$ joins the competition, where $t^+$ and $t^-$ are
asymptotically close to t. Next, let $W(t)$ denote the total sum over the
weights of all active clients at time t, i.e., $W(t) = \sum_{i \in \mathcal{A}(t)}
w_i (t)$ and by convenience let us take $lag_j (t^-) = lag_j(t)$ . Since $t^-
\rightarrow t^+$ we have $s_i(t_0^i, t^-) = s_i(t_0^i, t^+)$. Then from Eq. (3)
we obtain

> * $t^-$ : client j 加入前的很接近的时间
> * $t^+$ : client j 加入后的很接近的时间
>
> 并且为了方便让 $lag_j (t^-) = lag_j(t)$(这相当于一个策略让 任务j, $lag_j$
>
> 另外由于 $t^-$ 和 $t^+$ 两个时间很接近， 可以让 $s_i(t_0^i, t^-) = s_i(t_0^i,
> t^+)$

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
