
## 全局变量
* rcu_call_count: 当前增在请求的rcu数量

## RCU THREAD
rcu thread 主要的作用是等待rcu请求后, 然后
在等待宽限期，然后执行object 销毁函数.

```cpp
static void *call_rcu_thread(void *opaque)
{
    struct rcu_head *node;

    rcu_register_thread();

    for (;;) {
        int tries = 0;
        //获取正在请求的rcu数量
        int n = qatomic_read(&rcu_call_count);

        /* Heuristically wait for a decent number of callbacks to pile up.
         * Fetch rcu_call_count now, we only must process elements that were
         * added before synchronize_rcu() starts.
         */
        //这里想汇集一定数量后, 在集中处理, 当然加了个时间限制
        //utime(10000) * 5
        while (n == 0 || (n < RCU_CALL_MIN_SIZE && ++tries <= 5)) {
            g_usleep(10000);
            if (n == 0) {
                //如果是0, 这里又不想轮训，那就在用event的方式,
                //等待rcu_call_ready_event, 但是reset和wait之间
                //需要再次查看下 rcu_call_count的值，避免漏掉
                qemu_event_reset(&rcu_call_ready_event);
                n = qatomic_read(&rcu_call_count);
                if (n == 0) {
#if defined(CONFIG_MALLOC_TRIM)
                    malloc_trim(4 * 1024 * 1024);
#endif
                    qemu_event_wait(&rcu_call_ready_event);
                }
            }
            //==(1)==
            n = qatomic_read(&rcu_call_count);
        }
        //1 读取到的值是n，但是在这两条指令中间可能n又涨了，
        //所以这里将n减去，而不是clear to zero
        qatomic_sub(&rcu_call_count, n);
        //关键函数，等待宽限期
        synchronize_rcu();
        qemu_mutex_lock_iothread();
        while (n > 0) {
            node = try_dequeue();
            while (!node) {
                qemu_mutex_unlock_iothread();
                qemu_event_reset(&rcu_call_ready_event);
                node = try_dequeue();
                if (!node) {
                    qemu_event_wait(&rcu_call_ready_event);
                    node = try_dequeue();
                }
                qemu_mutex_lock_iothread();
            }

            n--;
            node->func(node);
        }
        qemu_mutex_unlock_iothread();
    }
    abort();
}
```
synchronize_rcu:
```cpp
void synchronize_rcu(void)
{
    QEMU_LOCK_GUARD(&rcu_sync_lock);

    /* Write RCU-protected pointers before reading p_rcu_reader->ctr.
     * Pairs with smp_mb_placeholder() in rcu_read_lock().
     */
    smp_mb_global();

    QEMU_LOCK_GUARD(&rcu_registry_lock);
    if (!QLIST_EMPTY(&registry)) {
        /* In either case, the qatomic_mb_set below blocks stores that free
         * old RCU-protected pointers.
         */
        if (sizeof(rcu_gp_ctr) < 8) {
            /* For architectures with 32-bit longs, a two-subphases algorithm
             * ensures we do not encounter overflow bugs.
             *
             * Switch parity: 0 -> 1, 1 -> 0.
             */
            qatomic_mb_set(&rcu_gp_ctr, rcu_gp_ctr ^ RCU_GP_CTR);
            wait_for_readers();
            qatomic_mb_set(&rcu_gp_ctr, rcu_gp_ctr ^ RCU_GP_CTR);
        } else {
            /* Increment current grace period.  */
            qatomic_mb_set(&rcu_gp_ctr, rcu_gp_ctr + RCU_GP_CTR);
        }

        wait_for_readers();
    }
}
```
