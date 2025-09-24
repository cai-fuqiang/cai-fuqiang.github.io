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

V(t^+) &= V(t) + lag3(t)\frac{w_i}{w_1+w_2+w_3} 

\end{align}
$$

继而可以得出上面的公式.

任务加入和任务离开不同的是, 当任务 $j$ 再次到达时，任务 $j$ 会自带一个 $lag_j(t)
$,这里的 $lag_j(t)$该怎么取值.

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
务j加入时，有任务1，2，3，其奖励/惩罚时针对任务1，2，3。这似乎不公平. 但是, 我们
需要注意的是.

> We note that changing the weight of an active client is equivalent to a leave
> and a rejoin operation that take place at the same time. To be specic,
> suppose that at time t the weight of client j is changed from wj to w0 j .
> Then this is equivalent to the following two operations: client j leaves the
> competition at time t, and rejoins it immediately (at the same time t) having
> weight w0 j . By adding Eq. (18) and (19), we obtain
