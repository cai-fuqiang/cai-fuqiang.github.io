---
layout: post
title:  "kvm mmu org patch"
author: fuqiang
date:   2024-04-26 11:26:00 +0800
categories: [kvm,mmu]
tags: [virt]
---
## 简介
我们分析最初引入kvm的一版patch
```
commit 6aa8b732ca01c3d7a54e93f4d701b8aabbe60fb7
Author: Avi Kivity <avi@qumranet.com>
Date:   Sun Dec 10 02:21:36 2006 -0800

    [PATCH] kvm: userspace interface
```

该版patch引入时, intel还不支持EPT, 所以
该patch是根据影子页表的原理设计的,但是
EPT 和 影子页表有一些共同面对的问题,并且在数据
结构上, 也有一些相似之处, 我们来看下

> 在kernel主线上, 只是一个patch, 可能不太好看
> 在
>
> [MAIL LIST: [PATCH 0/14] KVM: Kernel-based Virtual Machine (v4)](https://lore.kernel.org/kvm/454E4941.7000108@qumranet.com/)
>
> 是比较清晰的, 我们很容易找到和内存虚拟化相关的patch代码
> 
> * [\[PATCH 1/14\] KVM: userspace interface](https://lore.kernel.org/kvm/20061105202934.B5F842500A7@cleopatra.q/)
> * [\[PATCH 3/14\] KVM: kvm data structures](https://lore.kernel.org/kvm/20061105203134.DA9FC2500A7@cleopatra.q/)
> * [\[PATCH 6/14\] KVM: memory slot management](https://lore.kernel.org/kvm/20061105203435.2FA912500A7@cleopatra.q/)
> * [\[PATCH 11/14\] KVM: mmu](https://lore.kernel.org/kvm/20061105203935.CAF332500A7@cleopatra.q/)
> 
> 我们主要依据这个代码进行分析

## userspace interface

kvm 是内核的一个模块, 其主要功能是提供一些对memory, cpu, interrupt controller
虚拟化的一些接口, 所以我们这里主要介绍下, 用于memory virtualization的一些
接口

### data struct

#### kvm_memory_region

```cpp
struct kvm_memory_region {
	__u32 slot;
	__u32 flags;
	__u64 guest_phys_addr;
	__u64 memory_size; /* bytes */
};
```

该数据结构是给用户层面的API struct, 用户态负责通过该函数, 描述guest memory
的相关属性.

+ **slot**: 作为 identifier 使用, 用于标记一个memory region
+ **flags**: 最初只引入了 `KVM_MEM_LOG_DIRTY_PAGES`
  ```cpp
  /* for kvm_memory_region::flags */
  #define KVM_MEM_LOG_DIRTY_PAGES  1UL
  ```
+ **guest_phys_addr**: guest 物理地址 GPA
+ **memory_size**: 该memory region 的size

> 这是早期kvm用户态 interface, 后来该struct变动
> 也不大, 在`struct kvm_userspace_memory_region`
> 引入了`userspace_addr`成员, 我们不再本文中介绍
> 该部分改动, 还是分析最初的代码
{: .prompt-info}

#### kvm_memory_slot

```cpp
struct kvm_memory_slot {
        gfn_t base_gfn;
        unsigned long npages;
        unsigned long flags;
        struct page **phys_mem;
        unsigned long *dirty_bitmap;
};
```
该数据结构相当于是用户态通过`kvm_memory_region` 传进来的 `region`, 
在KVM 中的实例. 其包含了`kvm_memory_region`的内容, 同时还包含了
一些成员供KVM管理.

* **base_gfn**: `kvm_memory_region::guest_phys_addr` 的 pfn
* **npages**: `kvm_memory_region::memory_size / PAGE_SIZE`
* **flags**: 
* **phys_mem**: page of guest memory 
* **dirty_bitmap**: 和kvm脏页管理有关, 可以标识guest中哪些page是dirty的

### kvm_dev_ioctl

```cpp
static long kvm_dev_ioctl(struct file *filp,
                          unsigned int ioctl, unsigned long arg)
{ 
        ...
        case KVM_SET_MEMORY_REGION: {
                struct kvm_memory_region kvm_mem;

                r = -EFAULT;
                if (copy_from_user(&kvm_mem, (void *)arg, sizeof kvm_mem))
                        goto out;
                r = kvm_dev_ioctl_set_memory_region(kvm, &kvm_mem);
                if (r)
                        goto out;
                break;
        }
        ...
 
```
> NOTE
>
> 这里代码路径是 `kvm_dev_ioctl()`, 是因为memory是作为整个虚拟机的管理对象,
> 而非一个vcpu的.

该函数从用户空间copy数据结构`kvm_memory_region`, 然后调用`kvm_dev_ioctl_set_memory_region`,
我们主要看下该函数

### kvm_dev_ioctl_set_memory_region


#### part1 -- param check
```cpp
static int kvm_dev_ioctl_set_memory_region(struct kvm *kvm,
                                           struct kvm_memory_region *mem)
{
        int r;
        gfn_t base_gfn;
        unsigned long npages;
        unsigned long i;
        struct kvm_memory_slot *memslot;
        struct kvm_memory_slot old, new;
        int memory_config_version;

        r = -EINVAL;
        /* General sanity checks */
        //===========(1)================
        if (mem->memory_size & (PAGE_SIZE - 1))
                goto out;
        //===========(2)================
        if (mem->guest_phys_addr & (PAGE_SIZE - 1))
                goto out;
        //===========(3)================
        if (mem->slot >= KVM_MEMORY_SLOTS)
                goto out;
        //===========(4)================
        if (mem->guest_phys_addr + mem->memory_size < mem->guest_phys_addr)
                goto out;

        ...
}
```

该函数前半部分主要是在做一些参数的合法性检查, 主要包括:
1. `kvm_memory_region->memory_size` 必须是 PAGE_SIZE 对齐
2. `kvm_memory_region->guest_phys_addr` 必须是 PAGE_SIZE 对齐
3. `kvm_memory_region->slot` identifier 不能超过最大值 `KVM_MEMORY_SLOTS`
   ```cpp
   #define KVM_MEMORY_SLOTS 4
   ```
4. 这里实际上是判断 `mem->guest_phys_addr + mem->memory_size` 不能溢出


#### part2 -- init memory slot && check  overlaps

```cpp
static int kvm_dev_ioctl_set_memory_region(struct kvm *kvm,
                                           struct kvm_memory_region *mem)
{
        //===========(1)================
        memslot = &kvm->memslots[mem->slot];
        base_gfn = mem->guest_phys_addr >> PAGE_SHIFT;
        npages = mem->memory_size >> PAGE_SHIFT;

        if (!npages)
                mem->flags &= ~KVM_MEM_LOG_DIRTY_PAGES;


        //===========(2.1)================
raced:
        spin_lock(&kvm->lock);

        //===========(2.2)================
        memory_config_version = kvm->memory_config_version;
        new = old = *memslot;

        new.base_gfn = base_gfn;
        new.npages = npages;
        new.flags = mem->flags;

        /* Disallow changing a memory slot's size. */
        r = -EINVAL;
        //===========(3)================
        if (npages && old.npages && npages != old.npages)
                goto out_unlock;

        /* Check for overlaps */
        r = -EEXIST;
        //===========(4)================
        for (i = 0; i < KVM_MEMORY_SLOTS; ++i) {
                struct kvm_memory_slot *s = &kvm->memslots[i];

                if (s == memslot)
                        continue;
                if (!((base_gfn + npages <= s->base_gfn) ||
                      (base_gfn >= s->base_gfn + s->npages)))
                        goto out_unlock;
        }
        /*
         * Do memory allocations outside lock.  memory_config_version will
         * detect any races.
         */
        spin_unlock(&kvm->lock);

        /* Deallocate if slot is being removed */
        if (!npages)
                new.phys_mem = 0;

        /* Free page dirty bitmap if unneeded */
        if (!(new.flags & KVM_MEM_LOG_DIRTY_PAGES))
                new.dirty_bitmap = 0;
        ...
}
```
1. 从用户态入参中获取 memslot attr
2. 该函数是可重入的, 为了避免两个线程同时修改memslot, 我们在part4 介绍
3. 可以修改memslot的其他属性, 但是不能修改 memory size
4. 检查该slot 是否和其他的slot 有重叠


#### part3 --alloc memory && alloc dirty_bitmap

```cpp
static int kvm_dev_ioctl_set_memory_region(struct kvm *kvm,
                                           struct kvm_memory_region *mem)
{
        ...
        r = -ENOMEM;
        //===(1)===
        /* Allocate if a slot is being created */
        if (npages && !new.phys_mem) {
                new.phys_mem = vmalloc(npages * sizeof(struct page *));

                if (!new.phys_mem)
                        goto out_free;

                memset(new.phys_mem, 0, npages * sizeof(struct page *));
                for (i = 0; i < npages; ++i) {
                        new.phys_mem[i] = alloc_page(GFP_HIGHUSER
                                                     | __GFP_ZERO);
                        if (!new.phys_mem[i])
                                goto out_free;
                }
        }

        /* Allocate page dirty bitmap if needed */
        if ((new.flags & KVM_MEM_LOG_DIRTY_PAGES) && !new.dirty_bitmap) {
                unsigned dirty_bytes = ALIGN(npages, BITS_PER_LONG) / 8;

                new.dirty_bitmap = vmalloc(dirty_bytes);
                if (!new.dirty_bitmap)
                        goto out_free;
                memset(new.dirty_bitmap, 0, dirty_bytes);
        }

        ...
}
```
1. 说明是第一次对该memslot 创建guest page, 这里需要注意的是, 最终创建分配页
   的接口是 `alloc_page(GFP_HIGHUSER| __GFP_ZERO)`, 并且没有做map, 所以
   该内存实际上不是用户态内存
2. 当flags中有`KVM_MEM_LOG_DIRTY_PAGES`, 同时之前没有创建过. 则为bitmap 申请空间.

#### part 4 -- check for re-entry
```cpp
static int kvm_dev_ioctl_set_memory_region(struct kvm *kvm,
                                           struct kvm_memory_region *mem)
{
        ...
        spin_lock(&kvm->lock);
        //==(1.1)==
        if (memory_config_version != kvm->memory_config_version) {
                spin_unlock(&kvm->lock);
                kvm_free_physmem_slot(&new, &old);
                goto raced;
        }

        r = -EAGAIN;
        if (kvm->busy)
                goto out_unlock;

        if (mem->slot >= kvm->nmemslots)
                kvm->nmemslots = mem->slot + 1;

        *memslot = new;
        //==(1.2)==
        ++kvm->memory_config_version;

        spin_unlock(&kvm->lock);

        //==(2)==
        for (i = 0; i < KVM_MAX_VCPUS; ++i) {
                struct kvm_vcpu *vcpu;

                vcpu = vcpu_load(kvm, i);
                if (!vcpu)
                        continue;
                kvm_mmu_reset_context(vcpu);
                vcpu_put(vcpu);
        }
        kvm_free_physmem_slot(&old, &new);
        return 0;

out_unlock:
        spin_unlock(&kvm->lock);
out_free:
        kvm_free_physmem_slot(&new, &old);
out:
        return r;
}
```
1. 结合 part2 中的(2), 我们可以看到为了防止re-entry 带来的问题, kvm做了如下步骤.
   1. 先获取`memory_config_version` (part2: 2.2)
   2. 初始化局部变量new (part2: 2.2)
   3. 在初始化完全结束后, 再次检查 `memory_config_version`是否被修改过, 
      如果修改过, 需要将new free掉, 将old放回memslot中,再从`raced`处
      重新走一遍.(part4: 1.1)

      这里需要注意, `kvm_free_physmem_slot()` 为什么要传入两个参数呢, 主要是因为,
      old, new他们的指针可能要指向相同的地址, 所以假如要释放new, 那必须要看下
      old中的指针是否和new相同, 如果相同, 其指针指向的memory就不能释放.

      <details markdown=1 open>
      <summary>kvm_free_physmem_slot代码</summary>
      ```cpp
      /*
       * Free any memory in @free but not in @dont.
       */
      static void kvm_free_physmem_slot(struct kvm_memory_slot *free,
                                        struct kvm_memory_slot *dont)
      {
              int i;
              //==(1)==
              if (!dont || free->phys_mem != dont->phys_mem)
                      if (free->phys_mem) {
                              for (i = 0; i < free->npages; ++i)
                                      __free_page(free->phys_mem[i]);
                              vfree(free->phys_mem);
                      }
      
              //==(2)==      
              if (!dont || free->dirty_bitmap != dont->dirty_bitmap)
                      vfree(free->dirty_bitmap);
      
              free->phys_mem = 0;
              free->npages = 0;
              free->dirty_bitmap = 0;
      }
      ```
      memslot有两个指针, `phys_mem` 和 `dirty_bitmap`, 该函数主要是比较`free`
      中的这两个指针是否和`dont`中的相等, 如果相等, 就不释放了.

      </details>
   4. bump version `memory_config_version`(part4: 1.2)

   其中步骤`3, 4`锁在一起. 这样保证了check 和 modify version 是atomic的, 保证
   如果有两方同时修改肯定有一方需要重新走一遍`raced`

2. 请注意, 这里会将所有的vcpu 分别执行`vcpu_load()`, `vcpu_put()`, 这里就不展开
   这两个函数, 
