## paper

```
对于延迟应用大多数调度器要么无法满足延迟要求，要么专门针对复杂的实时模式，
这限制了它们在通用系统中的适用性。

本文提出了一种借用虚拟时间（BVT）技术。该调度方案能够为实时和交互式应用提
供低延迟，并根据系统策略在应用间加权共享 CPU 资源，即使在实时层面出现线程
故障也能保证性能，而且在多处理器和单处理器上都能以低开销实现。它对应用开
发者的要求极低，并且可以与预留或准入控制模块配合使用，以满足硬实时应用的需求。

```

### BVT schduler

* **virtual time**: thread execution time is monitored in terms of virtual time
* **effective virtual time**: dispatching the runnable thread with the earliest effective virtual time (EVT).

A latency-sensitive thread is allowed to warp back in virtual time to make it appear earlier
and thereby gain dispatch preference.It then effectively borrows virtual time from its future CPU
allocation and thus does not disrupt long-term CPU sharing. Hence the name, borrowed virtual
time scheduling.

> [!NOTE]
> 
> * **virtual time**: 用来管理 thread 运行时间, 控制其总的运行时间的比例
> * **effective virtual time**: 调度器用来选择哪个进程运行, 不再考虑 _earliest virtual time_,
>   而是考虑 _earliest effective virtual time_
>
> 而 _latency-sensitive thread_ 允许 warp back(回溯) _virtual time_ 来让其更早从而获得更好的
> 调度优先级. 但是它实际上是 borrow(借用) _future CPU allocation_ (贷款未来的时间片), 所以
> 这并不会破坏长期的 CPU sharing.

* $A_i$ : _actual virtual time_ (AVT).
* $E_i$ : _effective virtual time_ (EVT)
* $W_i$ : _virtual time warp_ ($warpBack_i$)

上面提到过，调度的原则是, 选择 _earliest EVT_ ($E_i$), 而  $E_i$ 的计算公式为:

$$
E_i \leftarrow  A_i - (warp ? W_i : 0)
$$

而 $warp$ 这个bool 值下面会讲怎么设置.

> [!NOTE]
>
> $E_i$ 赋值的逻辑是，首先判断 $warp$, 根据该值判断能不能 _warp_,
> * 不能: $A_i$
> * 能:   $A_i - $W_i$

而这里的关键变量有两个:
* $warp$
* $W_i$

为了更好的定义上面两个变量的值，引入了下面的常量定义:
* $MCU$ : minimum charging unit (最小计费单元), 通常等于
  clock interrupt 的频率(在Linux中我们可以简单理解为tick),

  如果thread运行了 $k * mcu - \epsilon$, 我们也会记账为 $k * MCU$,
  如果 进程切换的开销大约为 $\frac{mcu}{2}$, 我们可以变相认为, _curr_
  进程为进程切换买单。(因为进程平均运行 $(k + \frac{1}{2}) * MCU$)

* 另外，为了防止过度调度，引入了 _context switch allowance_ $C$,
  这可以理解为, 如果两个进程都拥有相同的 $virtual time$, 允许一个
  进程运行多长时间(_real time_) 然后被切换。可以理解为最小的时间片。

  $C$ 取值 通常是 $MCU$ 的整数倍。

## weighted for sharing


## 参考链接
1. [BVT paper](https://rcs.uwaterloo.ca/papers/bvt.pdf)
2. [【管中窥豹】浅谈调度器演进的思考，从 CFS 到 EEVDF 有感](https://zhuanlan.zhihu.com/p/680182553)
3. [cgroup 进程调度之 Borrowed-virtual-time (BVT) scheduling](http://0fd.org/2018/04/14/borrowed-virtual-time-bvt-scheduling/)
