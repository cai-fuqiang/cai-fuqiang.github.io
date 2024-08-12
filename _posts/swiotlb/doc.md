

> FROM : https://docs.kernel.org/core-api/swiotlb.html

## DMA and swiotlb

swiotlb is a memory buffer allocator used by the Linux kernel DMA layer. It is
typically used when a device doing DMA can’t directly access the target memory
buffer because of hardware limitations or other requirements. In such a case,
the DMA layer calls swiotlb to allocate a temporary memory buffer that conforms
to the limitations. The DMA is done to/from this temporary memory buffer, and
the CPU copies the data between the temporary buffer and the original target
memory buffer. This approach is generically called “bounce buffering”, and the
temporary memory buffer is called a “bounce buffer”.

> ```
> conforms: 符合;遵守
> ```
>
> swiotlb 是 Linux 内核 DMA 层使用的内存缓冲区分配器。它通常在执行 DMA 的设备由
> 于硬件限制或其他要求而无法直接访问目标内存缓冲区时使用。在这种情况下，DMA 层
> 会调用 swiotlb 来分配符合限制的临时内存缓冲区。DMA 是在此临时内存缓冲区中执行
> 的，CPU 会在临时缓冲区和原始目标内存缓冲区之间复制数据。这种方法通常称为“反弹
> 缓冲”，临时内存缓冲区称为“反弹缓冲区”。

Device drivers don’t interact directly with swiotlb. Instead, drivers inform
the DMA layer of the DMA attributes of the devices they are managing, and use
the normal DMA map, unmap, and sync APIs when programming a device to do DMA.
These APIs use the device DMA attributes and kernel-wide settings to determine
if bounce buffering is necessary. If so, the DMA layer manages the allocation,
freeing, and sync’ing of bounce buffers. Since the DMA attributes are per
device, some devices in a system may use bounce buffering while others do not.

> 设备驱动程序不直接与 swiotlb 交互。相反，驱动程序会通知 DMA 层它们所管理的设备
> 的 DMA 属性，并在对设备进行 DMA 编程时使用常规的 DMA 映射、取消映射和同步 API。
> 这些 API 使用设备 DMA 属性和内核范围的设置来确定是否需要反弹缓冲。如果需要，
> DMA 层会管理反弹缓冲区的分配、释放和同步。由于 DMA 属性是针对每个设备的，因此系
> 统中的某些设备可能使用反弹缓冲，而其他设备则不使用。

Because the CPU copies data between the bounce buffer and the original target
memory buffer, doing bounce buffering is slower than doing DMA directly to the
original memory buffer, and it consumes more CPU resources. So it is used only
when necessary for providing DMA functionality. 

> 由于 CPU 在反弹缓冲区和原始目标内存缓冲区之间复制数据，因此执行反弹缓冲比直接
> 对原始内存缓冲区执行 DMA 更慢，并且会消耗更多 CPU 资源。因此，仅在需要提供 
> DMA 功能时才使用它。

## Usage Scenarios

swiotlb was originally created to handle DMA for devices with addressing
limitations. As physical memory sizes grew beyond 4 GiB, some devices could
only provide 32-bit DMA addresses. By allocating bounce buffer memory below the
4 GiB line, these devices with addressing limitations could still work and do
DMA.

> swiotlb 最初是为处理具有寻址限制的设备的 DMA 而创建的。随着物理内存大小超过 
> 4 GiB，某些设备只能提供 32 位 DMA 地址。通过分配低于 4 GiB 的反弹缓冲区内存，
> 这些具有寻址限制的设备仍可工作并执行 DMA。

More recently, Confidential Computing (CoCo) VMs have the guest VM’s memory
encrypted by default, and the memory is not accessible by the host hypervisor
and VMM. For the host to do I/O on behalf of the guest, the I/O must be
directed to guest memory that is unencrypted. CoCo VMs set a kernel-wide option
to force all DMA I/O to use bounce buffers, and the bounce buffer memory is set
up as unencrypted. The host does DMA I/O to/from the bounce buffer memory, and
the Linux kernel DMA layer does “sync” operations to cause the CPU to copy the
data to/from the original target memory buffer. The CPU copying bridges between
the unencrypted and the encrypted memory. This use of bounce buffers allows
device drivers to “just work” in a CoCo VM, with no modifications needed to
handle the memory encryption complexity.

> ```
> confidential [ˌkɒnfɪˈdenʃl] : 机密
> behalf: 代表; 利益
> ```
>
> 最近，机密计算 (CoCo) VM 默认加密guest VM 的内存，host hypervisor 和 VMM 无法访问该内存。
> 为了让主机代表guest执行 I/O，必须将 I/O 定向到未加密的guest内存。CoCo VM 设置内核范
> 围的选项以强制所有 DMA I/O 使用反弹缓冲区，并且反弹缓冲区内存设置为未加密。主机对
> 反弹缓冲区内存执行 DMA I/O，Linux 内核 DMA 层执行“同步”操作以使 CPU 将数据复制到
> 原始目标内存缓冲区或从原始目标内存缓冲区复制数据。CPU 复制在未加密内存和加密内存之
> 间架起了桥梁。使用反弹缓冲区允许设备驱动程序在 CoCo VM 中“正常工作”，无需进行任何
> 修改即可处理内存加密复杂性。

Other edge case scenarios arise for bounce buffers. For example, when IOMMU
mappings are set up for a DMA operation to/from a device that is considered
“untrusted”, the device should be given access only to the memory containing
the data being transferred. But if that memory occupies only part of an IOMMU
granule, other parts of the granule may contain unrelated kernel data. Since
IOMMU access control is per-granule, the untrusted device can gain access to
the unrelated kernel data. This problem is solved by bounce buffering the DMA
operation and ensuring that unused portions of the bounce buffers do not
contain any unrelated kernel data. 

> ```
> scenarios [sɪˈnɑːrɪəʊz] : 场景
> arise: 出现
> edge case : 极端情况
> transfer: 转移, 使转动
> granule /ˈɡrænjuːl/: 颗粒
> ```
>
> 对于反弹缓冲区，还会出现其他极端情况。例如，当为往返于被视为“不受信任”的设备的
> DMA 操作设置 IOMMU 映射时，应仅授予该设备对包含正在传输的数据的内存的访问权限。
> 但是，如果该内存仅占用 IOMMU granule的一部分，则该颗粒的其他部分可能包含不相关的
> 内核数据。由于 IOMMU 访问控制是针对每个颗粒的，因此不受信任的设备可以访问不相
> 关的内核数据。通过反弹缓冲 DMA 操作并确保反弹缓冲区的未使用部分不包含任何不相
> 关的内核数据，可以解决此问题。

## Core Functionality

The primary swiotlb APIs are swiotlb_tbl_map_single() and
swiotlb_tbl_unmap_single(). The “map” API allocates a bounce buffer of a
specified size in bytes and returns the physical address of the buffer. The
buffer memory is physically contiguous. The expectation is that the DMA layer
maps the physical memory address to a DMA address, and returns the DMA address
to the driver for programming into the device. If a DMA operation specifies
multiple memory buffer segments, a separate bounce buffer must be allocated for
each segment. swiotlb_tbl_map_single() always does a “sync” operation (i.e., a
CPU copy) to initialize the bounce buffer to match the contents of the original
buffer.

> ```
> contiguous /kənˈtɪɡjuəs/: 相邻的,相接的, 连续的
> ```
> 主要的 swiotlb API 是 swiotlb_tbl_map_single() 和 swiotlb_tbl_unmap_single()。 
> “map” API 分配一个指定大小（以字节为单位）的反弹缓冲区，并返回该缓冲区的物理
> 地址。缓冲区内存在物理上是连续的。预期是 DMA 层将物理内存地址映射到 DMA 地址，
> 并将 DMA 地址返回给驱动程序以编程到设备中。如果 DMA 操作指定多个内存缓冲区段，
> 则必须为每个段分配一个单独的反弹缓冲区。 swiotlb_tbl_map_single() 始终执行
> “同步”操作（即 CPU 复制）以初始化反弹缓冲区以匹配原始缓冲区的内容。

swiotlb_tbl_unmap_single() does the reverse. If the DMA operation might have
updated the bounce buffer memory and DMA_ATTR_SKIP_CPU_SYNC is not set, the
unmap does a “sync” operation to cause a CPU copy of the data from the bounce
buffer back to the original buffer. Then the bounce buffer memory is freed.

> swiotlb_tbl_unmap_single（）则相反。如果DMA操作可能已经更新了bounce buffer 
> memory 并且DMA_ATTR_SKIP_CPU_SYNC未设置，则取消映射会执行“同步”操作，使CPU
> 将数据从反弹缓冲区复制回原始缓冲区。然后释放反弹缓冲存储器。

swiotlb also provides “sync” APIs that correspond to the dma_sync_*() APIs that
a driver may use when control of a buffer transitions between the CPU and the
device. The swiotlb “sync” APIs cause a CPU copy of the data between the
original buffer and the bounce buffer. Like the dma_sync_*() APIs, the swiotlb
“sync” APIs support doing a partial sync, where only a subset of the bounce
buffer is copied to/from the original buffer. 

> ```
> correspond /ˌkɒrəˈspɒnd/ : 相一致
> ```
> swiotlb 还提供了与 dma_sync_() API 相对应的“同步”API，当缓冲区的控制权在 CPU 
> 和设备之间转换时，驱动程序可以使用这些 API。swiotlb“同步”API 会导致原始缓冲区
> 和反弹缓冲区之间的数据在 CPU 中复制。与 dma_sync_() API 一样，swiotlb“同步”
> API 支持执行部分同步，其中只有反弹缓冲区的子集会复制到原始缓冲区或从原始缓冲区
> 复制。

## Core Functionality Constraints

 >  Constraints /kənˈstreɪnts/ : 约束条件; 限制

The swiotlb map/unmap/sync APIs must operate without blocking, as they are
called by the corresponding DMA APIs which may run in contexts that cannot
block. Hence the default memory pool for swiotlb allocations must be
pre-allocated at boot time (but see Dynamic swiotlb below). Because swiotlb
allocations must be physically contiguous, the entire default memory pool is
allocated as a single contiguous block.

> swiotlb 映射/取消映射/同步 API 必须以无阻塞方式运行，因为它们由相应的 DMA 
> API 调用，而这些 API 可能在无法阻塞的上下文中运行。因此，swiotlb 分配的默
> 认内存池必须在启动时预先分配（但请参阅下面的动态 swiotlb）。由于 swiotlb 
> 分配必须是物理连续的，因此整个默认内存池将分配为单个连续块。

The need to pre-allocate the default swiotlb pool creates a boot-time tradeoff.
The pool should be large enough to ensure that bounce buffer requests can
always be satisfied, as the non-blocking requirement means requests can’t wait
for space to become available. But a large pool potentially wastes memory, as
this pre-allocated memory is not available for other uses in the system. The
tradeoff is particularly acute in CoCo VMs that use bounce buffers for all DMA
I/O. These VMs use a heuristic to set the default pool size to ~6% of memory,
with a max of 1 GiB, which has the potential to be very wasteful of memory.
Conversely, the heuristic might produce a size that is insufficient, depending
on the I/O patterns of the workload in the VM. The dynamic swiotlb feature
described below can help, but has limitations. Better management of the swiotlb
default memory pool size remains an open issue.

> ```
> tradeoff /ˈtreɪˌdɔf/ : 权衡
> satisfied /ˈsætɪsfaɪd/ : 满意的
> potentially  /pə'tenʃəli/: 潜在的
> acute /əˈkjuːt/: 严重的
> heuristic /hjuˈrɪstɪk/ : 启发式的
> conversely /ˈkɒnvɜːsli/ : 相反
> insufficient /ˌɪnsəˈfɪʃnt/ : 不足的;不够的
> ```
>
> 需要预先分配默认的 swiotlb 池会产生启动时间权衡。池应足够大，以确保始终能够满足
> 反弹缓冲区请求，因为非阻塞要求意味着请求不能等待空间可用。但是，大型池可能会浪
> 费内存，因为此预分配内存不能用于系统中的其他用途。对于使用反弹缓冲区进行所有 
> DMA I/O 的 CoCo VM，这种权衡尤其严重。这些 VM 使用启发式方法将默认池大小设置为
> 内存的约 6%，最大值为 1 GiB，这可能会非常浪费内存。相反，启发式方法可能会产
> 生不足的大小，具体取决于 VM 中工作负载的 I/O 模式。下面描述的动态 swiotlb 功能
> 可以提供帮助，但有局限性。更好地管理 swiotlb 默认内存池大小仍然是一个悬而未决
> 的问题。

A single allocation from swiotlb is limited to IO_TLB_SIZE * IO_TLB_SEGSIZE
bytes, which is 256 KiB with current definitions. When a device’s DMA settings
are such that the device might use swiotlb, the maximum size of a DMA segment
must be limited to that 256 KiB. This value is communicated to higher-level
kernel code via dma_map_mapping_size() and swiotlb_max_mapping_size(). If the
higher-level code fails to account for this limit, it may make requests that
are too large for swiotlb, and get a “swiotlb full” error.

> swiotlb的单个分配仅限于IO_TLB_SIZE*IO_TLB_SEGSIZE字节，根据当前定义为256 KiB。
> 当设备的DMA设置使得设备可能使用swiotlb时，DMA段的最大大小必须限制在256KiB。
> 该值通过dma_mapping_size() 和swiotlb_max_mapping_size()。如果高级代码未能考虑
> 到这一限制，它可能会发出对swiotlb来说太大的请求，并得到“swiotlb full”错误。

A key device DMA setting is “min_align_mask”, which is a power of 2 minus 1 so
that some number of low order bits are set, or it may be zero. swiotlb
allocations ensure these min_align_mask bits of the physical address of the
bounce buffer match the same bits in the address of the original buffer. When
min_align_mask is non-zero, it may produce an “alignment offset” in the address
of the bounce buffer that slightly reduces the maximum size of an allocation.
This potential alignment offset is reflected in the value returned by
swiotlb_max_mapping_size(), which can show up in places like
/sys/block/<device>/queue/max_sectors_kb. For example, if a device does not use
swiotlb, max_sectors_kb might be 512 KiB or larger. If a device might use
swiotlb, max_sectors_kb will be 256 KiB. When min_align_mask is non-zero,
max_sectors_kb might be even smaller, such as 252 KiB.

> ```
> minus /ˈmaɪnəs/: 减
> slightly: 轻微的
> ```
> 一个关键的device DMA 设置是“min_align_mask”，它是 2 的幂减 1，因此设置了一
> 些低位，或者它可能为零。swiotlb 分配确保反弹缓冲区的物理地址的这些 
> min_align_mask 位与原始缓冲区地址中的相同位匹配。当 min_align_mask 非零时，它
> 可能会在反弹缓冲区的地址中产生“对齐偏移”，从而略微减少分配的最大大小。此潜
> 在的对齐偏移反映在 swiotlb_max_mapping_size() 返回的值中，该值可能显示在 
> /sys/block//queue/max_sectors_kb 等位置。例如，如果设备不使用 swiotlb，
> max_sectors_kb 可能为 512 KiB 或更大。如果设备可能使用 swiotlb，
> max_sectors_kb 将为 256 KiB。当 min_align_mask 非零时，max_sectors_kb 
> 可能甚至更小，例如 252 KiB。 

swiotlb_tbl_map_single() also takes an “alloc_align_mask” parameter. This
parameter specifies the allocation of bounce buffer space must start at a
physical address with the alloc_align_mask bits set to zero. But the actual
bounce buffer might start at a larger address if min_align_mask is non-zero.
Hence there may be pre-padding space that is allocated prior to the start of
the bounce buffer. Similarly, the end of the bounce buffer is rounded up to an
alloc_align_mask boundary, potentially resulting in post-padding space. Any
pre-padding or post-padding space is not initialized by swiotlb code. The
“alloc_align_mask” parameter is used by IOMMU code when mapping for untrusted
devices. It is set to the granule size - 1 so that the bounce buffer is
allocated entirely from granules that are not used for any other purpose.

> swiotlb_tbl_map_single() 还采用 “alloc_align_mask” 参数。此参数指定反弹缓
> 冲区空间的分配必须从 alloc_align_mask 位设置为零的物理地址开始。但是，如果 
> min_align_mask 非零，则实际反弹缓冲区可能从更大的地址开始。因此，在反弹缓
> 冲区开始之前可能会分配预填充空间。同样，反弹缓冲区的末尾会四舍五入到 
> alloc_align_mask 边界，从而可能导致后填充空间。swiotlb 代码不会初始化任何
> 预填充或后填充空间。IOMMU 代码在映射不受信任的设备时使用“alloc_align_mask”
> 参数。它设置为颗粒大小 - 1，以便反弹缓冲区完全从未用于任何其他目的的颗粒中
> 分配。

## Data structures concepts

Memory used for swiotlb bounce buffers is allocated from overall system memory
as one or more “pools”. The default pool is allocated during system boot with a
default size of 64 MiB. The default pool size may be modified with the
“swiotlb=” kernel boot line parameter. The default size may also be adjusted
due to other conditions, such as running in a CoCo VM, as described above. If
CONFIG_SWIOTLB_DYNAMIC is enabled, additional pools may be allocated later in
the life of the system. Each pool must be a contiguous range of physical
memory. The default pool is allocated below the 4 GiB physical address line so
it works for devices that can only address 32-bits of physical memory (unless
architecture-specific code provides the SWIOTLB_ANY flag). In a CoCo VM, the
pool memory must be decrypted before swiotlb is used.

> ```
> overall: 总体的;全面的;综合的
> ```
> swiotlb 反弹缓冲区使用的内存是从整个系统内存中分配的，作为一个或多个“池”。
> 默认池在系统启动期间分配，默认大小为 64 MiB。可以使用“swiotlb=”内核启动行参数修
> 改默认池大小。默认大小也可能由于其他条件而调整，例如在 CoCo VM 中运行，如上所述。
> 如果启用了 CONFIG_SWIOTLB_DYNAMIC，则可能会在系统生命周期的后期分配其他池。每个
> 池必须是连续的物理内存范围。默认池分配在 4 GiB 物理地址线以下，因此它适用于只能
> 寻址 32 位物理内存的设备（除非特定于架构的代码提供 SWIOTLB_ANY 标志）。在 CoCo 
> VM 中，必须在使用 swiotlb 之前解密池内存。

Each pool is divided into “slots” of size IO_TLB_SIZE, which is 2 KiB with
current definitions. IO_TLB_SEGSIZE contiguous slots (128 slots) constitute
what might be called a “slot set”. When a bounce buffer is allocated, it
occupies one or more contiguous slots. A slot is never shared by multiple
bounce buffers. Furthermore, a bounce buffer must be allocated from a single
slot set, which leads to the maximum bounce buffer size being IO_TLB_SIZE *
IO_TLB_SEGSIZE. Multiple smaller bounce buffers may co-exist in a single slot
set if the alignment and size constraints can be met.

> ```
> constitute /ˈkɒnstɪtjuːt/: 组成，构成；制定
> furthermore: 此外
> ```
> 每个池被划分为大小为 IO_TLB_SIZE 的“槽”，根据当前定义，其大小为 2 KiB。
> IO_TLB_SEGSIZE 个连续槽（128 个槽）构成所谓的“槽集”。分配反弹缓冲区时，
> 它会占用一个或多个连续槽。一个槽永远不会被多个反弹缓冲区共享。此外，
> 反弹缓冲区必须从单个槽集中分配，这导致最大反弹缓冲区大小为 
> IO_TLB_SIZE * IO_TLB_SEGSIZE。如果可以满足对齐和大小约束，则多个较小的
> 反弹缓冲区可以共存于单个槽集中。

Slots are also grouped into “areas”, with the constraint that a slot set exists
entirely in a single area. Each area has its own spin lock that must be held to
manipulate the slots in that area. The division into areas avoids contending
for a single global spin lock when swiotlb is heavily used, such as in a CoCo
VM. The number of areas defaults to the number of CPUs in the system for
maximum parallelism, but since an area can’t be smaller than IO_TLB_SEGSIZE
slots, it might be necessary to assign multiple CPUs to the same area. The
number of areas can also be set via the “swiotlb=” kernel boot parameter.

> ```
> manipulate /məˈnɪpjuleɪt/: 操纵; 操作; 控制; 使用; 影响
> division /dɪˈvɪʒn/: 部门
> content: 竞争
> parallelism /ˈpærəlelɪzəm/: 相似; 并行
> ```
>
> 插槽也被分组为“区域”，但有一个限制，即插槽集完全存在于单个区域中。每个区域
> 都有自己的自旋锁，必须持有该锁才能操作该区域中的插槽。划分为区域可避免在 
> swiotlb 大量使用时（例如在 CoCo VM 中）争用单个全局自旋锁。区域数量默认为
> 系统中的 CPU 数量，以实现最大并行性，但由于区域不能小于 IO_TLB_SEGSIZE 
> 插槽，因此可能需要将多个 CPU 分配给同一区域。区域数量也可以通过“swiotlb=”
> 内核启动参数设置。

When allocating a bounce buffer, if the area associated with the calling CPU
does not have enough free space, areas associated with other CPUs are tried
sequentially. For each area tried, the area’s spin lock must be obtained before
trying an allocation, so contention may occur if swiotlb is relatively busy
overall. But an allocation request does not fail unless all areas do not have
enough free space.

> ```
> sequentially  [səˈkwɛntʃəli]: 顺序的
> ```
> 在分配反弹缓冲区时，如果与调用CPU相关联的区域没有足够的可用空间，则会顺序尝
> 试与其他CPU相关的区域。对于每个尝试的区域，在尝试分配之前必须获得该区域的旋
> 转锁，因此如果swiotlb总体上相对繁忙，则可能会发生争用。但是，除非所有区域都
> 没有足够的可用空间，否则分配请求不会失败。

IO_TLB_SIZE, IO_TLB_SEGSIZE, and the number of areas must all be powers of 2 as
the code uses shifting and bit masking to do many of the calculations. The
number of areas is rounded up to a power of 2 if necessary to meet this
requirement.

> IO_TLB_SIZE、IO_TLB_SEGSIZE和区域数量都必须是2的幂，因为代码使用移位和位掩
> 码来进行许多计算。如果需要满足此要求，区域的数量将四舍五入到2的幂。

The default pool is allocated with PAGE_SIZE alignment. If an alloc_align_mask
argument to swiotlb_tbl_map_single() specifies a larger alignment, one or more
initial slots in each slot set might not meet the alloc_align_mask criterium.
Because a bounce buffer allocation can’t cross a slot set boundary, eliminating
those initial slots effectively reduces the max size of a bounce buffer.
Currently, there’s no problem because alloc_align_mask is set based on IOMMU
granule size, and granules cannot be larger than PAGE_SIZE. But if that were to
change in the future, the initial pool allocation might need to be done with
alignment larger than PAGE_SIZE. 


> ```
> criterium [kriterjɔm]: 标准;绕圈赛
> eliminating [ɪˈlɪmɪneɪtɪŋ]: 消除;排除;
> ```
>
> 默认池是使用 PAGE_SIZE 对齐方式分配的。如果 swiotlb_tbl_map_single() 的 
> alloc_align_mask 参数指定了更大的对齐方式，则每个槽集中的一个或多个初始槽可
> 能不满足 alloc_align_mask 标准。由于反弹缓冲区分配不能跨越槽集边界，因此消
> 除这些初始槽可以有效减少反弹缓冲区的最大大小。目前，没有问题，因为
> alloc_align_mask 是根据 IOMMU 颗粒大小设置的，并且颗粒不能大于 PAGE_SIZE。
> 但如果这种情况在未来发生变化，则初始池分配可能需要使用大于 PAGE_SIZE 的对齐
> 方式。


## Dynamic swiotlb

When CONFIG_SWIOTLB_DYNAMIC is enabled, swiotlb can do on-demand expansion of
the amount of memory available for allocation as bounce buffers. If a bounce
buffer request fails due to lack of available space, an asynchronous background
task is kicked off to allocate memory from general system memory and turn it
into an swiotlb pool. Creating an additional pool must be done asynchronously
because the memory allocation may block, and as noted above, swiotlb requests
are not allowed to block. Once the background task is kicked off, the bounce
buffer request creates a “transient pool” to avoid returning an “swiotlb full”
error. A transient pool has the size of the bounce buffer request, and is
deleted when the bounce buffer is freed. Memory for this transient pool comes
from the general system memory atomic pool so that creation does not block.
Creating a transient pool has relatively high cost, particularly in a CoCo VM
where the memory must be decrypted, so it is done only as a stopgap until the
background task can add another non-transient pool.

> ```
> no-demand: 按需;随需应变;按需分配
> expansion [ɪkˈspænʃn] :膨胀
> lack: 缺乏
> kick off: 开始
> ```
>
> 启用 CONFIG_SWIOTLB_DYNAMIC 后，swiotlb 可以按需扩展可分配为反弹缓冲区的内存量。
> 如果反弹缓冲区请求由于可用空间不足而失败，则会启动异步后台任务，从通用系统内存
> 中分配内存并将其转换为 swiotlb 池。必须异步创建附加池，因为内存分配可能会阻塞，
> 并且如上所述，不允许 swiotlb 请求阻塞。一旦启动后台任务，反弹缓冲区请求就会创建
> 一个“临时池”，以避免返回“swiotlb 已满”错误。临时池的大小与反弹缓冲区请求的大小相
> 同，并在释放反弹缓冲区时被删除。此临时池的内存来自通用系统内存原子池，因此创建
> 不会阻塞。创建临时池的成本相对较高，特别是在必须解密内存的 CoCo VM 中，因此它
> 只是作为权宜之计，直到后台任务可以添加另一个非临时池。

Adding a dynamic pool has limitations. Like with the default pool, the memory
must be physically contiguous, so the size is limited to MAX_PAGE_ORDER pages
(e.g., 4 MiB on a typical x86 system). Due to memory fragmentation, a max size
allocation may not be available. The dynamic pool allocator tries smaller sizes
until it succeeds, but with a minimum size of 1 MiB. Given sufficient system
memory fragmentation, dynamically adding a pool might not succeed at all.

> ```
> fragmentation [ˌfræɡmenˈteɪʃn] : 碎片
> ```
> 添加动态池有限制。与默认池一样，内存必须是物理连续的，因此大小限制为 MAX_PAGE_ORDER
> 页（例如，在典型的 x86 系统上为 4 MiB）。由于内存碎片，可能无法获得最大大小的分配。
> 动态池分配器会尝试较小的大小，直到成功为止，但最小大小为 1 MiB。如果系统内存碎片足
> 够多，动态添加池可能根本无法成功。

The number of areas in a dynamic pool may be different from the number of areas
in the default pool. Because the new pool size is typically a few MiB at most,
the number of areas will likely be smaller. For example, with a new pool size
of 4 MiB and the 256 KiB minimum area size, only 16 areas can be created. If
the system has more than 16 CPUs, multiple CPUs must share an area, creating
more lock contention.

> 动态池中的区域数量可能与默认池中的区域数量不同。由于新池大小通常最多为几 MiB，
> 因此区域数量可能会更小。例如，如果新池大小为 4 MiB，且最小区域大小为 256 KiB，
> 则只能创建 16 个区域。如果系统有超过 16 个 CPU，则多个 CPU 必须共享一个区域，
> 从而产生更多的锁争用。

New pools added via dynamic swiotlb are linked together in a linear list.
swiotlb code frequently must search for the pool containing a particular
swiotlb physical address, so that search is linear and not performant with a
large number of dynamic pools. The data structures could be improved for faster
searches.

> 通过动态 swiotlb 添加的新池以线性列表的形式链接在一起。swiotlb 代码必须频繁搜
> 索包含特定 swiotlb 物理地址的池，因此搜索是线性的，并且在大量动态池的情况下性能
> 不佳。可以改进数据结构以加快搜索速度。

Overall, dynamic swiotlb works best for small configurations with relatively
few CPUs. It allows the default swiotlb pool to be smaller so that memory is
not wasted, with dynamic pools making more space available if needed (as long
as fragmentation isn’t an obstacle). It is less useful for large CoCo VMs. 

> 总体而言，动态 swiotlb 最适合 CPU 相对较少的小型配置。它允许默认 swiotlb 池
> 更小，以免浪费内存，而动态池则可以根据需要提供更多空间（只要碎片化不是障
> 碍）。对于大型 CoCo VM，它用处不大。

## Data Structure Details

swiotlb is managed with four primary data structures: io_tlb_mem, io_tlb_pool,
io_tlb_area, and io_tlb_slot. io_tlb_mem describes a swiotlb memory allocator,
which includes the default memory pool and any dynamic or transient pools
linked to it. Limited statistics on swiotlb usage are kept per memory allocator
and are stored in this data structure. These statistics are available under
/sys/kernel/debug/swiotlb when CONFIG_DEBUG_FS is set.

> ```
> transient [ˈtrænʃnt] : 短暂的, 临时的
> ```
> swiotlb 由四个主要数据结构管理：io_tlb_mem、io_tlb_pool、io_tlb_area 和 
> io_tlb_slot。
>
> io_tlb_mem 描述 swiotlb 内存分配器，其中包括默认内存池以及与其链接的任何动
> 态或临时池。每个内存分配器都会保留有关 swiotlb 使用情况的有限统计数据，
> 并存储在此数据结构中。设置 CONFIG_DEBUG_FS 后，这些统计数据可在
> /sys/kernel/debug/swiotlb 下找到。

io_tlb_pool describes a memory pool, either the default pool, a dynamic pool,
or a transient pool. The description includes the start and end addresses of
the memory in the pool, a pointer to an array of io_tlb_area structures, and a
pointer to an array of io_tlb_slot structures that are associated with the
pool.

> io_tlb_pool 描述一个内存池，可以是默认池、动态池或临时池。描述包括池中内存的
> 起始和结束地址、指向 io_tlb_area 结构数组的指针以及指向与池关联的 io_tlb_slot 
> 结构数组的指针。

io_tlb_area describes an area. The primary field is the spin lock used to
serialize access to slots in the area. The io_tlb_area array for a pool has an
entry for each area, and is accessed using a 0-based area index derived from
the calling processor ID. Areas exist solely to allow parallel access to
swiotlb from multiple CPUs.

> ```
> derived [dɪˈraɪvd] from : 来源于
> ```
> io_tlb_area 描述一个区域。主要字段是用于序列化对区域中槽的访问的自旋锁。
> 池的 io_tlb_area 数组为每个区域都有一个条目，并使用从调用处理器 ID 派生
> 的 0-based 的区域索引进行访问。区域的存在只是为了允许从多个 CPU 并行访问 
> swiotlb。

io_tlb_slot describes an individual memory slot in the pool, with size
IO_TLB_SIZE (2 KiB currently). The io_tlb_slot array is indexed by the slot
index computed from the bounce buffer address relative to the starting memory
address of the pool. The size of struct io_tlb_slot is 24 bytes, so the
overhead is about 1% of the slot size.

> io_tlb_slot 描述池中的一个单独的内存槽，大小为 IO_TLB_SIZE（目前为 2 KiB）。
> io_tlb_slot 数组由槽索引索引，该槽索引是从反弹缓冲区地址相对于池的起始内存地址
> 计算出来的。struct io_tlb_slot 的大小为 24 字节，因此开销约为槽大小的 1%。

The io_tlb_slot array is designed to meet several requirements. First, the DMA
APIs and the corresponding swiotlb APIs use the bounce buffer address as the
identifier for a bounce buffer. This address is returned by
swiotlb_tbl_map_single(), and then passed as an argument to
swiotlb_tbl_unmap_single() and the swiotlb_sync_*() functions. The original
memory buffer address obviously must be passed as an argument to
swiotlb_tbl_map_single(), but it is not passed to the other APIs. Consequently,
swiotlb data structures must save the original memory buffer address so that it
can be used when doing sync operations. This original address is saved in the
io_tlb_slot array.

> io_tlb_slot 数组旨在满足几个要求。首先，DMA API 和相应的 swiotlb API 使用反弹缓冲
> 区地址作为反弹缓冲区的标识符。此地址由 swiotlb_tbl_map_single() 返回，然后作为参数
> 传递给 swiotlb_tbl_unmap_single() 和 swiotlb_sync_*() 函数。原始内存缓冲区地址显然
> 必须作为参数传递给 swiotlb_tbl_map_single()，但不会传递给其他 API。因此，swiotlb
> 数据结构必须保存原始内存缓冲区地址，以便在执行同步操作时使用它。此原始地址保存在 
> io_tlb_slot 数组中。

Second, the io_tlb_slot array must handle partial sync requests. In such cases,
the argument to swiotlb_sync_*() is not the address of the start of the bounce
buffer but an address somewhere in the middle of the bounce buffer, and the
address of the start of the bounce buffer isn’t known to swiotlb code. But
swiotlb code must be able to calculate the corresponding original memory buffer
address to do the CPU copy dictated by the “sync”. So an adjusted original
memory buffer address is populated into the struct io_tlb_slot for each slot
occupied by the bounce buffer. An adjusted “alloc_size” of the bounce buffer is
also recorded in each struct io_tlb_slot so a sanity check can be performed on
the size of the “sync” operation. The “alloc_size” field is not used except for
the sanity check.

> 其次，io_tlb_slot 数组必须处理部分同步请求。在这种情况下，swiotlb_sync_*() 
> 的参数不是反弹缓冲区的起始地址，而是反弹缓冲区中间某处的地址，而反弹缓冲区的起
> 始地址对于 swiotlb 代码来说是未知的。但 swiotlb 代码必须能够计算相应的原始内存缓
> 冲区地址，以执行“同步”指示的 CPU 复制。因此，对于反弹缓冲区占用的每个插槽，
> 调整后的原始内存缓冲区地址都会填充到 struct io_tlb_slot 中。每个 struct 
> io_tlb_slot 中还记录了调整后的反弹缓冲区的“alloc_size”，因此可以对“同步”
> 操作的大小执行健全性检查。除了健全性检查外，“alloc_size”字段不用于其他用途。

Third, the io_tlb_slot array is used to track available slots. The “list” field
in struct io_tlb_slot records how many contiguous available slots exist
starting at that slot. A “0” indicates that the slot is occupied. A value of
“1” indicates only the current slot is available. A value of “2” indicates the
current slot and the next slot are available, etc. The maximum value is
IO_TLB_SEGSIZE, which can appear in the first slot in a slot set, and indicates
that the entire slot set is available. These values are used when searching for
available slots to use for a new bounce buffer. They are updated when
allocating a new bounce buffer and when freeing a bounce buffer. At pool
creation time, the “list” field is initialized to IO_TLB_SEGSIZE down to 1 for
the slots in every slot set.

> 第三，io_tlb_slot 数组用于跟踪可用插槽。struct io_tlb_slot 中的“list”字段记录
> 从该插槽开始有多少个连续的可用插槽。“0”表示插槽已被占用。值“1”表示只有当前插槽
> 可用。值“2”表示当前插槽和下一个插槽都可用，等等。最大值是 IO_TLB_SEGSIZE，
> 它可以出现在插槽集中的第一个插槽中，并表示整个插槽集都可用。在搜索可用于新反弹
> 缓冲区的可用插槽时使用这些值。在分配新的反弹缓冲区和释放反弹缓冲区时，它们会更新。
> 在创建池时，“list”字段将初始化为 IO_TLB_SEGSIZE，每个插槽集中的插槽最低为 1。

Fourth, the io_tlb_slot array keeps track of any “padding slots” allocated to
meet alloc_align_mask requirements described above. When
swiotlb_tlb_map_single() allocates bounce buffer space to meet alloc_align_mask
requirements, it may allocate pre-padding space across zero or more slots. But
when swiotbl_tlb_unmap_single() is called with the bounce buffer address, the
alloc_align_mask value that governed the allocation, and therefore the
allocation of any padding slots, is not known. The “pad_slots” field records
the number of padding slots so that swiotlb_tbl_unmap_single() can free them.
The “pad_slots” value is recorded only in the first non-padding slot allocated
to the bounce buffer. 

> 第四，io_tlb_slot 数组会跟踪为满足上述 alloc_align_mask 要求而分配的任何“填充槽”。
> 当 swiotlb_tlb_map_single() 分配反弹缓冲区空间以满足 alloc_align_mask 要求时，
> 它可能会跨零个或多个槽分配预填充空间。但是，当使用反弹缓冲区地址调用
> swiotbl_tlb_unmap_single() 时，控制分配的 alloc_align_mask 值以及任何填充槽的分配
> 都是未知的。“pad_slots”字段记录填充槽的数量，以便 swiotlb_tbl_unmap_single() 可以
> 释放它们。“pad_slots”值仅记录在分配给反弹缓冲区的第一个非填充槽中。

## Restricted pools

The swiotlb machinery is also used for “restricted pools”, which are pools of
memory separate from the default swiotlb pool, and that are dedicated for DMA
use by a particular device. Restricted pools provide a level of DMA memory
protection on systems with limited hardware protection capabilities, such as
those lacking an IOMMU. Such usage is specified by DeviceTree entries and
requires that CONFIG_DMA_RESTRICTED_POOL is set. Each restricted pool is based
on its own io_tlb_mem data structure that is independent of the main swiotlb
io_tlb_mem.

> swiotlb 机制还用于“受限池”，这些池是与默认 swiotlb 池分开的内存池，专用于特
> 定设备的 DMA 使用。受限池在硬件保护功能有限的系统（例如缺少 IOMMU 的系统）
> 上提供一定程度的 DMA 内存保护。此类用法由 DeviceTree 条目指定，并且需要设
> 置 CONFIG_DMA_RESTRICTED_POOL。每个受限池都基于其自己的 io_tlb_mem 数据结
> 构，该结构独立于主 swiotlb io_tlb_mem。

Restricted pools add swiotlb_alloc() and swiotlb_free() APIs, which are called
from the dma_alloc_*() and dma_free_*() APIs. The swiotlb_alloc/free() APIs
allocate/free slots from/to the restricted pool directly and do not go through
swiotlb_tbl_map/unmap_single().

> 受限池添加了 swiotlb_alloc() 和 swiotlb_free() API，它们从 dma_alloc_() 和
> dma_free_() API 调用。swiotlb_alloc/free() API 直接从受限池分配/释放插槽，而不
> 通过 swiotlb_tbl_map/unmap_single()。
