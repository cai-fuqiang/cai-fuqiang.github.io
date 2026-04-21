## 29.3.5 Accessed and Dirty Flags for EPT

The Intel 64 architecture supports accessed and dirty flags in ordinary
paging-structure entries (see Section 4.8). Some processors also support
corresponding flags in EPT paging-structure entries. Software should read the
VMX capability MSR IA32_VMX_EPT_VPID_CAP (see Appendix A.10) to determine
whether the processor supports this feature.

Software can enable accessed and dirty flags for EPT using bit 6 of the
extended-page-table pointer (EPTP), a VM- execution control field (see Table
25-9 in Section 25.6.11). If this bit is 1, the processor will set the accessed
and dirty flags for EPT as described below. In addition, setting this flag
causes processor accesses to guest paging- structure entries to be treated as
writes (see below and Section 29.3.3.2).

For any EPT paging-structure entry that is used during guest-physical-address
translation, bit 8 is the accessed flag. For a EPT paging-structure entry that
maps a page (as opposed to referencing another EPT paging structure), bit 9 is
the dirty flag.

Whenever the processor uses an EPT paging-structure entry as part of
guest-physical-address translation, it sets the accessed flag in that entry (if
it is not already set).

Whenever there is a write to a guest-physical address, the processor sets the
dirty flag (if it is not already set) in the EPT paging-structure entry that
identifies the final physical address for the guest-physical address (either an
EPT PTE or an EPT paging-structure entry in which bit 7 is 1).

When accessed and dirty flags for EPT are enabled, processor accesses to guest
paging-structure entries are treated as writes (see Section 29.3.3.2). Thus,
such an access will cause the processor to set the dirty flag in the EPT
paging-structure entry that identifies the final physical address of the guest
paging-structure entry.

(This does not apply to loads of the PDPTE registers for PAE paging by the MOV
to CR instruction; see Section 4.4.1. Those loads of guest PDPTEs are treated
as reads and do not cause the processor to set the dirty flag in any EPT
paging-structure entry.)


These flags are “sticky,” meaning that, once set, the processor does not clear
them; only software can clear them.

A processor may cache information from the EPT paging-structure entries in TLBs
and paging-structure caches (see Section 29.4). This fact implies that, if
software changes an accessed flag or a dirty flag from 1 to 0, the processor
might not set the corresponding bit in memory on a subsequent access using an
affected guest-physical address.

## 29.3.6 Page-Modification Logging

When accessed and dirty flags for EPT are enabled, software can track writes to
guest-physical addresses using a feature called page-modification logging.

Software can enable page-modification logging by setting the “enable PML”
VM-execution control (see Table 25-7 in Section 25.6.2). When this control is
1, the processor adds entries to the page-modification log as described below.
The page-modification log is a 4-KByte region of memory located at the physical
address in the PML address VM-execution control field. The page-modification
log consists of 512 64-bit entries; the PML index VM-execution control field
indicates the next entry to use.

Before allowing a guest-physical access, the processor may determine that it
first needs to set an accessed or dirty flag for EPT (see Section 29.3.5). When
this happens, the processor examines the PML index. If the PML index is not in
the range 0–511, there is a page-modification log-full event and a VM exit
occurs. In this case, the accessed or dirty flag is not set, and the
guest-physical access that triggered the event does not occur.

If instead the PML index is in the range 0–511, the processor proceeds to
update accessed or dirty flags for EPT as described in Section 29.3.5. If the
processor updated a dirty flag for EPT (changing it from 0 to 1), it then
operates as follows:

1. The guest-physical address of the access is written to the page-modification
   log. Specifically, the guest- physical address is written to physical
   address determined by adding 8 times the PML index to the PML address. Bits
   11:0 of the value written are always 0 (the guest-physical address written
   is thus 4-KByte aligned).

2. The PML index is decremented by 1 (this may cause the value to transition
   from 0 to FFFFH). 

Because the processor decrements the PML index with each log entry, the value
may transition from 0 to FFFFH. At that point, no further logging will occur,
as the processor will determine that the PML index is not in the range 0– 511
and will generate a page-modification log-full event (see above).

## 29.3.7 EPT and Memory Typing

This section specifies how a logical processor determines the memory type use
for a memory access while EPT is in use. (See Chapter 12, “Memory Cache
Control‚” of the Intel® 64 and IA-32 Architectures Software Developer’s Manual,
Volume 3A, for details of memory typing in the Intel 64 architecture.) Section
29.3.7.1 explains how the memory type is determined for accesses to the EPT
paging structures. Section 29.3.7.2 explains how the memory type is determined
for an access using a guest-physical address that is translated using EPT.

### 29.3.7.1 Memory Type Used for Accessing EPT Paging Structures

This section explains how the memory type is determined for accesses to the EPT
paging structures. The determi- nation is based first on the value of bit 30
(cache disable—CD) in control register CR0:

* If CR0.CD = 0, the memory type used for any such reference is the EPT
  paging-structure memory type, which is specified in bits 2:0 of the
  extended-page-table pointer (EPTP), a VM-execution control field (see Section
  25.6.11). A value of 0 indicates the uncacheable type (UC), while a value of
  6 indicates the write-back type (WB). Other values are reserved.

* If CR0.CD = 1, the memory type used for any such reference is uncacheable
  (UC).

The MTRRs have no effect on the memory type used for an access to an EPT
paging structure.

## 29.3.7.2 Memory Type Used for Translated Guest-Physical Addresses

The effective memory type of a memory access using a guest-physical address (an
access that is translated using EPT) is the memory type that is used to access
memory. The effective memory type is based on the value of bit 30 (cache
disable—CD) in control register CR0; the last EPT paging-structure entry used
to translate the guest- physical address (either an EPT PDE with bit 7 set to 1
or an EPT PTE); and the PAT memory type (see below):

* The PAT memory type depends on the value of CR0.PG:
  + If CR0.PG = 0, the PAT memory type is WB (writeback).

  + If CR0.PG = 1, the PAT memory type is the memory type selected from the
    IA32_PAT MSR as specified in Section 12.12.3, “Selecting a Memory Type
    from the PAT.”

* The EPT memory type is specified in bits 5:3 of the last EPT paging-structure
  entry: 0 = UC; 1 = WC; 4 = WT; 5 = WP; and 6 = WB. Other values are reserved
  and cause EPT misconfigurations (see Section 29.3.3).

* If CR0.CD = 0, the effective memory type depends upon the value of bit 6 of
  the last EPT paging-structure entry:

  + If the value is 0, the effective memory type is the combination of the EPT
    memory type and the PAT memory type specified in Table 12-7 in Section
    12.5.2.2, using the EPT memory type in place of the MTRR memory type.
  + If the value is 1, the memory type used for the access is the EPT memory type. 
    The PAT memory type is ignored.

* If CR0.CD = 1, the effective memory type is UC.

The MTRRs have no effect on the memory type used for an access to a guest-physical address.
