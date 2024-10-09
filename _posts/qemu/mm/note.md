# global var
```cpp
static MemoryRegion *system_memory;
static MemoryRegion *system_io;

AddressSpace address_space_io;
AddressSpace address_space_memory;
```
# struct
## AddressSpace
```cpp
/**
 * struct AddressSpace: describes a mapping of addresses to #MemoryRegion objects
 */
struct AddressSpace {
    /* private: */
    struct rcu_head rcu;
    char *name;
    MemoryRegion *root;

    /* Accessed via RCU.  */
    struct FlatView *current_map;

    int ioeventfd_nb;
    int ioeventfd_notifiers;
    struct MemoryRegionIoeventfd *ioeventfds;
    QTAILQ_HEAD(, MemoryListener) listeners;
    QTAILQ_ENTRY(AddressSpace) address_spaces_link;
};
```
## MemoryRegion
```cpp
struct MemoryRegion {
    ...
    const MemoryRegionOps *ops;
    MemoryRegion *container;
    ...
    hwaddr addr;
};

```

## MemoryRegionSection 
```cpp
struct MemoryRegionSection {
    Int128 size;
    MemoryRegion *mr;
    FlatView *fv;
    hwaddr offset_within_region;
    hwaddr offset_within_address_space;
    bool readonly;
    bool nonvolatile;
    bool unmergeable;
};
``` ## MemoryListener
callbak set
```cpp
begin(MemoryListener *) : 
  在进行address space update trans 之前做, 后续可能会调用
  ->region_add()  ->region_del()  ->region_nop()
  ->log_start()   ->log_stop()

commit(MemoryListener *) :
  在执行完address space update trans 末尾做

region_add(MemoryListener *, MemoryRegionSection *)
  for a section of the address space that is new in this address space
  space since the last transaction.

region_del(MemoryListener *, MemoryRegionSection *)
  for a section of the address space that has disappeared(消失) in the address
  space since the last transaction.

region_nop(MemoryListener *, MemoryRegionSection *)
  for a section of the address space that is in the same place in the address
  space as in the last transaction.

...
```
其他成员
* priority
* address_space
* link
* link_as

# kvm init memory

```sh
kvm_init
  => kvm_memory_listener_register            # 内存空间
     (,&s->memory_listener, &address_space_memory, 0, "kvm-memory")
     => assign listeners member: callbak and others
        { 
          region_add = kvm_region_add
          region_del = kvm_region_del
          commit = kvm_region_commit
          priority = MEMORY_LISTENER_PRIORITY_ACCEL; # 10 very high
          ...
        }
     => memory_listener_register
  => memory_listener_register                # io空间
     (&kvm_io_listener, &address_space_io)
```

# memory_listener_register
```sh
void memory_listener_register(MemoryListener *listener, AddressSpace *as)

=> listeners->address_space = as
=> 链接到memory_listeners 全局list中, 按照priority 从小到大排列
=> 将listeners 链接到 as->listeners 链表中, 同样按照从小到大排列

   => listener_add_address_space(listener, as)
```
这里注册了一个listener, 所以需要执行对该as 的 所有region 进行
`region_add()` update transaction

# listener_add_address_space
```sh
=> listener->begin()
=> if(global_dirty_tracking)  listener->log_global_start()
=> 获取当前 flatview
   {
     address_space_get_flatview()
     => while(!flatview_ref(view))
        view = address_space_to_flatview()
          => qatomic_rcu_read(&as->current_map); 
     # current_map表示当前的flatview, 并且如果有人replace as->current_map,
     # 则as->current_map 返回false, 
     # flatview_ref
     # => qatomic_fetch_inc_nonzero() > 0 atomic_fetch_inc return old value
   }
=> 遍历之前的view, 添加每一个 MemoryRegionSection

     listener->log_stop()
     listener->region_add()
   }
=> listener->commit()
```
# kvm_region_xxx

## kvm_region_add
```sh
=> update = g_new0(KVMMemoryUpdate, 1);
=> update->section = *section;
=> QSIMPLEQ_INSERT_TAIL(&kml->transaction_add, update, next);
```
大概流程是，创建一个`KVMMemoryUpdate`, 并且初始化其section成员，
将其链接到`kml(KVMMemoryListener)->transaction_add`链表上

## kvm_region_del
```sh
=> update = g_new0(KVMMemoryUpdate, 1);
=> update->section = *section;
=> QSIMPLEQ_INSERT_TAIL(&kml->transaction_del, update, next);
```
前面两个操作类似，不过是将其链接到 `kml->transaction_del` 链表上

# kvm_region_commit
该流程主要将 as update transaction 进行commit对于`region_add()`/
`region_del()`来说主要是将 `kml->transaction_del(add)`链表上未
commit的region更新
```sh
=> 首先判断del的range和add的range是否overlaps
   NOTE: 这里算法默认认为两个链表是从小到大排序好的，但是kvm_region_add()
   并没有这个保证
   {
     if (range_overlaps_range(&r1, &r2)) need_inhibit = true; break;
   }
   如果overlap了， 则赋值 need_inhibit, 并如下调用accel_ioctl_inhibit_begin()
=> kvm_slot_lock()
=> if (need_inhibit) accel_ioctl_inhibit_begin() # 作用未知
=> 遍历kml->transaction_del list，对每一个KVMMemoryUpdate 调用kvm_set_phys_mem(,,false)
=> 遍历kml->transaction_del list, 对每一个KVMMemoryUpdate 调用kvm_set_phys_mem(,,true)
=> if (need_inhibit) accel_ioctl_inhibit_end() # 作用未知
```

# 
