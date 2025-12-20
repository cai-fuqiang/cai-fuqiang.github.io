## event

```cpp
struct QemuEvent {
#ifndef __linux__
    pthread_mutex_t lock;
    pthread_cond_t cond;
#endif
    unsigned value;
    bool initialized;
};
```
* value: 有三个值:
  + EV_FREE: 有事件pending，没有人等待
  + EV_SET:  事件已经发生
  + EV_BUSY: 有等待者

## API
### init
```cpp
void qemu_event_init(QemuEvent *ev, bool init)
{
#ifndef __linux__
    pthread_mutex_init(&ev->lock, NULL);
    pthread_cond_init(&ev->cond, NULL);
#endif
    // init == false ,置为free
    ev->value = (init ? EV_SET : EV_FREE);
    ev->initialized = true;
}

```
### reset
```cpp
void qemu_event_reset(QemuEvent *ev)
{
    unsigned value;

    assert(ev->initialized);
    value = qatomic_read(&ev->value);
    smp_mb_acquire();

    if (value == EV_SET) {
        /*
         * If there was a concurrent reset (or even reset+wait),
         * do nothing.  Otherwise change EV_SET->EV_FREE.
         */
        qatomic_or(&ev->value, EV_FREE);
    }
}
```
reset 的目的是要
### set
```cpp
void qemu_event_set(QemuEvent *ev)
{
    /* qemu_event_set has release semantics, but because it *loads*
     * ev->value we need a full memory barrier here.
     */
    assert(ev->initialized);
    smp_mb();
    //==(1)==
    if (qatomic_read(&ev->value) != EV_SET) {
        if (qatomic_xchg(&ev->value, EV_SET) == EV_BUSY) {
            /* There were waiters, wake them up.  */
            qemu_futex_wake(ev, INT_MAX);
        }
    }
}
```
有三种情况:
+ ev->value = EV_SET: 说明之前set过，没有reset，无需唤醒
+ ev->value = EV_BUSY: 说明有人等待，需要将ev->value 更改EV_SET, 然后wakeup
+ ev->value = EV_FREE: 说明无人等待，但是也需要更改为EV_SET, 不用wakeup

### wait
```cpp
void qemu_event_wait(QemuEvent *ev)
{
    unsigned value;

    assert(ev->initialized);
    value = qatomic_read(&ev->value);
    //==(1)==
    smp_mb_acquire();
    //==(2)==
    if (value != EV_SET) {
        if (value == EV_FREE) {
            /*
             * Leave the event reset and tell qemu_event_set that there
             * are waiters.  No need to retry, because there cannot be
             * a concurrent busy->free transition.  After the CAS, the
             * event will be either set or busy.
             */
            //==(3)==
            if (qatomic_cmpxchg(&ev->value, EV_FREE, EV_BUSY) == EV_SET) {
                return;
            }
        }
        //==(4)==
        qemu_futex_wait(ev, EV_BUSY);
    }
}
```
1. smp_mb_acquire: 先不管
2. 如果value 是 EV_SET, 说明 事件已经触发，或者即将触发。没有新的pending的事件，所以
   不需要等待.
3. 将其置位busy. 说明此时有人在等待，但是只允许free->busy. 如果是set，同2
4. 等待事件发生(使用futex接口，当ev->value不等于 EV_BUSY时， 进入等待)
