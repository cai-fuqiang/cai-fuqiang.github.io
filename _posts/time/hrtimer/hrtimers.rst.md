<!-- ======================================================-->
hrtimers - subsystem for high-resolution kernel timers
------------------------------------------------------
<!-- ======================================================-->

This patch introduces a new subsystem for high-resolution kernel timers.

> 此补丁为 high-res kernel timers 引入了一个新的子系统。

One might ask the question: we already have a timer subsystem
(kernel/timers.c), why do we need two timer subsystems? After a lot of
back and forth trying to integrate high-resolution and high-precision
features into the existing timer framework, and after testing various
such high-resolution timer implementations in practice, we came to the
conclusion that the timer wheel code is fundamentally not suitable for
such an approach. We initially didn't believe this ('there must be a way
to solve this'), and spent a considerable effort trying to integrate
things into the timer wheel, but we failed. In hindsight, there are
several reasons why such integration is hard/impossible:

> ```
> back and forth: 反复地, 来回地
> integrate: 构成整体
> fundamentally /ˌfʌndəˈmentəli/: 从根本上
> initially /ɪˈnɪʃəli/
> considerable /kənˈsɪdərəbl/: 相当大的
> in hindsight /ɪn ˈhaɪndsaɪt/: 事后看来, 后见之明
> ```
>
> 有人可能会问：我们已经有一个计时器子系统 (kernel/timers.c)，为什么还需要
> 另一个计时器子系统？经过多次反复尝试将高分辨率和高精度功能集成到现有计时
> 器框架中，并在实践中测试了各种此类高分辨率计时器实现后，我们得出结论，
> **timer wheel** 代码从根本上不适合这种方法。我们最初并不相信这一点（“一定
> 有办法解决这个问题”），并花费了相当大的精力尝试将东西集成到timer wheel中，但
> 我们失败了。回想起来，这种集成很难/不可能的原因有几个：

- the forced handling of low-resolution and high-resolution timers in
  the same way leads to a lot of compromises, macro magic and #ifdef
  mess. The timers.c code is very "tightly coded" around jiffies and
  32-bitness assumptions, and has been honed and micro-optimized for a
  relatively narrow use case (jiffies in a relatively narrow HZ range)
  for many years - and thus even small extensions to it easily break
  the wheel concept, leading to even worse compromises. The timer wheel
  code is very good and tight code, there's zero problems with it in its
  current usage - but it is simply not suitable to be extended for
  high-res timers.

  > ```
  > compromises /ˈkɒmprəmaɪzɪz/ : 妥协
  > mess /mes/ 混乱
  > tightly /ˈtaɪtli/: 紧凑的
  > assumptions /əˈsʌmpʃ(ə)nz/: 假设
  > hone /hoʊn/: 磨练,训练
  > narrow /ˈnærəʊ/: 狭窄的
  > ```
  > 强制以相同的方式处理低分辨率和高分辨率计时器会导致很多妥协、macro magic
  > 和 #ifdef 混乱。timers.c 代码是围绕 jiffies 和 32-bitness 假设 “紧密编码”
  > 的，并且多年来一直针对相对较窄的用例（相对较窄的 HZ 范围内的 jiffies）进行
  > 打磨和微优化 - 因此即使对其进行小的扩展也很容易破坏轮子概念，导致更糟糕的
  > 妥协。timer wheel 代码是非常好且紧密的代码，在当前使用中没有任何问题 - 
  > 但它根本不适合扩展用于高分辨率计时器。

- the unpredictable [O(N)] overhead of cascading leads to delays which
  necessitate a more complex handling of high resolution timers, which
  in turn decreases robustness. Such a design still leads to rather large
  timing inaccuracies. Cascading is a fundamental property of the timer
  wheel concept, it cannot be 'designed out' without inevitably
  degrading other portions of the timers.c code in an unacceptable way.
  > ```
  > inevitably /ɪnˈevɪtəbli/: 不可避免的
  > inaccuracies /ɪnˈækjʊrəsiz/: 不准确的
  > degrading [dɪˈɡreɪdɪŋ]: 有辱人格的, 降低身份的, 贬低的
  > ```
  >
  > 级联的不可预测的 [O(N)] 开销会导致延迟，从而需要更复杂地处理高分辨率计时器，
  > 这反过来又降低了鲁棒性。这样的设计仍然会导致相当大的计时不准确性。级联是timer
  > wheel 概念的基本属性，如果不以不可接受的方式降低 timers.c 其他部分代码的质量，
  > 就无法“设计出”它。

- the implementation of the current posix-timer subsystem on top of
  the timer wheel has already introduced a quite complex handling of
  the required readjusting of absolute CLOCK_REALTIME timers at
  settimeofday or NTP time - further underlying our experience by
  example: that the timer wheel data structure is too rigid for high-res
  timers.
  > ``` 
  > readjust : 重新适应
  > rigid  [ˈrɪdʒɪd]: 刚硬的, 坚硬的, 坚固的
  > ```
  > 当前 posix-timer 子系统在timer wheel 上的实现已经引入了相当复杂的处理，
  > 需要在 settimeofday 或 NTP 时间重新调整绝对 CLOCK_REALTIME 定时器 -- 进
  > 一步通过示例说明了我们的经验：定时器轮数据结构对于高分辨率定时器来说过
  > 于严格。

- the timer wheel code is most optimal for use cases which can be
  identified as "timeouts". Such timeouts are usually set up to cover
  error conditions in various I/O paths, such as networking and block
  I/O. The vast majority of those timers never expire and are rarely
  recascaded because the expected correct event arrives in time so they
  can be removed from the timer wheel before any further processing of
  them becomes necessary. Thus the users of these timeouts can accept
  the granularity and precision tradeoffs of the timer wheel, and
  largely expect the timer subsystem to have near-zero overhead.
  Accurate timing for them is not a core purpose - in fact most of the
  timeout values used are ad-hoc. For them it is at most a necessary
  evil to guarantee the processing of actual timeout completions
  (because most of the timeouts are deleted before completion), which
  should thus be as cheap and unintrusive as possible.
  > ```
  > vast: 巨大的
  > granularity: 颗粒,粒度
  > precision /prɪˈsɪʒn/: 精确
  > tradeoffs : 权衡取舍
  > necessary evil: 必要之恶, 无法避免的事情
  > unintrusive : [ʌnɪnt'ruːsɪv]  非侵入性, 不干涉的
  > ```
  > 定时器轮盘代码最适合标识为“timeout”的用例。此类timeout通常设置为覆盖各种 
  > I/O 路径中的错误情况，例如网络和块 I/O。绝大多数这些定时器永不过期，并且
  > 很少重新级联，因为预期的正确事件会及时到达，因此可以在需要进一步处理它们
  > 之前将它们从定时器轮盘中移除。因此，这些超时的用户可以接受定时器轮盘的粒
  > 度和精度权衡，并且在很大程度上期望定时器子系统的开销接近于零。对他们来说，
  > 准确的计时并不是核心目的 - 事实上，使用的大多数超时值都是临时的。
  > 对他们来说，保证实际超时完成的处理最多是必要之恶（因为大多数超时在completion
  > 之前就被删除了），因此应该尽可能便宜和不具侵入性。

The primary users of precision timers are user-space applications that
utilize nanosleep, posix-timers and itimer interfaces. Also, in-kernel
users like drivers and subsystems which require precise timed events
(e.g. multimedia) can benefit from the availability of a separate
high-resolution timer subsystem as well.

> ```
> utilize  /ˈjuːtəlaɪz/: 利用, 使用
> ```
> 精确计时器的主要用户是使用 nanosleep、posix 计时器和 itimer 接口的用户空间
> 应用程序。此外，内核用户（如需要精确计时事件（例如多媒体）的驱动程序和子
> 系统）也可以从单独的高精度计时器子系统的可用性中受益。

While this subsystem does not offer high-resolution clock sources just
yet, the hrtimer subsystem can be easily extended with high-resolution
clock capabilities, and patches for that exist and are maturing quickly.
The increasing demand for realtime and multimedia applications along
with other potential users for precise timers gives another reason to
separate the "timeout" and "precise timer" subsystems.

> ```
> maturing /məˈtʃʊrɪŋ/ : 成熟, 使...成熟
> demand: 需求; 需要
> ```

> 虽然该子系统目前还没有提供高分辨率时钟源，但hrtimer子系统可以很容易地扩
> 展高分辨率时钟功能，并且其补丁已经存在并正在迅速成熟。实时和多媒体应
> 用程序以及其他潜在用户对精确计时器的需求不断增加，这为分离“超时”和“精
> 确计时器”子系统提供了另一个理由。

Another potential benefit is that such a separation allows even more
special-purpose optimization of the existing timer wheel for the low
resolution and low precision use cases - once the precision-sensitive
APIs are separated from the timer wheel and are migrated over to
hrtimers. E.g. we could decrease the frequency of the timeout subsystem
from 250 Hz to 100 HZ (or even smaller).

> 另一个潜在的好处是，一旦精度敏感的 API 从定时器轮中分离出来并迁移到 
> hrtimers，这种分离就可以为低分辨率和低精度用例对现有的定时器轮进行更
> 多特殊用途的优化。例如，我们可以将超时子系统的频率从 250 Hz 降低到 
> 100 HZ（甚至更低）。

hrtimer subsystem implementation details
----------------------------------------

the basic design considerations were:

- simplicity

- data structure not bound to jiffies or any other granularity. All the
  kernel logic works at 64-bit nanoseconds resolution - no compromises.
  > 数据结构不受 jiffies 或任何其他粒度的限制。所有内核逻辑都以 64 位纳
  > 秒分辨率运行 - 毫不妥协。

- simplification of existing, timing related kernel code

another basic requirement was the immediate enqueueing and ordering of
timers at activation time. After looking at several possible solutions
such as radix trees and hashes, we chose the red black tree as the basic
data structure. Rbtrees are available as a library in the kernel and are
used in various performance-critical areas of e.g. memory management and
file systems. The rbtree is solely used for time sorted ordering, while
a separate list is used to give the expiry code fast access to the
queued timers, without having to walk the rbtree.

> 另一个基本要求是在activation 时立即将计时器入队并排序。在研究了 radix 
> tree 和 hashes 等 几种可能的解决方案后，我们选择了红黑树作为基本数据结构。
> 红黑树在内核中以库的形式提供，并用于各种性能关键领域，例如内存管理和文件系统。
> 红黑树仅用于按时间排序，而使用单独的列表使到期代码能够快速访问排队的计时器，
> 而无需遍历红黑树。

(This separate list is also useful for later when we'll introduce
high-resolution clocks, where we need separate pending and expired
queues while keeping the time-order intact.)

> （这个单独的list对于我们稍后引入高分辨率时钟也很有用，我们需要单独的待
> 处理和过期队列，同时保持时间顺序不变。）

Time-ordered enqueueing is not purely for the purposes of
high-resolution clocks though, it also simplifies the handling of
absolute timers based on a low-resolution CLOCK_REALTIME. The existing
implementation needed to keep an extra list of all armed absolute
CLOCK_REALTIME timers along with complex locking. In case of
settimeofday and NTP, all the timers (!) had to be dequeued, the
time-changing code had to fix them up one by one, and all of them had to
be enqueued again. The time-ordered enqueueing and the storage of the
expiry time in absolute time units removes all this complex and poorly
scaling code from the posix-timer implementation - the clock can simply
be set without having to touch the rbtree. This also makes the handling
of posix-timers simpler in general.

> ```
> purely /ˈpjʊəli/: 完全的
> ```
> 然而，按时间顺序入队并非纯粹为了高分辨率时钟的目的，它还简化了基于低分辨率 
> CLOCK_REALTIME 的绝对计时器的处理。现有实现需要保留所有已启用的绝对 
> CLOCK_REALTIME 计时器的额外列表以及复杂的锁定。在 settimeofday 和 
> NTP 的情况下，所有计时器 (!) 都必须出队，时间更改代码必须逐一修复它们，
> 并且必须将它们全部重新入队。按时间顺序入队和以绝对时间单位存储到期时间从 
> posix-timer 实现中移除了所有这些复杂且扩展性较差的代码 - 只需设置时钟，
> 而无需触及 rbtree。这也使得 posix-timer 的处理总体上更简单。

The locking and per-CPU behavior of hrtimers was mostly taken from the
existing timer wheel code, as it is mature and well suited. Sharing code
was not really a win, due to the different data structures. Also, the
hrtimer functions now have clearer behavior and clearer names - such as
hrtimer_try_to_cancel() and hrtimer_cancel() [which are roughly
equivalent to timer_delete() and timer_delete_sync()] - so there's no direct
1:1 mapping between them on the algorithmic level, and thus no real
potential for code sharing either.

> hrtimers 的锁定和每个 CPU 行为主要取自现有的定时器轮盘代码，因为它已经成熟
> 且非常适合。由于数据结构不同，共享代码并不是真正的优势。此外，hrtimer 
> 函数现在具有更清晰的行为和更清晰的名称 - 例如 hrtimer_try_to_cancel() 和
> hrtimer_cancel() [大致相当于 timer_delete() 和 timer_delete_sync()] - 
> 因此在算法层面上它们之间没有直接的 1:1 映射，因此也没有真正的代码共享潜力。

Basic data types: every time value, absolute or relative, is in a
special nanosecond-resolution 64bit type: ktime_t.
(Originally, the kernel-internal representation of ktime_t values and
operations was implemented via macros and inline functions, and could be
switched between a "hybrid union" type and a plain "scalar" 64bit
nanoseconds representation (at compile time). This was abandoned in the
context of the Y2038 work.)

> ```
> the context of : 在...北京下, 考虑到...的情况, 这里的意思应该是 在...中
> ```
>
> 基本数据类型：每个时间值（绝对或相对）都采用特殊的纳秒分辨率 64 位类型：
> ktime_t。（最初，ktime_t 值和操作的内核内部表示是通过宏和内联函数实现的，
> 并且可以在“混合联合”类型和普通“标量”64 位纳秒表示之间切换（在编译时）。
> 这在 Y2038 工作中被放弃了。）

hrtimers - rounding of timer values
-----------------------------------

the hrtimer code will round timer events to lower-resolution clocks
because it has to. Otherwise it will do no artificial rounding at all.

> hrtimer代码将计时器事件四舍五入到较低分辨率的时钟，因为它必须这样做。
> 否则，它将根本不进行人工四舍五进。

one question is, what resolution value should be returned to the user by
the clock_getres() interface. This will return whatever real resolution
a given clock has - be it low-res, high-res, or artificially-low-res.

> 一个问题是，clock_getres() 接口应该返回什么分辨率值给用户。这将返回给定
> 时钟的实际分辨率 - 无论是低分辨率、高分辨率还是人为低分辨率。

hrtimers - testing and verification
-----------------------------------

We used the high-resolution clock subsystem on top of hrtimers to verify
the hrtimer implementation details in praxis, and we also ran the posix
timer tests in order to ensure specification compliance. We also ran
tests on low-resolution clocks.

> ```
> praxis: /ˈpræksɪs/ 实践
> compliance /kəmˈplaɪəns/ : 遵从; 服从
> ```
>
> 我们在 hrtimers 上使用高分辨率时钟子系统来验证 hrtimer 的实现细节，
> 并且我们还运行了 posix 计时器测试以确保符合规范。我们还对低分辨率时
> 钟进行了测试。

The hrtimer patch converts the following kernel functionality to use
hrtimers:

 - nanosleep
 - itimers
 - posix-timers

The conversion of nanosleep and posix-timers enabled the unification of
nanosleep and clock_nanosleep.

> unification /ˌjuːnɪfɪˈkeɪʃn/ 统一

The code was successfully compiled for the following platforms:

 i386, x86_64, ARM, PPC, PPC64, IA64

The code was run-tested on the following platforms:

 i386(UP/SMP), x86_64(UP/SMP), ARM, PPC

hrtimers were also integrated into the -rt tree, along with a
hrtimers-based high-resolution clock implementation, so the hrtimers
code got a healthy amount of testing and use in practice.

> hrtimers 也被集成到 -rt 树中，并带有基于 hrtimers 的高分辨率时钟实现，
> 因此 hrtimers 代码在实践中得到了大量的测试和使用。

	Thomas Gleixner, Ingo Molnar
