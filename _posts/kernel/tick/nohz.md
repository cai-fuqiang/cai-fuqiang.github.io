## function

### tick_nohz_stop_sched_tick

```cpp
/**
 * tick_nohz_stop_sched_tick - stop the idle tick from the idle task
 *
 * When the next event is more than a tick into the future, stop the idle tick
 * Called either from the idle loop or from irq_exit() when an idle period was
 * just interrupted by an interrupt which did not cause a reschedule.
 */
void tick_nohz_stop_sched_tick(int inidle)
```

> 在idle task中停止idle tick
>
> 当发现 next event 已经超过了一个tick，停止idle tick。
>
> 在下面场景被调用:
>
> * `idle loop`
> * `irq_exit()`中, 当一个idle period被该中断打断，并且未造成reschedule.

```cpp
/*
 * nohz_stop_sched_tick can be called several times before
 * the nohz_restart_sched_tick is called. This happens when
 * interrupts arrive which do not cause a reschedule. In the
 * first call we save the current tick time, so we can restart
 * the scheduler tick in nohz_restart_sched_tick.
 */
```

> 在`nohz_restart_sched_tick`被调用之前, nohz_stop_sched_tick 可能被调用几次
> 这常常发生在中断到达，但是还未造成reschedule时。在第一次调用时，我们保存了
> current tick time, 所以我们可以在 `nohz_restart_sched_tick`中 restart
> `scheduler tick`
