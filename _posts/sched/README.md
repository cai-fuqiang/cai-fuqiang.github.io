## overview

调度子系统的任务:

调度程序负责决定运行哪个程序，该程序运行多长时间。

调度系统的责任很明确, 需要在不富裕的CPU上，合理的运行所有程序。目前的cpu架构决定,
在一个core上, 同一时间只能有一个task运行, 所以调度子系统会决定当前cpu运行某个进
程，并且让其他进程等待, 在合适的时机，将cpu上的进程调出，运行下一个合适的进程，
依次循环。

![sched_resp](./pic/sched_resp.svg)

所以调度系统是建立在多任务的基础上构建, 我们可以设想下, 如果将来某一天，体系架构
从根本上变了, -- `CPU >> task number`, Linus本人可能要执行`rm -rf kernel/sched`。

### schedule system type

而这种多任务的调度系统分为两类:

1. 非抢占式
2. 抢占式

非抢占式是指在前一个任务未主动退出之前，调度子系统不会将另一个该任务踢出，运行另
一个任务。而我们日常生活中用到的OS都是抢占式(windows,linux,mac os)。这种调度系统
会在进程正在运行时，打断该程序运行，调度另一个task到运行。由于本篇文章主要介绍
Linux调度系统，所以，下文中调度均指抢占式调度。

### 质量

而衡量一个调度系统的质量，往往有两个:

* 效率
* 合理

效率是指, 调度子系统本身所占用的cpu时间尽可能的少。而合理就是要满足目前的task 运
行需求，或者说计算场景。前一个指标好理解可以定量，而后一个指标却是主观的。所以，
向linux这种通用的操作系统需要满足用户绝大部分的需求。

我们来简单举个例子:

![sched_simple_two_task_1](./pic/sched_simple_two_task_1.svg)

当前CPU上运行两个程序:

1. MP3 player: 用于听歌
2. 非常简单的死循环程序: 单纯用于费电...

MP3程序的需求是每个10ms调度其一次，调度频率越稳定，其产生的音乐越稳定. 而"费电"程序
只有一个原则, 尽量占用CPU, 让电脑的电量下降更快。

那如果, 调度器不能按照这些程序的需求执行呢?

![sched_simple_two_task_2](./pic/sched_simple_two_task_2.svg)

那将导致让人非常恼火的卡顿，一度认为是电脑城老板的原因。

而上面的两个程序也对应于两种类型的`tasks`

### 任务种类

开发者们根据这些task 运行需求大致分为两类:

* batch process: 

  大部分时间运行一些计算指令，不和外围设备交互。

* interactive process:

  这种类型的task 实际的运行时间较少，往往在执行一段时间后，会主动的调度走, 然后
  进行较长时间等待。这段时间内, task 将无需调度回来，只有当其等待的事件完成后，
  才有必要继续运行。

我们以上个章节提到的两个任务为例:

费电程序，其代码一直执行死循环。其关注的是当前机器的费电效率，也就是吞吐。而由于
调度所执行的上下文切换会带来性能损失(例如 flush tlb, cache replacement, 以及调度
器本身的cost), 所以调度策略往往是尽量降低其调度频率。

而像`MP3 player`, 其执行完"输出某个音符到设备后", 主动让出调度，然后等待 10ms，
再输出另外一个音符。其希望每隔`10ms + 1 us`，精准调度到该进程。其关注的是是调度
延迟，所以调度策略往往是增加调度点。

不幸的是，自古鱼和熊掌不可兼得。降低延迟和增加吞吐本身就是矛盾的。降低延迟往往意
味着增加调度点check，或者更加频繁的调度来满足低延迟的需求，但是这样必然会降低
整体性能，而降低吞吐。调度器需要在两者之间做平衡。

另外，我们往往不能预测某个程序的究竟是哪种类型。例如一个数据库程序，其可能会执行
某个排序算法大量消耗cpu，也可能在执行writeback 触发大量IO ... 这时，需要调度系统
更采用更"合理"的调度策略。


## 参考链接
1. `<<Linux 内核调度与实现>>`
2. [The Rotating Staircase Deadline Scheduler](https://lwn.net/Articles/224865/)
3. [O(1) scheduler for 2.4.19-rc1](https://lwn.net/Articles/4079/)
4. [Ingo Molnar and Con Kolivas 2.6 scheduler patches](https://lore.kernel.org/all/1059211833.576.13.camel@teapot.felipe-alfaro.com/)
5. [RSDL completely fair starvation free interactive cpu scheduler](https://lwn.net/Articles/224654/)
6. [RSDM patch](https://lore.kernel.org/all/?q=RSDL-mm)
7. [郭健： Linux进程调度技术的前世今生之“今生”](https://mp.weixin.qq.com/mp/wappoc_appmsgcaptcha?poc_token=HCYNsWijDcK9zI9m_1BHFWnlNNZqZpU172Od085y&target_url=https%3A%2F%2Fmp.weixin.qq.com%2Fs%3F__biz%3DMzg2OTc0ODAzMw%3D%3D%26mid%3D2247501940%26idx%3D1%26sn%3D5e70031a7a0222794ce6c6958a2408d0%26source%3D41#wechat_redirect)
8. [O(1)调度器：Linux2.6版本的核心算法](https://blog.csdn.net/m0_50662680/article/details/129101153)
