## Reconciling High Server Utilization and Sub-millisecond Quality-of-Service<sup>1</sup>

> An important detail in the design of CFS is how virtual runtime
> is assigned for a task that wakes up and becomes runnable. The
> assignment of virtual runtime for waking tasks balances two
> properties:
>
> * allowing the waking task to run promptly, in case the event that
>   caused its wakeup needs to be handled urgently, and 
> * not giving an unfair share of processor time to waking tasks.
>
> ```
> promptly: 及时的
> ```

如果没有进程的睡眠和唤醒, CFS或者说步进算法将会很好的处理各个进程的应获得
的时间份额。这很适合为批处理任务调度其赢得的时间片带宽。但是, 在实际应用中
有很多的服务是event驱动。其希望当其event发生时，能够尽快的处理该event。

而CFS在这种情况下就不太好处理，任务在睡眠时，已经停止了 `vruntime` 的前进，
应该为唤醒后的进程赋值什么样的 `vruntime` 则成了一个老大难的问题。

1. [Reconciling High Server Utilization and Sub-millisecond Quality-of-Service](https://link.zhihu.com/?target=https%3A//dl.acm.org/doi/10.1145/2592798.2592821)
