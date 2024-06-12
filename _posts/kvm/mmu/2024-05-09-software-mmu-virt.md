---
layout: post
title:  "software mmu virtualization"
author: fuqiang
date:   2024-05-09 20:30:00 +0800
categories: [kvm,mmu]
tags: [virt]
---

{% include link/kvm_link.md %}

## abstract

Soft mmu 又称影子页表, 该实现方式是, 在guest memory 之外, 另外
维护一套pgtables -- shadow pgtable, 在 VM entry 之前, 将guest CR3 指向
shadow pgtable root. 所以, 这种方式, 有点像 TLB , 又有些不同. 我们
来看下: 

* 相同之处

  在guest看来, "CPU" 实际进行translation 时, 使用的可能是 "TLB"(shadow 
  pgtable), 而不一定是 memory pgtable. 所以两者都是在 memory 之外, 另外
  保存了一份 用于 translation 的副本.

* 不同之处.

  TLB 中保存的信息, 和memory pgtables 中所含有的信息 基本是 一致的. 而shadow
  pgtables 的作用就是 基于guest pgtables 更改掉一部分信息(E.g, 最常见的 PFN, 
  将GPA->对应的HPA).

我们将在本文章中, 详细描述关于host是如何根据guest memory pgtables 创建 shadow 
pgtable.

另外所有的 cache , 都面临一个问题, 那就是 如何和memory 之间保持 sync. KVM mmu 也是
在这一方面做了大量的优化, 演进出几个版本,  我们在后面列举出这些实现, 并分析其后续版本
的有点.

## 具体实现 -- base org patch

[KVM org patch][kvm_org_patch_mail_list]

### struct

在x86架构下, cpu有不同的model, 对应的mmu的行为也不同, 如下

* real mode && protect mode nopaging
* 32-bit paging
* PAE paging
* 4-level paging and 5-level paging (64 bit paging)

所以, 我们需要对每个vcpu 维护其mmu的状态:

#### kvm_vcpu

```cpp
struct kvm_vcpu {
        ...
        struct list_head free_pages;
        struct kvm_mmu_page page_header_buf[KVM_NUM_MMU_PAGES];
        struct kvm_mmu mmu;
        ...
};
```

* **free_pages**: 串联所有的free 的 `kvm_mmu_page`
* **page_header_buf[]**: 该数组存放所有的 `kvm_mmu_page`

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

####  kvm_mmu_page

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

### init mmu
上面提到过, cpu 处于不同的model, 对应的mmu的行为不一样.
所以需要去捕获guest cpu model的转换, 然后对 mmu 做一些
初始化工作.
```cpp
int kvm_mmu_reset_context(struct kvm_vcpu *vcpu)
{
        destroy_kvm_mmu(vcpu);
        return init_kvm_mmu(vcpu);
}

static int init_kvm_mmu(struct kvm_vcpu *vcpu)
{
        ASSERT(vcpu);
        ASSERT(!VALID_PAGE(vcpu->mmu.root_hpa));

        if (!is_paging(vcpu))
                return nonpaging_init_context(vcpu);
        else if (kvm_arch_ops->is_long_mode(vcpu))
                return paging64_init_context(vcpu);
        else if (is_pae(vcpu))
                return paging32E_init_context(vcpu);
        else
                return paging32_init_context(vcpu);
}
```
流程大致是, 销毁之前的mmu, 然后根据当前cpu所处的模式
重新初始化.

调用者:
```
set_cr0
set_cr4
kvm_dev_ioctl_set_memory_region
kvm_dev_ioctl_set_sregs
```

* `set cr0 / cr4`: 对guest set cr0 /cr4 行为的捕获, 设置这两个
  寄存器可能导致cpu 寻址方式的改变.
* `kvm_dev_ioctl_set_memory_region`: 设置memory region, 这里可能导致GPA->HPA映射关系
  改变, 所以需要reset mmu.
* `kvm_dev_ioctl_set_sregs`: 该函数可能会设置cr0, cr3, cr4

我们以 `paging32_init_context` 为例, 该函数会设置`kvm_mmu`数据结构的各个成员:
```cpp
static int paging32_init_context(struct kvm_vcpu *vcpu)
{
        struct kvm_mmu *context = &vcpu->mmu;
        //==(1)==
        context->new_cr3 = paging_new_cr3;
        //==(1.1)==
        context->page_fault = paging32_page_fault;
        context->inval_page = paging_inval_page;
        //==(1.2)==
        context->gva_to_gpa = paging32_gva_to_gpa;
        context->free = paging_free;
        //==(2)==
        context->root_level = PT32_ROOT_LEVEL;
        //==(3)==
        context->shadow_root_level = PT32E_ROOT_LEVEL;
        //==(4)==
        context->root_hpa = kvm_mmu_alloc_page(vcpu, NULL);
        ASSERT(VALID_PAGE(context->root_hpa));
        //==(5)==
        kvm_arch_ops->set_cr3(vcpu, context->root_hpa |
                    (vcpu->cr3 & (CR3_PCD_MASK | CR3_WPT_MASK)));
        return 0;
}
```

1. 这部分主要是设置各个callback
2. root_level设置为`PT32_ROOT_LEVEL` (2), 表示guest pgtable root level 为2
3. root_level设置为`PT32E_ROOT_LEVEL` (3), 表示shadow pgtable root level 为3,

   <details markdown=1 open>
   <summary>细节</summary>

   请看 `KVM_PMODE_VM_CR4_ALWAYS_ON`(`KVM_PMODE_VM_CR4_ALWAYS_ON`也一样), 
   总是会设置 `CR4_PAE_MASK`,  另外在 commit(56b321f9e3 "KVM: x86/mmu: 
   simplify and/or inline computation of shadow MMU roles")中新增了一条注释:
   ```
   KVM uses PAE paging whenever the guest isn't using 64-bit paging.
   ```

   大概的意思是当guest 不是64-bit paging 总是会使用PAE paging.

   > WHY?
   >
   > 我们需要想下 PAE paging 的特点
   >
   > PAE paging 扩展了物理内存寻址空间, 是 32-bit mode 下能够具有64 bit
   > 寻址能力(目前物理地址空间最大为52-bit). 如果不使能PAE, 32-bit paging guest
   > 寻址的物理地址只能在4gb以下, 也就是 `GFP_DMA32`, 这显然是不合理的. 而使能了
   > PAE 之后, 就可以为guest 分配任意物理地址.
   {: .prompt-tip}

   </details>
4. 分配 root level pgtable
5. 设置cr3 为 刚刚分配的 root level pgtable

我们需要注意(1.1), (1.2) 部分的回调, 以`paging32`开头, 如果直接搜这个函数是搜不到的.
内核以模板头文件的方式构造了这些函数. 具体实现见`paging_tmpl.h`

<details markdown=1 open>

<summary>paging_tmpl.h模板文件使用</summary>

在 `drivers/kvm/mmu.c`中, 定义了如下代码:
```cpp
#define PTTYPE 64
#include "paging_tmpl.h"
#undef PTTYPE

#define PTTYPE 32
#include "paging_tmpl.h"
#undef PTTYPE
```

在`paging_tmpl.h`中会根据 PTTYPE的值定义一些宏:

<details markdown=1 open>
<summary>具体宏定义</summary>

```cpp
#if PTTYPE == 64
        #define pt_element_t u64
        #define guest_walker guest_walker64
        #define FNAME(name) paging##64_##name
        #define PT_BASE_ADDR_MASK PT64_BASE_ADDR_MASK
        #define PT_DIR_BASE_ADDR_MASK PT64_DIR_BASE_ADDR_MASK
        #define PT_INDEX(addr, level) PT64_INDEX(addr, level)
        #define SHADOW_PT_INDEX(addr, level) PT64_INDEX(addr, level)
        #define PT_LEVEL_MASK(level) PT64_LEVEL_MASK(level)
        #define PT_PTE_COPY_MASK PT64_PTE_COPY_MASK
        #define PT_NON_PTE_COPY_MASK PT64_NON_PTE_COPY_MASK
#elif PTTYPE == 32
        #define pt_element_t u32
        #define guest_walker guest_walker32
        #define FNAME(name) paging##32_##name
        #define PT_BASE_ADDR_MASK PT32_BASE_ADDR_MASK
        #define PT_DIR_BASE_ADDR_MASK PT32_DIR_BASE_ADDR_MASK
        #define PT_INDEX(addr, level) PT32_INDEX(addr, level)
        #define SHADOW_PT_INDEX(addr, level) PT64_INDEX(addr, level)
        #define PT_LEVEL_MASK(level) PT32_LEVEL_MASK(level)
        #define PT_PTE_COPY_MASK PT32_PTE_COPY_MASK
        #define PT_NON_PTE_COPY_MASK PT32_NON_PTE_COPY_MASK
#else
        #error Invalid PTTYPE value
#endif
```
</details>

然后各个函数名也是使用 `FNAME()` 宏定义包裹
* FNAME(page_fault)
  - paging32_page_fault
  - paging64_page_fault
* FNAME(gva_to_gpa)
  - paging32_gva_to_gpa
  - paging64_gva_to_gpa
</details>

关于 kvm mmu init 的代码流程大致介绍完, 下面主要介绍 kvm mmu page 的创建过程.

### kvm mmu page create

创建过程大致如下:
* In guest mode, MMU walk shadow pgtable, broken. Trigger #PF causing VM-exit.
* According to VM exit reason, call handle_exception()
* Execute the following actions
  ```
  handle_exception
    vcpu->mmu.page_fault() -- FNAME(page_fault)
      FNAME(init_walker)
      FNAME(fetch)
        kvm_mmu_alloc_page
        FNAME(set_pde)/FNAME(set_pte)
  ```

* init_walker: walker的数据结构是， guest_walker 定义如下, 作用是guest walk pgtable

  <details markdown=1 open>
  <summary>struct guest worker</summary>
  ```cpp
  struct guest_walker {
          int level;                      //the CURRENT level of guest walker
          pt_element_t *table;            //the pgtable of the level, and mask some
                                          //guest bit of CR3_FLAGS_MASK
  
          pt_element_t inherited_ar;      /* see intel sdm 4.10.2.2 "Caching Translations
                                           * in TLBs", inherited_ar like certain permission
                                           * attributes in TLBs entries, calculated by all
                                           * level pgtable entries to execute logical-AND/OR.
                                           *
                                           * why we only need to  pay attention to R/W && U/S
                                           * flags(see FNAME(init_walker) for more information)
                                           * because we need to use these bits during the page
                                           * fault to handle page faults reasonably.(see
                                           * FNAME(page_fault) for more information. Saving this
                                           * information will prevent us from walking the guest
                                           * page table again.
                                           */
  };
  ```
  </details>

  > NOTE
  > 
  > 这里我们想下遍历guest walker 所需获取的信息。其是mmu page 包含的信息，和TLB很像。我们可以从
  > intel sdm `4.10.2.2 Caching Translations in TLBs` 中得到这些信息:
  > * The physical address corresponding to the page number (the page frame).
  > * The access rights from the paging-structure entries used to translate linear
  >   addresses with the page number
  >   - R/W
  >   - U/S
  > * Attributes from a paging-structure entry that identifies the final page frame for the page
  >   number (either a PTE or a paging-structure entry in which the PS flag is 1):
  >
  > TLB是将这些信息集中在一条TLB entry中，HARDWARE MMU 只需要通过这一条TLBs, 就可以获取到该
  > translation 的相关信息。
  >
  > 而在shadow pgtable中:
  > * PFN: 这个不用说，肯定是位于last level pgtable
  > * R/W, U/S access right: 这些和TLB比较类似， 是经过all level pgtable Logical-AND 运算得到。
  >   主要是这些bit有特殊用途。在host 捕获 #PF 时， 可能需要获取这些数据， 保存在last level pgtable,
  >   可以避免再次 walking guest pgtable. 我们接下来会看在什么情况下，会读取这两个access right
  {: .prompt-tip}
* fetch: 根据guest pgtable，构建shadow pgtable, 这里包括前几级的pgtable和last level pgtable, 
  如果是last level pgtable, 我们需要设置 page的PFN, 这个page 就是GPA所对应的HPA 所在的页框。
  然后执行FNAME(set_pde)/FNAME(set_pte)

* FNAME(set_pde)/FNAME(set_pte)
  后面会讲到，最初的patch处理大页(PSE)的逻辑，其最终都是设置pte, 只不过根据guest pgtable entry
  中的pfn, 计算 host pfn的方式不同。

* kvm_mmu_alloc_page

  为shadow pgtable分配page.


```cpp

```
