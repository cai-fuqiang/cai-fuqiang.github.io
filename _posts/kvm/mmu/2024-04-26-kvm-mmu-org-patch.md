---
layout: post
title:  "kvm mmu org patch"
author: fuqiang
date:   2024-04-26 11:26:00 +0800
categories: [kvm,mmu_note]
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

## userspace interface -- set memory region

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

####  kvm

```cpp
struct kvm {
        spinlock_t lock; /* protects everything except vcpus */
        int nmemslots;
        struct kvm_memory_slot memslots[KVM_MEMORY_SLOTS];
        int memory_config_version;
        ...
};
```

* **lock**: 注释中提到, 可以保护除了vcpu成员之外的所有的程亚u年
* **nmemslots**: 表示当前所有的 memslot 的number
* **memslots**: memslot数组, 共`KVM_MEMORY_SLOTS(4)`
* **memory_config_version**: 表示当前 memslots的version, 每修改一次
  就做一次bump version

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

2. 请注意, 这里会将所有的vcpu 分别执行`vcpu_load()`, `vcpu_put()`, 简单说下这两个
   函数, `vcpu_load()`的作用, 是将`vcpu` 也就是 `VMCS` load 到当前cpu上,也就是
   变为`current`, 这样就可以使用`VMX instruction` -- `VMWRITE`修改VMCS 内容.

   而这里执行`vcpu_load`就是为了在`kvm_mmu_reset_context`中, 完成对VMCS
   某些字段的修改. 我们下面会介绍相关函数.

## KVM MMU -- shadow page table

* Q: 何谓影子页表?
* A: 影子页表就是guest pgtable 的1:1 copy, 但是不是完全的copy, 例如 page/next pgtable
     paddr.

* Q: 为什么会出现影子页表呢?
* A: 因为早期的CPU不支持EPT, 也就是说在VMX non-root operation中, VA->PA 只有一个stage.
     不可能让GUEST 直接访问到GPA. 应该让guest访问到KVM为guest 分配的page. 所以KVM 需要
     重建这个映射.

* Q: 如何实现
* A: 我们主要思考两个问题:
     + guest写入pgtable的地址是GPA, 而kvm分配的地址是HPA. 如何将这两者绑定.

       guest 需要 `GVA->GPA`, 而最终的是否访问到`GPA`, 在guest看来是由hardware mmu
       决定, 对于其来说是透明的. 索性KVM就 重构了这个"hardware mmu"(i.e.,`KVM MMU`), 
       搞了另外一套页表, attr什么的, 能copy直接copy guest pgtable, 但是 页表的pa 部分, 
       全都替换成hpa, 让最终的映射, 映射到为guest 分配好的page 上, 页表准备好了另一套, 
       那么就需要在guest运行时, 指定到这套页表, 咋指定呢? 通过CR3指定到shadow pgtable
       的 root pgtable.

     + guest modify pgtable, 如何通知到kvm

       这个当前版本代码是把`kvm mmu -- shadow pgtable`, 当作了 TLB, 所以就允许了guest如果
       modify pgtable, 可能会造成memory和 "TLB" 不一致的问题. 所以KVM 捕捉guest invlidate
       TLB 的行为, 并在hook中 invlidate 相关的"shadow pgtable"

### data struct

#### kvm_mmu

```cpp
struct kvm_mmu {
        void (*new_cr3)(struct kvm_vcpu *vcpu);
        int (*page_fault)(struct kvm_vcpu *vcpu, gva_t gva, u32 err);
        void (*inval_page)(struct kvm_vcpu *vcpu, gva_t gva);
        void (*free)(struct kvm_vcpu *vcpu);
        gpa_t (*gva_to_gpa)(struct kvm_vcpu *vcpu, gva_t gva);
        hpa_t root_hpa;
        int root_level;
        int shadow_root_level;
};
```
* **root_hpa**: shadow pgtable的root: pgd
* **root_level**: 表示guest pgtable 的 level
* **shadow_root_level**: 表示影子页表的level

#### kvm_mmu_page

每个shadow page table 都由一个 `kvm_mmu_page`维护

```cpp
struct kvm_mmu_page {
        struct list_head link;
        hpa_t page_hpa;
        unsigned long slot_bitmap; /* One bit set per slot which has memory
                                    * in this shadow page.
                                    */
        int global;              /* Set if all ptes in this page are global */
        u64 *parent_pte;
};
```

* **link**: 链接所有的`kvm_mmu_page`
* **page_hpa**: 该shadow page table的`hpa`
* **slot_bitmap**: 表示该shadow page 指向的page 在哪些memslot内
* **global**: 表示该pgtable 中的所有pte 都是 global的.
* **parent_pte**: parent level pte address

#### kvm_vcpu

```cpp
struct kvm_vcpu {
        ...
        struct kvm_mmu_page page_header_buf[KVM_NUM_MMU_PAGES];
        struct kvm_mmu mmu;
        ...
};

```

* **page_header_buf**: 

### init mmu
该函数为`init_kvm_mmu`, 该函数有两类调用路径:
1. `kvm_mmu_reset_context`
   ```
   set_cr0/set_cr4/kvm_dev_ioctl_set_memory_region/kvm_ioctl_set_sregs
     kvm_mmu_reset_context() {
       destroy_kvm_mmu()
       init_kvm_mmu()
     }
   ```
2. `kvm_mmu_init`
   ```
   kvm_dev_ioctl_create_vcpu
     kvm_mmu_init
       init_kvm_mmu
   ```

> 思考下1, 
{: .prompt-tip}
