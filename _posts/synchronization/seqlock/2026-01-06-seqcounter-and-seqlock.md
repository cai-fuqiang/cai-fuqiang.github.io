---
layout: post
title:  "sequence counters and sequential locks"
author: fuqiang
date:   2026-01-07 16:35:00 +0800
categories: [os, synchronization]
tags: [os, synchronization, seqlock]
media_subpath: /_posts/synchronization/seqlock
math: true
---

## introduce

> **_Definination of sequence_**:
>
> In mathematics, a sequence is an infinite list $x_1, x_2, x_3$, ... (Sometimes
> finite lists are also called sequence) <sup>2</sup>
>
> > 大概的意思是序列是一个无限列表。而counter的含义是一个计数器。计数器的特点是
> > 计数前后的差值为1。那么 sequence counter 的特点是, $0,1,2,3 ...$  这样的一个
> >列表。
> {: .prompt-tip}
{: .prompt-ref}

sequence counters/locks 是一种 reader-writer  consistency
mechanism, 特点是 lockless readers(read-only retry loops),
不会有写饥饿。

> <sup>1</sup> 原文是
>
> ```
> Sequence counters are a reader-writer consistency mechanism with lockless
> readers (read-only retry loops), and no writer starvation.
> ```
> {: .prompt-ref}
>
> 关于`reader-writer consistency`，我自己的理解:
> > 大家可以想象下，完整性是对谁而言的? writer？
> > 
> > NONONO, 对于写者而言，本身没有什么一致性可言，其只负责将数据写入, 不负责
> > 观测该object完整性. 而对于读者而言肯定需要确保观测到完整的数据。
> {: .prompt-tip}
>
> 所以, 这个机制有点类似于RCU。但和RCU 达成的效果却截然相反，rcu为 lockess
> writers, no read starvation
{: .prompt-info}

该方法适合读多写少的场景, 读者愿意为读取到一致性的信息在信息发生变化时重试。

## 实现方法

`sequence counters` 实现起来很简单:
* 读者端临界区开始处读取到偶数的序列数，并且在临界区结束处读取到相同的序列数则
  可以认为数据是一致的。否则，需要发起重试。
* 写者端, 在临界区开始处将序列号变更为奇数，并在临界区结束时将序列号变更为偶数。

内核中的同步机制，在一侧出现类似于自旋阻塞时，要很小心处理这部分。防止死锁。
这种情况一般发生在其互斥部分被强行中断，切换上下文执行到该阻塞部分。发生上下文
切换的上下文有:

* bottom half
* interrupt
* NMI
* preempt-schedule

而 `sequence counters`场景阻塞部分为reader，和reader互斥部分为writer。所以，
**reader 绝不能抢占/中断 writer的执行! 否则如前面所说，会造成死锁**

```
writer                       reader
sequence_counter++
 sequence_counter is odd
 writing...
                             broken by interrupt
                             spin wait sequence_counter 
                             become even...
can't return back..
  write done
  sequence_count++
```

另外, 如果受保护的数据是指针，则不能使用该机制，因为writer可能因为reader正在跟踪
指针而失败..

> 为什么非指针可以，但是指针不行. 我们想象一个场景
>
> 非指针
> ```
> reader                     writer
> enter read crtial section
> LOOP:
>   A = s.a;
>   B = s.b;
>                            sequence_counter++
>                            s.a=xxx;s.b=xxx;s.c=xxx;
>                            sequence_counter++
>   C = s.c;
> sequence_counter change
>   goto LOOP;
>                            DO NOTHING FOR sequence counter
> ```
>
> 指针:
> ```
> reader                     writer
> enter read crtial section
> LOOP:
>   A = s->a;
>   B = s->b;
>                            sequence_counter++
>                            tmp_s->a=xxx, tmp_s->b=xxx, tmp_s->c=xxx;
>                            old_s=s
>                            CAN do s=tmp_s, release s..
>                              NO! the reader is in crtial section..just faulted
>                            sequence_counter++
>   C = s->c;
> sequence_counter change
>   goto LOOP;
> ```
>
> 可以看到只要用到了指针。就需要等待读者完整，倒反天罡了这是... 另外这种情况下,
> 一般采用RCU 算法。
{: .prompt-tip}

`sequence counters` 有很多的变体:
* seqcount_t(本体)
* seqcount_LOCKNAME_t
* seqcount_latch_t
* seqlock_t

我们分别介绍下:

## sequence counter (seqcount_t)

这仅是一个原始的计数机制，无法满足多个写者同时写入. 如果有多个写者，需要调用者
自己通过外部锁串行写操作。

另外, 如果 写入序列化接口未隐式关抢占，则 **_必须在进入写临界区之前显示的关抢占_**,
另外，如果read section 可能会在中断上下文或者软中断上下文中调用。在进入write
section 之前, 也必须禁用 中断/bottom half。 

如果需要自动处理多写者和非抢占性要求，请使用`seqlock_t`(这个在内部使用自旋锁保证)

使用示例:

**initialization** :

```cpp
/* dynamic */
seqcount_t foo_seqcount;
seqcount_init(&foo_seqcount);

/* static */
static seqcount_t foo_seqcount = SEQCNT_ZERO(foo_seqcount);

/* C99 struct init */
struct {
        .seq   = SEQCNT_ZERO(foo.seq),
} foo;
```

初始化流程主要是将 `seqcount_t->sequence`初始化为0

**write path** :
```cpp
/* Serialized context with disabled preemption */

write_seqcount_begin(&foo_seqcount);

/* ... [[write-side critical section]] ... */

write_seqcount_end(&foo_seqcount);
```

* `write_seqcount_begin()` 将 `sequence counter` 变为 **odd**, 表示
      写临界区正在执行，读到的数据可能是不一致的。
* `write_seqcount_end()` 将 `sequence counter` 恢复为 **even**

**read path** :
```cpp
do {
        seq = read_seqcount_begin(&foo_seqcount);

        /* ... [[read-side critical section]] ... */

} while (read_seqcount_retry(&foo_seqcount, seq));
```
* `read_seqcount_begin()` 会获取 `sequence counter`的值，如果是奇数, 则再次重试，
  直到尝试获取到偶数。如果获取到偶数，则将 获取到的counter值返回。在这里，记录到
  `seq` 变量中
* 而在读临界区之外，调用`read_seqcount_retry()` 之外再次获取`sequence counter`的
  值 并和`seq` 变量进行对比
  + eq: return 0
  + ne: return 1

  当如果不相等时，说明在读临界区中，有writer 进入了写临界区。读临界区中发生的读
  取动作很可能获取到不一致的数据。需要重试。所以，这里`while()` 会获取
  `read_seqcount_retry()`返回值，如果是`true` 则重启循环。

前面提到多个写者之间要通过其他的互斥机制并行, 能不能封装一个新的接口，让串行多写者
的方式封装到接口中呢?

可以!

## seqlock

实现方法是在`seqlock_t`中封装一个自旋锁:
```cpp
typedef struct {
    unsigned sequence;
    spinlock_t lock;
} seqlock_t;
```

相关的接口也需要改变:

**initialization**:

```cpp
/* dynamic */
seqlock_t foo_seqlock;
seqlock_init(&foo_seqlock);

/* static */
static DEFINE_SEQLOCK(foo_seqlock);

/* C99 struct init */
struct {
        .seql   = __SEQLOCK_UNLOCKED(foo.seql)
} foo;
```

**Write path:**

```cpp
write_seqlock(&foo_seqlock);

/* ... [[write-side critical section]] ... */

write_sequnlock(&foo_seqlock);
```

<details markdown=1>
<summary>write sequence 相关接口, 增加了写操作</summary>

```cpp
static inline void write_seqlock(seqlock_t *sl)
{
    spin_lock(&sl->lock);
    ++sl->sequence;
    smp_wmb();
}

static inline void write_sequnlock(seqlock_t *sl)
{
    smp_wmb();
    sl->sequence++;
    spin_unlock(&sl->lock);
}
```
</details>

**read path**:
读取路径分为三种:
1. 普通: 不阻塞writer:
   ```cpp
   do {
           seq = read_seqbegin(&foo_seqlock);

           /* ... [[read-side critical section]] ... */

   } while (read_seqretry(&foo_seqlock, seq));
   ```

2. 摇身一变，变身spinlock
   ```cpp
   read_seqlock_excl(&foo_seqlock);

   /* ... [[read-side critical section]] ... */

   read_sequnlock_excl(&foo_seqlock);
   ```
   直接给读临界区加自旋锁:
   ```cpp
   static inline void read_seqlock_excl(seqlock_t *sl)
   {
           spin_lock(&sl->lock);
   }
   ```
3. 如果发现有写者正在运行, 使用`sequence counter`, 如果发现有写者运行. 直接用自
   旋锁, 该方式的好处在writer 运行不频繁的情况下，可以达到读写锁的效果 -- 允许
   多个写者同时运行.
   ```cpp
   /* marker; even initialization */
   int seq = 0;
   do {
           read_seqbegin_or_lock(&foo_seqlock, &seq);

           /* ... [[read-side critical section]] ... */

   } while (need_seqretry(&foo_seqlock, seq));
   done_seqretry(&foo_seqlock, seq);
   ```

   <details markdown=1>
   <summary>相关接口代码</summary>
   ```cpp
   static inline void read_seqbegin_or_lock(seqlock_t *lock, int *seq)
   {
           //如果是偶数，说明没有写者运行。那用 sequence_counter
           if (!(*seq & 1))        /* Even */
                   *seq = read_seqbegin(lock);
           //有写者运行，不再用sequence_counter 的方式重试等待，而直接用
           //spinlock
           else                    /* Odd */
                   read_seqlock_excl(lock);
   }
   static inline void done_seqretry(seqlock_t *lock, int seq)
   {
           //如果seq是奇数，按照`read_seqbegin_or_lock()`的逻辑会上自旋锁。
           //那么在这里解锁
           if (seq & 1)
                   read_sequnlock_excl(lock);
   }
   ```
   </details>

无论是sequence counter(raw) 还是seqlock。 整个算法是比较简单的，但是`sequence
counter` 在内核中，有一个很大的问题 -- **容易死锁**。因为内核有很多异步的上下文，
这些异步的上下文很可能会打断当前正在运行的写临界区，如果该临界区中会运行读临界区。
那就有死锁的风险。

而死锁问题比较难定位的是，造成死锁的两个互斥区不一定都能在死锁现场中暴露出来。例
如AA死锁。第一次加锁的现场很可能已经被覆盖掉。所以内核在很多锁中使用了`lockdep`

那能不能也使用`lockdep`来帮助定位 sequence counter/lock 的死锁现场呢?

可以!

## sequence counter with lockdep

前面提到, 如果在writer 临界区中进行上下文切换，而目标上下文中运行reader则可能造成
死锁。那么, 我们需要在reader和writer相关的api中lockdep以检测死锁.

```cpp
//writer
static inline void do_write_seqcount_begin_nested(seqcount_t *s, int subclass)
{
        seqcount_acquire(&s->dep_map, subclass, 0, _RET_IP_);
        do_raw_write_seqcount_begin(s);
}

//reader
#define read_seqcount_begin(s)                                          \
({                                                                      \
        seqcount_lockdep_reader_access(seqprop_const_ptr(s));           \
        raw_read_seqcount_begin(s);                                     \
})
static inline void seqcount_lockdep_reader_access(const seqcount_t *s)
{
        seqcount_t *l = (seqcount_t *)s;
        unsigned long flags;

        local_irq_save(flags);
        seqcount_acquire_read(&l->dep_map, 0, 0, _RET_IP_);
        seqcount_release(&l->dep_map, _RET_IP_);
        local_irq_restore(flags);
}
```

> ***TODO***
>
> 如果写者执行`seqcount_acquire()` 切换到读者执行`seqcount_acquire_read()`则触发
> 死锁检测.
>
> 但是多个读者侧执行并不会造成死锁。因为其执行的是acquire_read, 并在
> `acquire_read()` 后 释放锁。
>
> ***这块还没有详细了解lockdep的接口和原理，纯瞎猜***
{: .prompt-warning}

* 虽然可以检测读者写者死锁，但是能不能检测进入写临界区的写锁一定是加锁状态呢?
* 每次手动关抢占太麻烦了, 能不能自动关抢占呢 ?

都可以!

## sequence counters with associated locks(seqcount_LOCKNAME_t)

`seqcount_LOCKNAME_t` 可以实现几个目标:
1. 检测未在调用writer相关接口前加锁的代码
2. 某些类型的锁可能会隐式关抢占, 某些锁不会, 该功能将在接口中根据锁类型自动按需
   关闭/开启抢占。(例如某些接口可能会隐式关抢占, 例如spinlock，当使用
   `seqcount_spinlock_t`时就不会自动关抢占).

我们看其是如何实现的:

1. 在编译`CONFIG_LOCKDEP || CONFIG_PREEMPT_RT` 情况下才使用该功能
   ```cpp
   #if defined(CONFIG_LOCKDEP) || defined(CONFIG_PREEMPT_RT)
   #define __SEQ_LOCK(expr)        expr
   #else
   #define __SEQ_LOCK(expr)
   #endif

   #define SEQCOUNT_LOCKNAME(lockname, locktype, preemptible, lockbase)    \
   typedef struct seqcount_##lockname {                                    \
           seqcount_t              seqcount;                               \
           __SEQ_LOCK(locktype     *lock);                                 \
   } seqcount_##lockname##_t;

   SEQCOUNT_LOCKNAME(raw_spinlock, raw_spinlock_t,  false,    raw_spin)
   SEQCOUNT_LOCKNAME(spinlock,     spinlock_t,      __SEQ_RT, spin)
   SEQCOUNT_LOCKNAME(rwlock,       rwlock_t,        __SEQ_RT, read)
   SEQCOUNT_LOCKNAME(mutex,        struct mutex,    true,     mutex)
   #undef SEQCOUNT_LOCKNAME
   ```

   前者可以理解， 无论是检测是否加write锁，还是检测是否开抢占，这都是lockdep相关
   功能。后者我们需要根据后面的代码看下.
2. 定义`seqcount_LOCKNAME_t`的各个helper, 这些helper 有哪些呢 :
   ```cpp
   #define __seqprop_case(s, lockname, prop)                               \
           seqcount_##lockname##_t: __seqprop_##lockname##_##prop
   
   #define __seqprop(s, prop) _Generic(*(s),                               \
           seqcount_t:             __seqprop_##prop,                       \
           __seqprop_case((s),     raw_spinlock,   prop),                  \
           __seqprop_case((s),     spinlock,       prop),                  \
           __seqprop_case((s),     rwlock,         prop),                  \
           __seqprop_case((s),     mutex,          prop))
   
   #define seqprop_ptr(s)                  __seqprop(s, ptr)(s)
   #define seqprop_const_ptr(s)            __seqprop(s, const_ptr)(s)
   #define seqprop_sequence(s)             __seqprop(s, sequence)(s)
   #define seqprop_preemptible(s)          __seqprop(s, preemptible)(s)
   #define seqprop_assert(s)               __seqprop(s, assert)(s)
   ```
   ***seqprop_xxx***:
   * **seqprop_(const_)ptr**: 返回`seqcount_t`的地址
   * **seqprop_sequence**: 返回`seqcount_t->sequence`的值
   * **seqprop_preemptible**: 表示该锁的可抢占性(会不会隐式关抢占), 如果可抢占的
       话, 则在写接口中自动将抢占关闭。
     + 可抢占 -- 不会隐式关抢占: return true
     + 不可抢占 -- 会隐式关抢占: return false

     具体情况:
     + 不编译`CONFIG_PREEMPT_RT`的情况下，根据各个锁类型来看:
       + raw_spinlock: false
       + spinlock_t: true
       + rwlock_t: true
       + mutex: true
     + 编译`CONFIG_PREEMPT_RT`情况下，所有锁都返回false (因为`CONFIG_PREEMPT_RT`
       不允许关抢占)
   * **seqprop_assert**: 判断是否持有了锁

<details markdown=1>
<summary> helper 展开 </summary>

作者用`_Generic` 语法对各个锁类型的进行了抽象

```cpp
#define __seqprop_case(s, lockname, prop)                               \
        seqcount_##lockname##_t: __seqprop_##lockname##_##prop

#define __seqprop(s, prop) _Generic(*(s),                               \
        seqcount_t:             __seqprop_##prop,                       \
        __seqprop_case((s),     raw_spinlock,   prop),                  \
        __seqprop_case((s),     spinlock,       prop),                  \
        __seqprop_case((s),     rwlock,         prop),                  \
        __seqprop_case((s),     mutex,          prop))
```

`_Generic` 的用法 :

<details markdown=1>
<summary><code>_Generic</code> 展开</summary>

```sh
_Generic(
 表达式,
 类型1: 结果1,
 类型2: 结果2,
 ...

 类型n: 结果n,
 default: 默认结果
)
```

举例:
```cpp
#include <stdio.h>

#define type_check(x) _Generic((x), \
    int: "int", \
    float: "float", \
    double: "double", \
    default: "other")

int main() {
    int i = 0;
    double d = 3.0;
    printf("%s\n", type_check(i)); // 输出 int
    printf("%s\n", type_check(d)); // 输出 double
    printf("%s\n", type_check("hello")); // 输出 other
    return 0;
}
```
</details>

综上来看, `_Generic` 根据`*(s)`的类型，走不同的分支:
```
__seqprop_##lockname##_##prop
```
在看`__seqprop_##lockname##_##prop()`具体展开实现之前我先来看在原有接口上的改动
</details>

**write**:

```cpp
#define write_seqcount_begin(s)                                         \
do {                                                                    \
        //判断是否持有写锁                                              \
        seqprop_assert(s);                                              \
                                                                        \
        //如果目前是可抢占的(锁没有关抢占并且可以关抢占)                \
        if (seqprop_preemptible(s))                                     \
                preempt_disable();                                      \
                                                                        \
        do_write_seqcount_begin(seqprop_ptr(s));                        \
} while (0)
```

所以writer这边做了两个优化:
* 判断了是否持有锁（没有持有锁通过lockdep报告)
* 如果锁没有关抢占，在这里自动关抢占。无需在外部手动关抢占

**reader** 这边主要是对`CONFIG_PREEMPT_RT`的优化。首先说下为什么要做这个优化:

`CONFIG_PREEMPT_RT` 实时性要求会更改一些锁的行为, 例如将spinlock自旋抢锁，
改为了睡眠锁, 这样在 高优先级任务就可以强 spinlock, 而`sequence counter`
要求写者不能关抢占的这个要求不能在`CONFIG_PREEMPT_RT`中执行，所以
`seqprop_preemptible()` 会在该配置下，始终返回false. 而例如`spinlock`也
不会在`spin_lock()` 接口中关抢占。

而假设在`writer`临界区中关闭抢占, 走到reader临界区，按照`sequence counter`
的逻辑其会类似自旋，我们应该要避免掉自旋。让其调度走，回到writer。于是:

```cpp
static __always_inline unsigned                                         \
__seqprop_##lockname##_sequence(const seqcount_##lockname##_t *s)       \
{                                                                       \
        unsigned seq = smp_load_acquire(&s->seqcount.sequence);         \
                                                                        \
        //==(1)==
        if (!IS_ENABLED(CONFIG_PREEMPT_RT))                             \
                return seq;                                             \
                                                                        \
        //==(2)==
        if (preemptible && unlikely(seq & 1)) {                         \
                //==(3)==
                __SEQ_LOCK(lockbase##_lock(s->lock));                   \
                __SEQ_LOCK(lockbase##_unlock(s->lock));                 \
                                                                        \
                /*                                                      \
                 * Re-read the sequence counter since the (possibly     \
                 * preempted) writer made progress.                     \
                 */                                                     \
                seq = smp_load_acquire(&s->seqcount.sequence);          \
        }                                                               \
                                                                        \
        return seq;                                                     \
} 
```
1. 如果没有`CONFIG_PREEMPT_RT`, 还是按照原来的逻辑走，得到值直接返回。
2. 如果锁本身支持抢占, 并且此时正在写临界区。按照之前的逻辑得自旋等待
   写临界区退出（seq 变偶), 但是此时锁是可抢占的。不如让其抢占了。牺牲延迟
   带来更好的实时性。（最终要的避免死锁)

   如果不能抢占呢? 例如 `raw_spinlock` (只有这一个), 那不好意思，<kbd>死锁把你
   </kbd>
3. 直接调用睡眠锁（可抢占锁). 让其随眠。唤醒后（大概率是writer临界区结束，唤醒)
   再重新获取 `sequence` 的值

***

能不能在NMI中执行reader(NMI无法屏蔽)?

可以!!!

## TMP note
### seqcount_##lockname

```cpp
/*
 * For PREEMPT_RT, seqcount_LOCKNAME_t write side critical sections cannot
 * disable preemption. It can lead to higher latencies, and the write side
 * sections will not be able to acquire locks which become sleeping locks
 * (e.g. spinlock_t).
 *
 * To remain preemptible while avoiding a possible livelock caused by the
 * reader preempting the writer, use a different technique: let the reader
 * detect if a seqcount_LOCKNAME_t writer is in progress. If that is the
 * case, acquire then release the associated LOCKNAME writer serialization
 * lock. This will allow any possibly-preempted writer to make progress
 * until the end of its writer serialization lock critical section.
 *
 * This lock-unlock technique must be implemented for all of PREEMPT_RT
 * sleeping locks.  See Documentation/locking/locktypes.rst
 */
#if defined(CONFIG_LOCKDEP) || defined(CONFIG_PREEMPT_RT)
#define __SEQ_LOCK(expr)        expr
#else
#define __SEQ_LOCK(expr)
#endif

#define SEQCOUNT_LOCKNAME(lockname, locktype, preemptible, lockbase)    \
typedef struct seqcount_##lockname {                                    \
        seqcount_t              seqcount;                               \
        __SEQ_LOCK(locktype     *lock);                                 \
} seqcount_##lockname##_t;

SEQCOUNT_LOCKNAME(raw_spinlock, raw_spinlock_t,  false,    raw_spin)
SEQCOUNT_LOCKNAME(spinlock,     spinlock_t,      __SEQ_RT, spin)
SEQCOUNT_LOCKNAME(rwlock,       rwlock_t,        __SEQ_RT, read)
SEQCOUNT_LOCKNAME(mutex,        struct mutex,    true,     mutex)
#undef SEQCOUNT_LOCKNAME
```

### `__seqprop`

```cpp
#define __seqprop(s, prop) _Generic(*(s),                               \
        seqcount_t:             __seqprop_##prop,                       \
        __seqprop_case((s),     raw_spinlock,   prop),                  \
        __seqprop_case((s),     spinlock,       prop),                  \
        __seqprop_case((s),     rwlock,         prop),                  \
        __seqprop_case((s),     mutex,          prop))
#define __seqprop_case(s, lockname, prop)                               \
        seqcount_##lockname##_t: __seqprop_##lockname##_##prop
```

根据`s`不同的类型，调用不同的`helper`, 例如s如果为`spinlock` , prop 为 `assert`
则调用`__seqprop_spinlock_assert()`

### `__seqprop__##lockname##_##assert`
```cpp
static __always_inline void                                             \
__seqprop_##lockname##_assert(const seqcount_##lockname##_t *s)         \
{                                                                       \
        __SEQ_LOCK(lockdep_assert_held(s->lock));                       \
}

//raw sequence counter
static inline void __seqprop_assert(const seqcount_t *s)
{
         //断言这里已经关闭抢占
        lockdep_assert_preemption_disabled();
}
```

### write_seqcount_begin
```cpp
/**
 * write_seqcount_begin() - start a seqcount_t write side critical section
 * @s: Pointer to seqcount_t or any of the seqcount_LOCKNAME_t variants
 *
 * Context: sequence counter write side sections must be serialized and
 * non-preemptible. Preemption will be automatically disabled if and
 * only if the seqcount write serialization lock is associated, and
 * preemptible.  If readers can be invoked from hardirq or softirq
 * context, interrupts or bottom halves must be respectively disabled.
 *
 * sequence counter write side 必须被序列化(防止多个write)并且不能被抢占
 * 如果 write serialization lock 被关联，并且是可抢占的情况下，会自动关闭
 * 抢占。如果读操作可能在`hardirq` 或者 `softirq` 上下文中被调用，必须分别
 * 禁用中断或者 bottom half
 */
#define write_seqcount_begin(s)                                         \
do {                                                                    \
        seqprop_assert(s);                                              \
                                                                        \
        if (seqprop_preemptible(s))                                     \
                preempt_disable();                                      \
                                                                        \
        do_write_seqcount_begin(seqprop_ptr(s));                        \
} while (0)
#define seqprop_assert(s)               __seqprop(s, assert)(s)
```

## 参考链接
1. [Sequence counters and sequential locks](https://docs.kernel.org/locking/seqlock.html)
2. [Sequence wiki](https://chita.us/wikipedia/nost/index.pl?Sequence)

## 相关 commit
1. seqlock for xtime
   + bb59cfa4c9113214f91fa0ce744fd92fe2745039
   + Stephen Hemminger <shemminger@osdl.org>
   + Tue Feb 4 23:25:27 2003 -0800
2. seqcount: Add lockdep functionality to seqcount/seqlock structures
   + 1ca7d67cf5d5a2aef26a8d9afd789006fa098347
   + John Stultz <john.stultz@linaro.org>
   +  Mon Oct 7 15:51:59 2013 -0700
3. seqlock: Extend seqcount API with associated locks
   + 55f3560df975f557c48aa6afc636808f31ecb87a
   + Ahmed S. Darwish <a.darwish@linutronix.de>
   + Mon Jul 20 17:55:15 2020 +0200
   + [seqlock: Extend seqcount API with associated locks](https://lore.kernel.org/all/20200720155530.1173732-10-a.darwish@linutronix.de/)
4. seqlock: seqcount_LOCKNAME_t: Introduce PREEMPT_RT support
   + 8117ab508f9c476e0a10b9db7f4818f784cf3176
   + Author: Ahmed S. Darwish <a.darwish@linutronix.de>
   + Date:   Fri Sep 4 17:32:30 2020 +0200
