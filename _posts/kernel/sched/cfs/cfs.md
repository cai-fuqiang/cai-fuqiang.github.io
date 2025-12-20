## 时间片计算
```cpp
static u64 sched_slice(struct cfs_rq *cfs_rq, struct sched_entity *se)
{
    //获取当前runq上有多少running的task
    unsigned int nr_running = cfs_rq->nr_running;
    u64 slice;
    //暂不关注
    if (sched_feat(ALT_PERIOD))
        nr_running = rq_of(cfs_rq)->cfs.h_nr_running;

    //获取
    slice = __sched_period(nr_running + !se->on_rq);

    for_each_sched_entity(se) {
        struct load_weight *load;
        struct load_weight lw;

        cfs_rq = cfs_rq_of(se);
        load = &cfs_rq->load;

        if (unlikely(!se->on_rq)) {
            lw = cfs_rq->load;

            update_load_add(&lw, se->load.weight);
            load = &lw;
        }
        slice = __calc_delta(slice, se->load.weight, load);
    }

    if (sched_feat(BASE_SLICE))
        slice = max(slice, (u64)sysctl_sched_min_granularity);

    return slice;
}
/*
 * The idea is to set a period in which each task runs once.
 *
 * When there are too many tasks (sched_nr_latency) we have to stretch
 * this period because otherwise the slices get too small.
 *
 * p = (nr <= nl) ? l : l*nr/nl
 */
static u64 __sched_period(unsigned long nr_running)
{
    //如果nr_running > sched_nr_latency
    if (unlikely(nr_running > sched_nr_latency))
        //保证每个任务都能平均运行最小的时间片sysctl_sched_min_granularity
        return nr_running * sysctl_sched_min_granularity;
    else
        //如果任务没有那么多，则将时间片定为sysctl_sched_latency
        return sysctl_sched_latency;
}
```
默认值:
* sched_nr_latency: 8
* sysctl_sched_min_granularity: 0.75ms
* sysctl_sched_latency: 6ms

## 任务唤醒
相关调用流程:
```sh
ttwu_do_activate
=> int en_flags = ENQUEUE_WAKEUP | ENQUEUE_NOCLOCK;
=> activate_task(rq, p, en_flags)
   => enqueue_task
      => enqueue_task_fair
         -> if (flags & ENQUEUE_WAKEUP)
            => enqueue_entity
               => place_entity
=> ttwu_do_wakeup
   => check_preempt_curr()
      => check_preempt_wakeup
         -> if (wakeup_preempt_entity(se, pse) == 1)
            => resched_curr(rq);
```
place_entity代码:
```cpp
static void
place_entity(struct cfs_rq *cfs_rq, struct sched_entity *se, int initial)
{
    u64 vruntime = cfs_rq->min_vruntime;

    /*
     * The 'current' period is already promised to the current tasks,
     * however the extra weight of the new task will slow them down a
     * little, place the new task so that it fits in the slot that
     * stays open at the end.
     */
    //新创建任务，则将任务放到下一个时间片，避免抢占当前进程
    if (initial && sched_feat(START_DEBIT))
        vruntime += sched_vslice(cfs_rq, se);

    /* sleeps up to a single latency don't count. */
    //如果是唤醒, 则将vruntime 提前，提前至1个或半个调度周期
    if (!initial) {
        unsigned long thresh = sysctl_sched_latency;

        /*
         * Halve their sleep time's effect, to allow
         * for a gentler effect of sleepers:
         */
        if (sched_feat(GENTLE_FAIR_SLEEPERS))
            //提前半个
            thresh >>= 1;

        vruntime -= thresh;
    }

    /* ensure we never gain time by being placed backwards. */
    se->vruntime = max_vruntime(se->vruntime, vruntime);
}
```
wakeup_preempt_entity
```cpp
static unsigned long wakeup_gran(struct sched_entity *se)
{
    unsigned long gran = sysctl_sched_wakeup_granularity;

    /*
     * Since its curr running now, convert the gran from real-time
     * to virtual-time in his units.
     *
     * By using 'se' instead of 'curr' we penalize light tasks, so
     * they get preempted easier. That is, if 'se' < 'curr' then
     * the resulting gran will be larger, therefore penalizing the
     * lighter, if otoh 'se' > 'curr' then the resulting gran will
     * be smaller, again penalizing the lighter task.
     *
     * This is especially important for buddies when the leftmost
     * task is higher priority than the buddy.
     */
    /* 由于 curr 现在正在运行，将其粒度从实时转换为虚拟时间单位。
     *
     * 通过使用 'se' 而不是 'curr'，我们惩罚轻量级任务，使它们更
     * 容易被抢占。也就是说，如果 'se' < 'curr'，那么结果的粒度
     * 将会更大，从而惩罚较轻的任务；反之，如果 'se' > 'curr'，
     * 那么结果的粒度将会更小，同样惩罚较轻的任务。
     *
     * 这对于伙伴任务尤其重要，当最左边的任务的优先级高于伙伴任
     * 务时。
     *
     * 来自commit [1]
     */
    return calc_delta_fair(gran, se);
}

/*
 * Should 'se' preempt 'curr'.
 *
 *             |s1
 *        |s2
 *   |s3
 *         g
 *      |<--->|c
 *
 *  w(c, s1) = -1
 *  w(c, s2) =  0
 *  w(c, s3) =  1
 */
static int
wakeup_preempt_entity(struct sched_entity *curr, struct sched_entity *se)
{
    s64 gran, vdiff = curr->vruntime - se->vruntime;

    if (vdiff <= 0)
        return -1;

    gran = wakeup_gran(se);
    if (vdiff > gran)
        return 1;

    return 0;
}
```
该函数会计算`vdiff` -- 被抢占任务curr, 和抢占任务se的vruntime的差值,
另外计算`sysctl_sched_wakeup_granularity`的虚拟时间, 既然是虚拟时间, 则需要锚定一个
task，这里选择se.

原因是, vruntime和task->weight 成反比，weight越大，则计算出的vruntime 越小。这里
想让被抢占者权重越高，越不容易抢占，抢占者权重越高，越容易抢占。

假设我们使用curr来做vruntime计算，得出的结果正好相反: 被抢占者权重越高, 得到的
gran越小，越容易抢占。

## commit
### about 
1. sched: prefer wakers
   + commit e52fb7c097238d34f4d8e2a596f8a3f85b0c0565
   + Author: Peter Zijlstra <a.p.zijlstra@chello.nl>
   + Date:   Wed Jan 14 12:39:19 2009 +0100

### avg_overlap
2. sched: Remove avg_wakeup
   + commit b42e0c41a422a212ddea0666d5a3a0e3c35206db
   + commit e12f31d3e5d36328c7fbd0fce40a95e70b59152c
   + Author: Mike Galbraith <efault@gmx.de>
   + Date:   Thu Mar 11 17:15:38 2010 +0100

