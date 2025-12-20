---
layout: post
title:  "DMA remapping"
author: fuqiang
date:   2025-04-02 14:07:00 +0800
categories: [vt-d,dma_remapping]
tags: [dma_remapping]
---

### 3.4.3 Scalable Mode Address Translation

For implementations supporting Scalable Mode Translation (SMTS=1 in Extended
Capability Register), the Root Table Address Register (RTADDR_REG) points to a
scalable-mode root-table when the Translation Table Mode field in the RTADDR_REG
register is programmed to scalable mode (RTADDR_REG.TTM is 01b). The
scalable-mode root-table is similar to the root-table (4KB in size and
containing 256 scalable-mode root-entries to cover the 0-255 PCI bus number
space), but has a different format to reference scalable-mode context-entries.
Each scalable-mode root-entry references a lower scalable-mode context-table and
a upper scalable-mode context-table.

> 对于支持 Scalable Mode Translation（SMTS=1 在 Extended Capability Register 中）
> 的实现，当 RTADDR_REG 寄存器中的 Translation Table Mode 字段被设置为 scalable
> mode（RTADDR_REG.TTM 为 01b）时，Root Table Address Register（RTADDR_REG）指向
> 一个 scalable-mode root-table。scalable-mode root-table 类似于 root-table（大
> 小为 4KB，包含 256 个 scalable-mode root-entry 以覆盖 0-255 的 PCI bus number
> 空间），但具有不同的格式以引用 scalable-mode context-entry。每个 scalable-mode
> root-entry 引用一个下 scalable-mode context-table 和一个上 scalable-mode
> context-table。

The lower scalable-mode context-table is 4-KByte in size and contains 128
scalable-mode context- entries corresponding to PCI functions in device range
0-15 on the bus. The upper scalable-mode context-table is also 4-KByte in size
and contains 128 scalable-mode context-entries corresponding to PCI functions in
device range 16-31 on the bus. Scalable-mode context-entries support both
requests-without-PASID and requests-with-PASID. However unlike legacy mode, in
scalable-mode, requests-without-PASID obtain a PASID value from the RID_PASID
field of the scalable-mode context- entry and are processed similarly to
requests-with-PASID. Implementations not supporting RID_PASID capability
(ECAP_REG.RPS is 0b), use a PASID value of 0 to perform address translation for
requests without PASID.

> Lower scalable-mode context-table 的大小为 4-KByte，包含 128 个 scalable-mode
> context-entry，对应于总线上的设备范围 0-15 的 PCI 功能。Upper scalable-mode
> context-table 也是 4-KByte 大小，包含 128 个 scalable-mode context-entry，对应
> 于总线上的设备范围 16-31 的 PCI 功能。Scalable-mode context-entries 支持
> request-with-PASID 和 request-without-PASID 然而，与传统模式不同，在
> scalable-mode 下，requests-with-PASID 从 scalable-mode context-entry 的
> RID_PASID 字段获取 PASID 值，并与 > request-with-PASID 进行类似的处理。不支持
> RID_PASID 功能（ECAP_REG.RPS 为 0b）的实现，使用 PASID 值为 0 来对
> request-without-PASID进行地址翻译。

The scalable-mode context-entry contains a pointer to a scalable-mode PASID
directory. The upper 14 bits (bits 19:6) of the request’s PASID value are used
to index into the scalable-mode PASID directory. Each present scalable-mode
PASID directory entry contains a pointer to a scalable-mode PASID-table. The
lower 6 bits (bits 5:0) of the request's PASID value are used to index into the
scalable-mode PASID-table. The PASID-table entries contain pointers to both
first-stage and second- stage translation structures, along with the PASID
Granular Translation Type (PGTT) field which specifies whether the request
undergoes a first-stage, second-stage, nested, or pass-through translation
process.

> 在 scalable-mode 中，context-entry 包含一个指向 scalable-mode PASID directory
> 的指针。requests的 PASID 值的上 14 位（位 19:6）用于索引到 scalable-mode PASID
> directory 中。每个有效的 scalable-mode PASID directory 条目包含一个指向
> scalable-mode PASID-table 的指针。请求的 PASID 值的下 6 位（位 5:0）用于索引到
> scalable-mode PASID-table 中。PASID-table 条目包含指向 first-level 和
> second-level translation structure 的指针，以及 PASID Granular Translation
> Type (PGTT) 字段，该字段指定请求是进行 first-level、second-level、nested 还是
> pass-through 翻译过程。

> 总结
>
> 1. scalable-mode中，即便是收到PCIe non-PASID 的请求，也会将PASID 设置为一个值
>    处理(0/RID_PASID)
> 2. scalable-mode 包含一个指向 scalable-mode PASID dir 的指针, 该dir中的每一项,
>    都指向一个sm PASID-table. 该table包含 first-level, second-level translation 
>    struct, 以及PGTT字段，该字段表明了translation mode:
>    + first-level ?
>    + second-level ?
>    + nested
>    + PT(passthrough)
{: .prompt-info}

Figure 3-4 illustrates device to domain mapping with scalable-mode
context-table.

![Figure-3-4](pic/Figure-3-4.png)

The scalable-mode root-entry format is described in Section 9.2, the
scalable-mode context-entry format is described in Section 9.4, the
scalable-mode PASID-directory-entry format is described in Section 9.5, and the
scalable-mode PASID-table entry format is described in Section 9.6.

> Note
> 
> Prior version of this specification supported a limited form of address
> translation for requests-with-PASID, that was referred to as Extended Mode
> address translation (enumerated through ECAP_REG bit 24). This mode is no
> longer supported and replaced with scalable mode address translation. ECAP_REG
> bit 24 must be reported as 0 in all future implementations to ensure software
> backward compatibility.
>
> > 以前版本的规范支持一种有限形式的地址转换，用于 request-with-PASID 的请求，这
> > 种形式被称为扩展模式地址转换（通过 ECAP_REG 位 24 枚举）。这种模式不再被支持，
> > 而是被 scalable mode 地址转换所取代。为了确保软件的向后兼容性，所有未来的实
> > 现必须将 ECAP_REG 位 24 报告为 0。
