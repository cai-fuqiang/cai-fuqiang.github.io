Hi everybody,

this series re-implements the LRU balancing between page cache and
anonymous pages to work better with fast random IO swap devices.

> ```
> work better with: 更好的与...配合
> ```
>
> 本系列重新实现了page cache和匿名页面之间的LRU平衡，以便更好地与快速
> 随机IO交换设备配合使用。

The LRU balancing code evolved under slow rotational disks with high
seek overhead, and it had to extrapolate the cost of reclaiming a list
based on in-memory reference patterns alone, which is error prone and,
in combination with the high IO cost of mistakes, risky. As a result,
the balancing code is now at a point where it mostly goes for page
cache and avoids the random IO of swapping altogether until the VM is
under significant memory pressure.

> ```
> evolve: 使发展; 使进化
> rotational /rəʊˈteɪʃənl/: 旋转的; 轮流的
> extrapolate /ɪkˈstræpəleɪt/: 外推；推断；推知
> prone: 有做...的倾向
> error prone /prəʊn/ : 容易出错
> ```
>
> LRU 平衡代码是在磁盘旋转速度慢、寻道开销大的情况下发展起来的，它必须仅根
> 据内存中的reference patterns来推断回收列表的成本，这很容易出错，再加上错
> 误的高 IO 成本，风险很大。因此，平衡代码现在主要用于page cache，并完全避
> 免随机IO交换，直到VM承受巨大的内存压力。

With the proliferation of fast random IO devices such as SSDs and
persistent memory, though, swap becomes interesting again, not just as
a last-resort overflow, but as an extension of memory that can be used
to optimize the in-memory balance between the page cache and the
anonymous workingset even during moderate load. Our current reclaim
choices don't exploit the potential of this hardware. This series sets
out to address this.

> ```
> proliferation /prəˌlɪfəˈreɪʃn/: 扩散
> ```
> 然而，随着 SSD 和持久内存等快速随机 I/O 设备的普及，交换再次变得有趣，
> 它不仅仅是作为最后的溢出手段，而且作为内存的扩展，可用于优化页面缓存
> 和匿名工作集之间的内存平衡，即使在中等负载下也是如此。

Having exact tracking of refault IO - the ultimate cost of reclaiming
the wrong pages - allows us to use an IO cost based balancing model
that is more aggressive about swapping on fast backing devices while
holding back on existing setups that still use rotational storage.

> ```
> exact /ɪɡˈzækt/: 确切的
> ultimate /ˈʌltɪmət/: 最终的，最后的；最根本的，最基础的
> aggressive /əˈɡresɪv/: 好斗的，挑衅的；积极进取的
> ```
>
> 通过精确跟踪 refault IO（回收错误页面的最终成本），我们可以使用基于
> IO 成本的平衡模型，该模型更积极地在快速备份设备上进行交换，同时抑制
> 仍然使用旋转存储的现有设置。

These patches base the LRU balancing on the rate of refaults on each
list, times the relative IO cost between swap device and filesystem
(swappiness), in order to optimize reclaim for least IO cost incurred.

> 这些补丁根据每个列表上的重新故障率乘以交换设备和文件系统 (swappiness) 
> 之间的相对 IO 成本来进行 LRU 平衡，以便优化回收以产生最少的 IO 成本。

---

The following postgres benchmark demonstrates the benefits of this new
model. The machine has 7G, the database is 5.6G with 1G for shared
buffers, and the system has a little over 1G worth of anonymous pages
from mostly idle processes and tmpfs files. The filesystem is on
spinning rust, the swap partition is on an SSD; swappiness is set to
115 to ballpark the relative IO cost between them. The test run is
preceded by 30 minutes of warmup using the same workload:

> 以下 postgres 基准测试展示了这种新模型的优势。机器有 7G，数据库有 
> 5.6G，其中 1G 用于共享缓冲区，系统有来自大部分空闲进程和 tmpfs 文件的
> 1G 多一点的匿名页面。文件系统在旋转的 rust 上，交换分区在 SSD 上；
> swappiness 设置为 115，以估计它们之间的相对 IO 成本。测试运行之前使用
> 相同的工作负载进行 30 分钟的预热：

```
transaction type: TPC-B (sort of)
scaling factor: 420
query mode: simple
number of clients: 8
number of threads: 4
duration: 3600 s

vanilla:
number of transactions actually processed: 290360
latency average: 99.187 ms
latency stddev: 261.171 ms
tps = 80.654848 (including connections establishing)
tps = 80.654878 (excluding connections establishing)

patched:
number of transactions actually processed: 377960
latency average: 76.198 ms
latency stddev: 229.411 ms
tps = 104.987704 (including connections establishing)
tps = 104.987743 (excluding connections establishing)

The patched kernel shows a 30% increase in throughput, and a 23%
decrease in average latency. Latency variance is reduced as well.

The reclaim statistics explain the difference in behavior:
```
