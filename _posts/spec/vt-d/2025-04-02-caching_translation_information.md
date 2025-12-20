## 6.1 Caching Mode

The Caching Mode (CM) field in Capability Register indicates if the hardware
implementation caches not-present or erroneous translation-structure entries.
When the CM field is reported as Set, any software updates to remapping
structures other than first-stage mapping (including updates to not- present
entries or present entries whose programming resulted in translation faults)
requires explicit invalidation of the caches.

Hardware implementations of this architecture must support operation
corresponding to CM=0. Operation corresponding to CM=1 may be supported by
software implementations (emulation) of this architecture for efficient
virtualization of remapping hardware. Software managing remapping hardware
should be written to handle both caching modes.

Software implementations virtualizing the remapping architecture (such as a VMM
emulating remapping hardware to an operating system running within a guest
partition) may report CM=1 to efficiently virtualize the hardware. Software
virtualization typically requires the guest remapping structures to be shadowed
in the host. Reporting the Caching Mode as Set for the virtual hardware requires
the guest software to explicitly issue invalidation operations on the virtual
hardware for any/all updates to the guest remapping structures. The virtualizing
software may trap these guest invalidation operations to keep the shadow
translation structures consistent to guest translation structure modifications,
without resorting to other less efficient techniques (such as write-protecting
the guest translation structures through the processor’s paging facility).

## 6.2 Address Translation Caches

This section provides architectural behavior of following remapping hardware
address translation caches:

* Context-cache
  + Caches context-entry, or scalable-mode context-entry encountered on a
    address translation of requests.
* PASID-cache

  + Caches scalable-mode PASID-table entries encountered on address translation
    of requests.
* I/O Translation Look-aside Buffer (IOTLB)

  + Caches the effective translation for a request. This can be the result of
    second-stage only page-walk, first-stage only page-walk, or nested page-walk -
    depending on the type of request (with or without PASID) that is address
    translated, and the programming of the DMA remapping hardware and various
    translation structures.
