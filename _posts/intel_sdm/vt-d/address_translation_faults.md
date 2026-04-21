Address translation faults are classified as follows:

* **_Non-recoverable Faults_**:Requests that encounter non-recoverable address
  translation faults are aborted by the remapping hardware, and typically
  require a reset of the device (such as through a function-level-reset) to
  recover and re-initialize the device to put it back into service.

  > 不可恢复的错误：遇到不可恢复地址翻译错误的请求会被重映射硬件中止，通常需
  > 要通过重置设备（例如，通过功能级重置）来恢复和重新初始化设备，以便重新投入
  > 使用。

* **_Recoverable Faults_**:Requests that encounter recoverable address translation
  faults can be retried by the requesting device after the condition causing
  the recoverable fault is handled by software. Recoverable translation faults
  are detected at the Device-TLB on the device and require the device to
  support Address Translation Services (ATS) capability. Refer to Address
  Translation Services in PCI Express Base Specification Revision 4.0 or later
  for details.
  > 可恢复的错误：遇到可恢复地址翻译错误的请求，可以在导致可恢复错误的条件被软件
  > 处理后由请求设备重试。可恢复的翻译错误在设备的设备-TLB（翻译后备缓冲）中被检测到，
  > 并要求设备支持地址翻译服务（ATS）功能。有关详细信息，请参阅 PCI Express 基本规范
  > 修订版 4.0 或更高版本中的 Address Translation Services.

## 7.1 Remapping Hardware Behavior on Faults

### 7.1.1 Non-Recoverable Address Translation Faults

Non-recoverable address translation faults can be detected by remapping
hardware for many different kinds of requests as shown by Table 30. A
non-recoverable fault condition is considered “qualified” if software can
suppress reporting of the fault by setting one of the Fault Processing Disable
(FPD) bits available in one or more of the address translation structures
(i.e., the context-entry, scalable-mode context-entry, scalable-mode
PASID-directory entry, scalable-mode PASID-table entry). For a request that
encounters a “qualified” non-recoverable fault condition, if the remapping
hardware encountered any translation structure entry with an FPD field value of
1, the remapping hardware must not report the fault to software. For example,
when processing a request that encounters an FPD field with a value of 1 in the
scalable-mode context-entry and encounters any “qualified” fault such as SCT.*,
SPD.*, SPT.*, SFS.*, SSS.*, or SGN.*, the remapping hardware will not report
the fault to software. Memory requests that result in non-recoverable address
translation faults are blocked by hardware. The exact method for blocking such
requests are implementation-specific. For example:


> Non-recoverable 地址翻译错误可以由重映射硬件在多种不同类型的请求中检测到，
> 如表30所示。如果软件可以通过在一个或多个地址翻译结构条目（即，上下文条目、
> scalable-mode context-entry、scalable-mode PASID 目录条目、scalable-mode PASID
> 表条目）中设置一个故障处理禁用（FPD）位来抑制错误报告，则认为 Non-recoverable
> 错误条件是“qualified”的。对于遇到“qualified” Non-recoverable 错误条件的请求，
> 如果重映射硬件在任何翻译结构条目中遇到 FPD 字段值为1，则重映射硬件不得向软件报
> 告该错误。例如，当处理遇到 scalable-mode context-entry 中 FPD 字段值为1的请求，
> 并遇到任何“qualified”错误（如 SCT.、SPD.、SPT.、SFS.、SSS.* 或 SGN.*）时，
> 重映射硬件将不会向软件报告该错误。导致 Non-recoverable 地址翻译错误的内存请求会
> 被硬件阻止。阻止此类请求的具体方法取决于具体实现。例如：

* Faulting write requests may be handled in much the same way as hardware
  handles write requests to non-existent memory. For example, the write request
  is discarded in a manner convenient for implementations (such as by dropping
  the cycle, completing the write request to memory with all byte enables
  masked off, re-directing to a catch-all memory location, etc.).

* Faulting read requests may be handled in much the same way as hardware
  handles read requests to non-existent memory. For example, the request may be
  redirected to a catch-all memory location, returned as all 0’s or 1’s in a
  manner convenient to the implementation, or the request may be completed with
  an explicit error indication (recommended). For faulting read requests from
  PCI Express devices, hardware indicates “Unsupported Request” (UR) or
  “Completer Abort” (CA) in the completion status field of the PCI Express read
  completion.

> * 发生故障的写请求可以类似于硬件处理对 non-existent 内存的写请求。例如，
>   写请求可以以对实现方便的方式被丢弃（如通过丢弃周期、以所有字节使能位屏蔽
>   的方式完成对内存的写请求、重定向到一个捕获所有的内存位置等）。

> * 发生故障的读请求可以类似于硬件处理对不存在 non-existent 的读请求。
>   例如，请求可以被重定向到一个捕获所有的内存位置，以对实现方便的方式返回全0或全1，
>   或者请求可以通过显式的错误指示完成（推荐）。对于来自 PCI Express 设备的故障读
>   请求，硬件在 PCI Express 读完成的完成状态字段中指示“Unsupported Request”（UR）
>   或“Completer Abort”（CA）。

### 7.1.2 Recoverable Address Translation Faults

When remapping hardware detects a recoverable fault on a translation-request
from Device-TLB, it is not reported to software as a fault. Instead, remapping
hardware sends a successful translation completion with limited or no
permission/privileges. When such a translation completion is received by the
Device-TLB, a translation fault is detected at the Device-TLB, and handled as
recoverable fault if the Device supports recoverable address translation
faults. What device accesses can tolerate and recover from Device-TLB detected
faults and what device accesses cannot tolerate Device-TLB detected faults is
specific to the device. Device-specific software (e.g., driver) is expected to
make sure translations with appropriate permissions and privileges are present
before initiating device accesses that cannot tolerate faults. Device
operations that can recover from such Device-TLB faults typically involves two
steps:

> 当 remapping hardware 在来自 Device-TLB 的 translation-request 中检测到可恢复的故
> 障时，它不会将其作为故障报告给软件。相反，remapping hardware 发送一个 successfull
> translation completion，但权限或特权有限或没有。当 Device-TLB 接收到这样的 
> translation completion 时，在 Device-TLB 处检测到 translation fault，如果设备支
> 持可恢复的 address translation faults，则将其作为可恢复故障处理。哪些设备访问可
> 以容忍并从 Device-TLB 检测到的故障中恢复，以及哪些设备访问不能容忍 Device-TLB 
> 检测到的故障，是设备特定的。设备特定的软件（例如 driver）需要确保在发起不能容忍
> 故障的设备访问之前，存在具有适当权限和特权的翻译。能够从此类 Device-TLB 故障中
> 恢复的设备操作通常涉及两个步骤：


+ Report the recoverable fault to host software; This may be done in a
  device-specific manner (e.g., through the device-specific driver), or if the
  device supports PCI Express Page Request Services (PRS) Capability, by
  issuing a page-request message to the remapping hardware. Section 7.4
  describes the page-request interface through the remapping hardware.
+ After the recoverable fault is serviced by software, the device operation
  that originally resulted in the recoverable fault may be replayed, in a
  device-specific manner.

> + 向主机软件报告可恢复的故障： 这可以通过设备特定的方式完成（例如，通过设备特定的 driver），
> 或者如果设备支持 PCI Express Page Request Services (PRS) Capability，可以通过向 
> remapping hardware 发出 page-request 消息来实现。第 7.4 节描述了通过 remapping 
> hardware 的 page-request 接口。
> + 重放设备操作： 在软件处理完可恢复的故障之后，最初导致该可恢复故障的设备操作可以以设
> 备特定的方式重放。


Device-TLB implementations must ensure that a device request, that led to
detection of a translation fault in the Device-TLB and reporting of the fault
to system software, does not reuse the same faulty translation on retry of the
device request after software has informed the device that the reported fault
has been handled. However, other device requests may use the same translation
in Device-TLB and may succeed or report another fault to system software. One
way devices can meet this requirement is by removing the faulty translations
from the Device-TLB after receiving confirmation from system software that the
fault has been serviced, however there may other device specific methods to
achieve this goal. If a recoverable page fault is reported to software in a
device-specific manner, rather than using Page Request Services, then software
should ensure that stale IOTLB entries in the remapping hardware in
root-complex are invalidated.

> Device-TLB 实现必须确保设备请求在 Device-TLB 中检测到 translation fault 
> 并将故障报告给系统软件后，在软件通知设备故障已处理后，重试设备请求时不再重用相
> 同的错误翻译。然而，其他设备请求可能会使用 Device-TLB 中的相同翻译，并可能成功
> 或再次向系统软件报告故障。设备可以通过在收到系统软件确认故障已处理后，从
> Device-TLB 中移除错误的翻译来满足此要求，但也可能有其他设备特定的方法来实现这一
> 目标。如果以设备特定的方式而不是使用 Page Request Services 向软件报告可恢复的页
> 面故障，则软件应确保在 root-complex 中的 remapping hardware 中失效过期的 IOTLB
> 条目。

## 7.2 Non-Recoverable Fault Reporting

Processing of non-recoverable address translation faults (and interrupt
translation faults) involves logging the fault information and reporting to
software through a fault event (interrupt). The remapping architecture defines
Primary Fault Logging as the default fault logging method that must be
supported by all implementations of this architecture.

### 7.2.1 Primary Fault Logging

The primary method for logging non-recoverable faults is through Fault
Recording Registers. The number of Fault Recording Registers supported is
reported through the Capability Register (see Section 11.4.2). Section 11.4.7.6
describes the Fault Recording Registers.

> 处理 non-recoverable 地址翻译故障（以及中断翻译故障）涉及记录故障信息，
> 并通过故障事件（中断）报告给软件。重映射架构定义了 Primary Fault Logging
> 作为默认的故障记录方法，所有该架构的实现都必须支持这种方法。

Hardware maintains an internal index to reference the Fault Recording Register
in which the next non- recoverable fault can be recorded. The index is reset to
zero when both address and interrupt translations are disabled (i.e., TES and
IES fields Clear in Global Status Register), and increments whenever a fault is
recorded in a Fault Recording Register. The index wraps around from N-1 to 0,
where N is the number of fault recording registers supported by the remapping
hardware unit.

> 硬件维护一个内部索引，用于引用 Fault Recording Register，以记录下一个 
> non-recoverable 故障。当地址和中断翻译均被禁用时（即，Global Status Register 
> 中的 TES 和 IES 字段被清除），该索引重置为零，并在每次在 Fault Recording 
> Register 中记录故障时递增。该索引从 N-1 回绕到 0，其中 N 是重映射硬件单元
> 支持的故障记录寄存器的数量。

Hardware maintains the Primary Pending Fault (PPF) field in the Fault Status
Register as the logical “OR” of the Fault (F) fields across all the Fault
Recording Registers. The PPF field is re-computed by hardware whenever hardware
or software updates the F field in any of the Fault Recording Registers.

> 硬件在 Fault Status Register 中维护 Primary Pending Fault (PPF) 字段，该字段
> 是所有 Fault Recording Registers 中的 Fault (F) 字段的逻辑“或”。每当硬件或软
> 件更新任何 Fault Recording Register 中的 F 字段时，硬件会重新计算 PPF 字段。

When primary fault recording is active, hardware functions as follows upon
detecting a non-recoverable address translation or interrupt translation
fault:

> 当primary fault reporting 处于活动状态时，硬件在检测到不可恢复的地址转换或
> 中断转换故障时，功能如下：

+ Hardware checks the current value of the Primary Fault Overflow (PFO) field
  in the Fault Status Register. If it is already Set, the new fault is not
  recorded.
  > 硬件检查 Fault Status Register 中的 Primary Fault Overflow (PFO) 字段的当
  > 前值。如果该字段已经被设置，则不会记录新的故障。

+ If hardware supports compression1 of multiple faults from the same requester,
  it compares the source-id (SID) field of each Fault Recording Register with
  Fault (F) field Set, to the source-id of the currently faulted request. If
  the check yields a match, the fault information is not recorded.
  > 如果硬件支持来自同一请求者的多个故障的压缩，它将比较每个 Fault Recording 
  > Register 中 Fault (F) 字段已设置的 source-id (SID) 字段，与当前发生故障的
  > 请求的 source-id。如果检查结果匹配，则不记录故障信息。

+ If the above check does not yield a match (or if hardware does not support
  compression of faults), hardware checks the Fault (F) field of the Fault
  Recording Register referenced by the internal index. If that field is already
  Set, hardware sets the Primary Fault Overflow (PFO) field in the Fault Status
  Register, and the fault information is not recorded.
  > 如果上述检查未产生匹配结果（或者如果硬件不支持故障的压缩），硬件将检查由内部索引
  > 引用的 Fault Recording Register 中的 Fault (F) 字段。如果该字段已经被设置，硬件
  > 将设置 Fault Status Register 中的 Primary Fault Overflow (PFO) 字段，并且故障信息
  > 不会被记录。

+ If the above check indicates there is no overflow condition, hardware records
  the current fault information in the Fault Recording Register referenced by
  the internal index. Depending on the current value of the PPF field in the
  Fault Status Register, hardware performs one of the following steps:
  > 如果上述检查表明没有溢出情况，硬件会将当前的故障信息记录在由内部索引引用的 
  > Fault Recording Register 中。根据 Fault Status Register 中 PPF 字段的当前值，
  > 硬件执行以下步骤之一：

  + If the PPF field is currently Set (implying there are one or more pending
    faults), hardware sets the F field of the current Fault Recording Register
    and increments the internal index.
    > 如果 PPF 字段当前被设置（意味着有一个或多个待处理的故障），硬件将设置当前
    > Fault Recording Register 的 F 字段并增加内部索引。

  + Else, hardware records the internal index in the Fault Register Index (FRI)
    field of the Fault Status Register and sets the F field of the current
    Fault Recording Register (causing the PPF field also to be Set). Hardware
    increments the internal index, and an interrupt may be generated based on
    the hardware interrupt generation logic described in Section 7.3.
    > 否则，硬件将在 Fault Status Register 的 Fault Register Index (FRI) 字段中
    > 记录内部索引，并设置当前 Fault Recording Register 的 F 字段（这也会导致
    > PPF 字段被设置）。硬件增加内部索引，并且可能会根据第 7.3 节中描述的硬件中
    > 断生成逻辑生成一个中断。

Software is expected to process the non-recoverable faults reported through the
Fault Recording Registers in a circular FIFO fashion starting from the Fault
Recording Register referenced by the Fault Recording Index (FRI) field, until
it finds a Fault Recording Register with no faults (F field Clear).

> 软件应以循环 FIFO 的方式处理通过 Fault Recording Registers 报告的不可恢复故障，
> 从 Fault Recording Index (FRI) 字段引用的 Fault Recording Register 开始，直到
> 找到一个没有故障的 Fault Recording Register（F 字段清除）。

To recover from a primary fault overflow condition, software must first process
the pending faults in each of the Fault Recording Registers, Clear the Fault
(F) field in all those registers, and Clear the overflow status by writing a 1
to the Primary Fault Overflow (PFO) field. Once the PFO field is cleared by
software, hardware continues to record new faults starting from the Fault
Recording Register referenced by the current internal index. 

> 要从主要故障溢出状态中恢复，软件必须首先处理每个 Fault Recording Register 中的待
> 处理故障，清除所有这些寄存器中的 Fault (F) 字段，并通过向 Primary Fault Overflow 
> (PFO) 字段写入 1 来清除溢出状态。一旦 PFO 字段被软件清除，硬件将从当前内部索引引
> 用的 Fault Recording Register 开始继续记录新故障。
