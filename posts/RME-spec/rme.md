## GPC faults
> FROM arm-A spec
> D9.2 GPC faults

If any of the following apply to the PA input to the GPC, the access generates a
Granule protection fault at Level 0:

* The input is a Secure PA and the Effective value of GPCCR_EL3.SPAD is 1.
* The input is a Non-secure PA and the Effective value of GPCCR_EL3.NSPAD is 1.
* The input is a Realm PA and the Effective value of GPCCR_EL3.RLPAD is 1.

...

An access is not permitted by the GPT if it is made to a PA space not permitted
according to the Granule Protection Information (GPI) value returned by the GPT
lookup.

If an access is not permitted by the GPT, then the access generates a Granule
protection fault at Level x, where x is the level of the GPT entry that the
access was checked against.

> 如果一次访问所对应的物理地址空间（PA space）不被 GPT 查找返回的粒度保护信息
> （GPI）允许，则该访问不被 GPT 允许。
> 
> 如果某次访问不被 GPT 允许，那么该访问会在第 x 层产生 GPF（Granule
> protection fault），其中 x 是检查该访问所对应的 GPT 表项的层级。


## GPCCR_EL3
> FROM  arm-A spec:
> "D24.2.50 GPCCR_EL3, Granule Protection Check Control Register (EL3)"
* L0GPTSZ, bits [23:20]

  Level 0 GPT entry size.

  This field advertises the number of least-significant address bits protected
  by each entry in the level 0 GPT.
  + 0b0000 30-bits. Each entry covers 1GB of address space.
  + 0b0100 34-bits. Each entry covers 16GB of address space.
  + 0b0110 36-bits. Each entry covers 64GB of address space.
  + 0b1001 39-bits. Each entry covers 512GB of address space.

* GPC, bit [16]
  + Granule Protection Check Enable.
  + 0b0: Granule protection checks are disabled. Accesses are not prevented by
    this mechanism.
  + 0b1: All accesses to physical address spaces are subject to granule
    protection checks, except for fetches of GPT information and accesses
    governed by the GPCCR_EL3.GPCP control.
    > 所有对物理地址的访问都受限于`granule protection checks`, 除了 fetch GPT
    > information 和 访问 受 GPCCR_EL3.GPCP 管理的字段.
 
  If any stage of translation is enabled, this bit is permitted to be cached in a TLB.
* GPCP, bit [17]

  + 0b0: GPC faults are all reported with a priority that is consistent with the
    GPC being performed on any access to physical address space.
    > GPC（Granule Protection Check）故障的报告优先级，与对所有物理地址空间访问执行 
    > GPC 时保持一致。
  + 0b1: A GPC fault for the fetch of a Table descriptor for a stage 2 translation
    table walk might not be generated or reported.

    All other GPC faults are reported with a priority consistent with the GPC
    being performed on all accesses to physical address spaces.

    > 当进行二级页表遍历（stage 2 translation table walk）时，如果是获取表描述符
    > （Table descriptor）的操作，可能不会生成或报告 GPC 故障。但其它所有类型的
    > GPC 故障，仍然会按照对所有物理地址空间访问执行 GPC 时的优先级进行报告。
* PGS, bits [15:14]: Physical Granule size.
  + 0b00: 4KB
  + 0b01: 64KB
  + 0b10: 16KB
* SH, bits [13:12]

  GPT fetch Shareability attribute

  + 0b00 Non-shareable.
  + 0b10 Outer Shareable.
  + 0b11 Inner Shareable.
* SPAD, bit [7]:
  Secure PA space Disable. This field controls access to the Secure PA space.

  + 0b0: This control has no effect on accesses.
  + 0b1: When granule protection checks are enabled, access to the Secure
    Physical Address space generates a Granule Protection fault.
* NSPAD, bit [6]

  Non-secure PA space Disable. This field controls access to the Non-secure PA
  space.
  + 0b0: This control has no effect on accesses.
  + 0b1: When granule protection checks are enabled, access to the Non-secure
    Physical Address space generates a Granule Protection fault.
* RLPAD, bit [5]

  Realm PA space Disable. This field controls access to the Realm PA space.

  + 0b0 This control has no effect on accesses.
  + 0b1 When granule protection checks are enabled, access to the Realm Physical
    Address space generates a Granule Protection fault.

* PPS, bits [2:0]: Protected Physical Address Size.

  The size of the memory region protected by GPTBR_EL3, in terms of the number
  of least-significant address bits.

  PPS Meaning
  + 0b000 32 bits, 4GB protected address space.
  + 0b001 36 bits, 64GB protected address space.
  + 0b010 40 bits, 1TB protected address space.
  + 0b011 42 bits, 4TB protected address space.
  + 0b100 44 bits, 16TB protected address space.
  + 0b101 48 bits, 256TB protected address space.
  + 0b110 52 bits, 4PB protected address space.
