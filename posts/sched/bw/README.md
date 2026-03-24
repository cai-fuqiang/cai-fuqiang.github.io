## struct

### task_group
* struct cfs_bandwidth cfs_bandwidth

### cfs_bandwidth
* ktime_t period
* u64 quota
* u64 runtime
* s64 hierarchal_quota
* u64 runtime_expires
* int idle
* int timer_active
* struct hrtimer period_timer
* struct hrtimer slack_timer
* struct list_head throttled_cfs_rq
* int nr_periods
* int nr_throttled
* u64 throttled_time

### cfs_rq

* int throttled
* int throttle_count
* u64 throttled_clock_task_time
* u64 throttled_clock
* u64 throttled_clock_task
* int runtime_enabled
* u64 runtime_expires
* s64 runtime_remaining

## main functions

### write quota, bandwidth
堆栈:
```sh
cpu_cfs_quota_write_s64
=> tg_set_cfs_quota
   => tg_set_cfs_bandwidth
      => __cfs_schedulable
```
`__cfs_schedulable`函数:
```sh
__cfs_schedulable
=> walk_tg_tree(tg_cfs_schedulable_down, tg_nop, &data);
   => walk_tg_tree_from(&root_task_group, down, up, data);
      ##  从root -> current 执行一遍down
      ## 从current -> root 执行一遍up

      => down loop call:  ret = (*down)(parent, data);
```

对于这个场景， 仅执行从`root`-> `current`执行一遍down(`tg_cfs_schedulable_down`)

但实际上tree的遍历的代码比较繁琐:
```cpp
int walk_tg_tree_from(struct task_group *from,
                 tg_visitor down, tg_visitor up, void *data)
{
    struct task_group *parent, *child;
    int ret;

    parent = from;

down:
    ret = (*down)(parent, data);
    if (ret)
        goto out;
    list_for_each_entry_rcu(child, &parent->children, siblings) {
        parent = child;
        goto down;

up:
        continue;
    }
    ret = (*up)(parent, data);
    if (ret || parent == from)
        goto out;

    child = parent;
    parent = parent->parent;
    if (parent)
        goto up;
out:
    return ret;
}
```

举个例子，假如说有下面的tree:
```
               a
              / \
             /   \
            b     c
           / \   / \
          /   \ /   \
         d    e f    g
```
执行流程大概是:

* down a , b , d
* up d
* down e
* up e ,b
* down c, f
* up f
* down g
* up g, c, a

采用深度遍历的方式，向下走到达一个节点, 该节点执行down，
而从该节点向上走，则执行up.

这样可以保证，当某个节点down时，其parent 层级都down。如果该节点
up，其child 层级均up.

好，接下来我们看下down函数。

```cpp
static int tg_cfs_schedulable_down(struct task_group *tg, void *data)
{
    struct cfs_schedulable_data *d = data;
    struct cfs_bandwidth *cfs_b = &tg->cfs_bandwidth;
    s64 quota = 0, parent_quota = -1;

    if (!tg->parent) {
        quota = RUNTIME_INF;
    } else {
        struct cfs_bandwidth *parent_b = &tg->parent->cfs_bandwidth;

        quota = normalize_cfs_quota(tg, d);
        parent_quota = parent_b->hierarchal_quota;

        /*
         * ensure max(child_quota) <= parent_quota, inherit when no
         * limit is set
         */
        if (quota == RUNTIME_INF)
            quota = parent_quota;
        else if (parent_quota != RUNTIME_INF && quota > parent_quota)
            return -EINVAL;
    }
    cfs_b->hierarchal_quota = quota;

    return 0;
}
/*
 * normalize group quota/period to be quota/max_period
 * note: units are usecs
 */
static u64 normalize_cfs_quota(struct task_group *tg,
                   struct cfs_schedulable_data *d)
{
    u64 quota, period;

    if (tg == d->tg) {
        period = d->period;
        quota = d->quota;
    } else {
        period = tg_get_cfs_period(tg);
        quota = tg_get_cfs_quota(tg);
    }

    /* note: these should typically be equivalent */
    if (quota == RUNTIME_INF || quota == -1)
        return RUNTIME_INF;

    return to_ratio(period, quota);
}
```

`normalize_cfs_quota()` 用来获取当前`task group` 的 period 和quota 
的比例.

`to_ratio`计算方式:
```sh
#define BW_SHIFT    20
return div64_u64(runtime << BW_SHIFT, period)
```

`quota << 20 / period`, 这里BW_SHIFT越高，精度越高。相当于将小数变整型。

而`tg_cfs_schedulable_down()` 主要的作用是， 获取当前 tg的份额(可以理解
为时间片比例)，和parent tg 的份额, 比较两者，让当前tg的份额始终小于parent

举几个例子:
* parent: RUNTIME_INF, current: quota_c -> current = quota_c
* parent: quota_p, current: RUNTIME_INF -> current = quota_p
* parent: quota_p, current: quota_c, quota_c < quota_p -> current = quota_c
* parent: quota_p, current: quota_c, quota_c > quota_p -> EINVAL

这里有一个异常情况，就是当current和parent都设置了quota，并且current quota设置
比parent高，直接返回异常，认为用户配置的不合理。

## 带宽管理

带宽管理很像是eevdf, 其会定义一个周期，在该周期中，如果任务分配的时间，超过了
其份额，则会做限制（出队），等到下一个份额的分发, 而这个周期性分发的动作显然交给
一个periodic timer比较合适。接下来来看下这部分代码:

### 带宽分发

timer 初始化(我们先仅关注period_timer)
```sh
init_cfs_bandwidth
=> rtimer_init(&cfs_b->period_timer, CLOCK_MONOTONIC, HRTIMER_MODE_ABS_PINNED);
## 这里想的是，搞一个随机的offset，让几乎同一时间创建的cgroup, 有不同的偏移量，
## 让时钟中断更分散
=> hrtimer_set_expires(&cfs_b->period_timer,
      get_random_u32_below(cfs_b->period));
## 暂不关注
=> hrtimer_init(&cfs_b->slack_timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL);
```
关注下timer的属性:
* HRTIMER_MODE_ABS_PINNED: 绝对时间，并且绑定到某个CPU

在`start_cfs_bandwidth()` 中启动timer:
```sh
tg_set_cfs_bandwidth
=> ret = __cfs_schedulable
=> runtime_enabled = quota != RUNTIME_INF;
=> runtime_was_enabled = cfs_b->quota != RUNTIME_INF;
=> init cfs_b->period, quota, bust
=> __refill_cfs_bandwidth_runtime()
=> if runtime_enabled
   => start_cfs_bandwidth
      => hrtimer_forward_now(&cfs_b->period_timer, cfs_b->period)
      => hrtimer_start_expires(&cfs_b->period_timer, HRTIMER_MODE_ABS_PINNED);
```
