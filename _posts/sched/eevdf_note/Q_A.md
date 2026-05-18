## 问题1

来自<sup>1</sup>

Q: 基于上面的上下文，假设一个任务运行10ms睡眠 40ms，另一个任务运行6ms睡眠40ms，第一个任务是不是永远不会抢占第二个任务

A:
```
现在我有了足够的信息来做分析。让我整理一下推导过程。

不是永远不会抢占，但在稳态下确实很难抢占。 让我们做一个详细推演：

前提假设（假设权重相同，即同 nice 值）：

任务 A：运行 10ms，睡眠 40ms，周期 50ms
任务 B：运行 6ms，睡眠 40ms，周期 50ms
sysctl_sched_latency = 6ms，GENTLE_FAIR_SLEEPERS = true → thresh = 3ms
sysctl_sched_wakeup_granularity = 1ms
每个周期 vruntime 的变化分析：

每个周期中，A 实际运行 10ms，B 实际运行 6ms（同权重下 vruntime 增量 = 实际运行时间），所以：

A 每周期 vruntime 增加 10ms
B 每周期 vruntime 增加 6ms
唤醒时 place_entity 的效果：

唤醒时 vruntime = max(se->vruntime, min_vruntime - 3ms)。

关键在于 max 操作：如果任务睡眠时间不够长，se->vruntime 本身就大于 min_vruntime - 3ms，那么补偿实际不生效。

稳态分析（以两个周期为例）：

假设某时刻两者 vruntime 都从 0 开始：

B 先运行 6ms → B.vruntime = 6
A 运行 10ms → A.vruntime = 10，此时 min_vruntime = 6
两者都睡眠 40ms
B 先唤醒：place 后 vruntime = max(6, min_vruntime - 3) = max(6, 7) = 7（取决于 min_vruntime 推进情况）
A 后唤醒：place 后 vruntime = max(10, min_vruntime - 3)
核心问题：A 唤醒时能否抢占正在运行的 B？

抢占条件：curr.vruntime - waker.vruntime > wakeup_granularity(1ms)

A 唤醒时，A.vruntime ≈ 10（因为 max 保护，补偿大概率不生效），而 B 作为 curr 的 vruntime 可能是 6~12（取决于已运行多久）。

由于 A 的 vruntime 始终比 B 大约 4ms（= 10 - 6），A 唤醒时：

B.vruntime - A.vruntime ≈ -4ms（B 的 vruntime 更小）
这个值 ≤ 0，wakeup_preempt_entity 返回 -1，不抢占
结论：在稳态下，由于 A 每周期积累的 vruntime 比 B 多 4ms，A 唤醒时它的 vruntime 始终大于 B 的 vruntime。因此 A 确实无法通过唤醒抢占 B。

但 A 不是"永远得不到运行"——当 B 睡眠、A 是唯一可运行任务时，A 自然会被调度运行。只是 A 无法在 B 正在运行时通过唤醒抢占 B。反过来，B 唤醒时是有可能抢占 A 的（因为 B 的 vruntime 更小）。
```

## question 2

Q: cfs_rq->last,和cfs_rq->next的含义

A: 
```
cfs_rq->next 和 cfs_rq->last 是两个"伙伴指针"（buddy），核心目的都是提升缓存局部性。

cfs_rq->next（"下一个想运行的"）

设置场景：

唤醒抢占成功时（check_preempt_wakeup 第7157行）：任务 P 唤醒并抢占了 curr → set_next_buddy(P)，意思是"P 刚唤醒，很可能要访问刚被处理过的数据，优先让它运行"
任务睡眠退出时（dequeue_task_fair 第5770行）：任务在时间片没用完时就睡眠了 → set_next_buddy(父实体)，意思是"这个组里刚让出了 CPU 时间，让同组的其他任务优先补上"
yield_to 时（第7853行）：主动让给指定任务
语义：有人强烈希望这个任务尽快运行。

cfs_rq->last（"上一个被抢占的"）

设置场景：

唤醒抢占成功时（check_preempt_wakeup 第7178行）：curr 被 P 抢占了 → set_last_buddy(curr)，意思是"curr 正在运行时被打断，它的缓存还是热的，抢占者用完后让它尽快回来"
语义：被抢占的任务缓存还热着，希望它尽快恢复运行。

配合场景举例：

假设任务 A 正在运行，任务 B 被唤醒并抢占成功：

set_next_buddy(B) — B 是唤醒者，优先运行
resched_curr() — 标记需要重新调度
set_last_buddy(A) — A 被抢占，记住它
之后 pick_next_entity 时：

优先选 next(B)（前提是 B 的 vruntime 没有比 left 大太多）
B 运行完后，优先选 last(A)（同样有公平性兜底）
这样 B→A 的切换路径使得两者都能利用热缓存。

默认配置：

NEXT_BUDDY = false — 唤醒时不会无条件设 next（只在抢占成功时才设）
LAST_BUDDY = true — 被抢占者会被设为 last buddy
所以默认情况下，last 比 next 更常被使用，侧重于让被抢占的任务尽快恢复。
```


## 参考链接
1. [Reconciling High Server Utilization and Sub-millisecond Quality-of-Service](https://link.zhihu.com/?target=https%3A//dl.acm.org/doi/10.1145/2592798.2592821)
