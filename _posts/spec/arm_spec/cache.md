## D7.5.8.1.2 Terminology for Clean, Invalidate, and Clean and Invalidate instructions

Caches introduce coherency problems in two possible directions:

> 缓存会在两个方向上引入一致性问题:

1. An update to a memory location by a PE that accesses a cache might not be
   visible to other observers that can access memory. This can occur because new
   updates are still in the cache and are not visible yet to the other observers
   that do not access that cache. access memory. This can occur because new
   updates are still in the cache and are not visible yet to the other observers
   that do not access that cache.

   > 由访问缓存的处理单元（PE）对某个内存位置进行的更新，可能对其他能够访问该内
   > 存的观察者不可见。这是因为新的更新仍然保留在缓存中，还没有对那些不访问该缓
   > 存的其他观察者可见。
   >
   >> update cache but have not writeback memory

2. Updates to memory locations by other observers that can access memory might
   not be visible to a PE that accesses a cache. This can occur when the cache
   contains an old, or stale, copy of the memory location that has been updated.

   > 由其他能够访问内存的观察者对某个内存位置所做的更新，可能对访问缓存的处理单
   > 元（PE）不可见。这种情况可能发生在缓存中还保留着该内存位置的旧副本（即过期
   > 的副本），而该位置实际上已经被更新。
   >
   >> update memory but have not update cache

>> 上面提到的是两个方向
>>
>> 1. cache --- not writeback ---> memory
>> 2. memory --- not invalidate --> cache

The Clean and Invalidate instructions address these two issues. The definitions
of these instructions are:

> Clean 和 Invalidate 指令用于解决上述两个问题。这些指令的定义如下：

* **Clean**

  A cache clean instruction ensures that updates made by an observer that
  controls the cache are made visible to other observers that can access memory
  at the point to which the instruction is performed. Once the Clean has
  completed, the new memory values are guaranteed to be visible to the point to
  which the instruction is performed, for example to the Point of Unification.
  The cleaning of a cache entry from a cache can overwrite memory that has been
  written by another observer only if the entry contains a location that has
  been written to by an observer in the shareability domain of that memory
  location.

  > 缓存清理（Clean）指令确保由控制该缓存的观察者所做的更新，在指令执行的那个点
  > 上，对其他能够访问内存的观察者可见。一旦清理操作完成，新写入的内存值就保证在
  > 该点（例如统一点 Point of Unification）可见。只有当缓存项包含的内存位置是由
  > 同一共享域内的观察者写入过时，从缓存中清理该项才可能覆盖其他观察者写入的内存
  > 内容。
  >
  >> **WRITEBACK**

* **Invalidate**

  A cache invalidate instruction ensures that updates made visible by observers
  that access memory at the point to which the invalidate is defined, are made
  visible to an observer that controls the cache. This might result in the loss
  of updates to the locations affected by the invalidate instruction that have
  been written by observers that access the cache, if those updates have not
  been cleaned from the cache since they were made. 

  If the address of an entry on which the invalidate instruction operates is
  Normal, Non-cacheable or any type of Device memory then an invalidate
  instruction also ensures that this address is not present in the cache.

  > 缓存失效（Invalidate）指令确保，在失效操作定义的那个点上，由访问内存的观察者
  > 所做的更新，对控制该缓存的观察者可见。如果自从某个缓存项被写入后还没有被清理
  > 过，那么对该项执行失效指令，可能会导致由访问缓存的观察者所做的更新丢失。
  > 
  > 如果失效指令操作的地址属于 Normal、Non-cacheable 或任何类型的 Device 内存，
  > 那么失效指令还会确保该地址不会出现在缓存中。
  >
  >> **INVALIDATE**

  > Note
  >
  > Entries for addresses that are Normal Cacheable can be allocated to the
  > cache at any time, and so the cache invalidate instruction cannot ensure
  > that the address is not present in a cache.
  >
  >> 对于属于 Normal Cacheable 类型的地址，缓存项可以在任何时候分配到缓存中，因
  >> 此缓存失效（invalidate）指令无法确保该地址不会出现在缓存中。

* Clean and Invalidate

  A cache clean and invalidate instruction behaves as the execution of a clean
  instruction followed immediately by an invalidate instruction. Both
  instructions are performed to the same location.

  > 缓存清理并失效（clean and invalidate）指令的行为等同于先执行一次清理（clean）
  > 指令，然后紧接着执行一次失效（invalidate）指令，这两条指令都作用于同一位置。

The points to which a cache maintenance instruction can be defined differ
depending on whether the instruction operates by VA or by set/way:

> 缓存维护指令所能定义的作用点不同，具体取决于该指令是通过虚拟地址（VA）还是通过
> 组/路（set/way）进行操作。

* For instructions operating by set/way, the point is defined to be to the next
  level of caching. For the All operations, the point is defined as the Point of
  Unification for each location held in the cache.

  > 对于按组/路（set/way）操作的指令，其作用点被定义为下一级缓存。对于“全部
  > （All）”操作，其作用点被定义为缓存中每个位置的统一点（Point of Unification）。

* For instructions operating by VA, the following conceptual points are defined:
  > 对于按虚拟地址（VA）操作的指令，定义了以下几个概念性作用点：

  + Point of Coherency (PoC)

    The point at which all agents that can access memory are guaranteed to see the
    same copy of a memory location for accesses of any memory type or cacheability
    attribute. In many cases this is effectively the main system memory, although
    the architecture does not prohibit the implementation of caches beyond the PoC
    that have no effect on the coherency between memory system agents.

    > 在所有能够访问内存的代理进行任何类型或缓存属性的访问时，能够保证它们看到同
    > 一个内存位置的相同副本的那个点。在许多情况下，这实际上就是主系统内存，尽管
    > 体系结构并不禁止在 PoC（一致性点）之后实现不会影响内存系统各代理之间一致性
    > 的缓存。

    > Note
    >
    > The presence of system caches can affect the determination of the point of
    > coherency as described in System level caches.
    >
    >> 系统缓存的存在可能会影响一致性点（point of coherency）的确定，这一点在“系
    >> 统级缓存”部分有详细描述。

  + Point of Physical Aliasing (PoPA)

    The point at which updates to one memory location of a Resource are visible
    to all other memory locations of that Resource, for accesses to that point
    of any memory type or cacheability attribute, for all agents that can access
    memory. The relationship between the PoPA and the PoC is such that a clean
    of a written memory location to the PoPA means that no agent in the system
    can subsequently reveal an old value of the memory location by performing an
    invalidate operation to the PoC.

    > 在系统中，某个资源的一个内存位置的更新，对于该资源的所有其他内存位置，在所
    > 有能够访问内存的代理以任意内存类型或缓存属性进行访问时，都可以被看到的那个
    > 点。PoPA（物理地址点）与 PoC（一致性点）之间的关系在于：如果将已写入的内存
    > 位置清理到 PoPA，那么系统中任何代理随后通过在 PoC 执行失效操作，都无法再获
    > 取该内存位置的旧值。

  + Point of Encryption (PoE)

    The point in the memory system where any write that has reached that point
    is encrypted with the context associated with the MECID that is associated
    with that write. Cache maintenance operations to the PoPA are sufficient to
    affect all caches before the PoE.

    > 在内存系统中，任何到达该点的写入操作都会使用与该写入操作相关联的 MECID 上
    > 下文进行加密。对 PoPA 进行的缓存维护操作足以影响 PoE 之前的所有缓存。

  + Point of Unification (PoU)

    The PoU for a PE is the point by which the instruction and data caches and
    the translation table walks of that PE are guaranteed to see the same copy
    of a memory location. In many cases, the Point of Unification is the point
    in a uniprocessor memory system by which the instruction and data caches and
    the translation table walks have merged.

    The PoU for an Inner Shareable shareability domain is the point by which the
    instruction and data caches and the translation table walks of all the PEs
    in that Inner Shareable shareability domain are guaranteed to see the same
    copy of a memory location. Defining this point permits self-modifying
    software to ensure future instruction fetches are associated with the
    modified version of the software by using the standard correctness policy of:

    1. Clean data cache entry by address.
    2. Invalidate instruction cache entry by address.
