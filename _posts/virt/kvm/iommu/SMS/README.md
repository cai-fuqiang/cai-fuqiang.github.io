## iommu_report_device_fault 注释


> From commit fc36479db74e957c4696b605a32c4afaa15fa6cb("iommu: Add a 
> page fault handler")

```
iommu_queue_iopf - IO Page Fault handler
@fault: fault event
@cookie: struct device, passed to iommu_register_device_fault_handler.

Add a fault to the device workqueue, to be handled by mm.

This module doesn't handle PCI PASID Stop Marker; IOMMU drivers must discard
them before reporting faults. A PASID Stop Marker (LRW = 0b100) doesn't
expect a response. It may be generated when disabling a PASID (issuing a
PASID stop request) by some PCI devices.

> 此模块不处理 PCI PASID Stop Marker；IOMMU 驱动程序必须在报告故障之前丢弃它们。
> PASID Stop Marker（LRW = 0b100）不需要期望响应。它可能在某些 PCI 设备禁用 
> 某个PASID（发出 PASID stop request）时生成。

The PASID stop request is issued by the device driver before unbind(). Once
it completes, no page request is generated for this PASID anymore and
outstanding ones have been pushed to the IOMMU (as per PCIe 4.0r1.0 - 6.20.1
and 10.4.1.2 - Managing PASID TLP Prefix Usage). Some PCI devices will wait
for all outstanding page requests to come back with a response before
completing the PASID stop request. Others do not wait for page responses, and
instead issue this Stop Marker that tells us when the PASID can be
reallocated.

> PASID stop request 由设备驱动程序在 unbind() 之前发出。一旦完成，此 PASID 
> 不再生成page request，未完成的请求已经被推送到 IOMMU（根据 PCIe 4.0r1.0 
> - 6.20.1 和 10.4.1.2 - 管理 PASID TLP 前缀使用）。某些 PCI 设备会等待所
> 有未完成的页面请求返回响应后再完成 PASID stop request。其他设备则不等待页面
> 响应，而是发出此 Stop Marker，以告知我们何时可以重新分配 PASID。

It is safe to discard the Stop Marker because it is an optimization.
a. Page requests, which are posted requests, have been flushed to the IOMMU
   when the stop request completes.
b. The IOMMU driver flushes all fault queues on unbind() before freeing the
   PASID.

> 丢弃 Stop Marker 是安全的，因为它是一种优化。
> a. page request（即已发布的请求）在停止请求完成时已被刷新到 IOMMU。
> b. IOMMU 驱动程序在 unbind() 时会刷新所有故障队列，然后再释放 PASID。

So even though the Stop Marker might be issued by the device *after* the stop
request completes, outstanding faults will have been dealt with by the time
the PASID is freed.

> 因此，即使 Stop Marker 可能在停止请求完成后由设备发出，在释放 PASID 之前，
> 未完成的故障将已经得到处理。

Return: 0 on success and <0 on error.
```

upstream 代码`iommu_report_device_fault`注释
```
Any valid page fault will be eventually routed to an iommu domain and the
page fault handler installed there will get called. The users of this
handling framework should guarantee that the iommu domain could only be
freed after the device has stopped generating page faults (or the iommu
hardware has been set to block the page faults) and the pending page faults
have been flushed. In case no page fault handler is attached or no iopf params
are setup, then the ops->page_response() is called to complete the evt.

> 任何有效的 page fault 最终都会被路由到一个 IOMMU domain，并且在那里安装的 page
> fault 处理程序将被调用。使用该处理框架的用户应确保只有在设备停止生成 page
> fault（或 IOMMU 硬件被设置为阻止 page fault）并且待处理的 page fault 已被刷新
> 后，才能释放 IOMMU domain。如果没有附加 page fault 处理程序或没有设置 IOPF 参数，
> 则会调用 ops->page_response() 来完成事件。
```

## 参考链接
1. [MAIL LIST](https://lore.kernel.org/all/20180511190641.23008-8-jean-philippe.brucker@arm.com/)
2. commit 

   ```
   commit fc36479db74e957c4696b605a32c4afaa15fa6cb

   Jean-Philippe Brucker
   Thu Apr 1 17:47:15 2021 +0200

   iommu: Add a page fault handler
   ```

3. vt-d 7.10 Software Steps to Drain Page Requests & Responses
4. function : intel_iommu_drain_pasid_prq
