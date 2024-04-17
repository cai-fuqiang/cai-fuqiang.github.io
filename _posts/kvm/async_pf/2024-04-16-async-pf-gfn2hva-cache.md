---
layout: post
title:  "async pf -- gfn2hva cache"
author: fuqiang
date:   2024-04-16 15:00:00 +0800
categories: [kvm,async_pf]
tags: [para_virt]
---

<!-- > [least mail list of this patch][]-->

## introduce

该功能仅通过name就可以得知, 是为了缓存gfn(gpa)到hva的映射. 但是这个映射关系
不是一直存在么, 为什么设计看似比较复杂的机制, 我们一步步来看

### user memory region support

我们知道,在比较早期的版本, kvm 创建memslot API
```
kvm_vm_ioctl
  KVM_SET_USER_MEMORY_REGION
```

就已经支持了对 user memory region申请的支持.

> 涉及patch
> 
> Patch: [KVM: Support assigning userspace memory to the guest](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=6fc138d2278078990f597cb1f62fde9e5b458f96)
>
> mail list: [mail](https://lore.kernel.org/all/1198421495-31481-28-git-send-email-avi@qumranet.com/)
>
> 这里只展示下, 用户态入参的数据结构:
>
> ```diff
> +/* for KVM_SET_USER_MEMORY_REGION */
> +struct kvm_userspace_memory_region {
> +       __u32 slot;
> +       __u32 flags;
> +       __u64 guest_phys_addr;
> +       __u64 memory_size; /* bytes */
> +       __u64 userspace_addr; /* start of the userspace allocated memory */
> +};
> ```
> 可以看到最后一个参数为, userspace_addr
{: .prompt-tip}


在该接口的支持下, qemu为guest申请memory region同时, 该内存也作为qemu进程的 anon memory
space 存在, qemu 可以通过管理匿名页的方式, 对该地址空间进行管理, kernel其他组建, 也可以
通过操作这部分匿名页来操作guest memory, 例如: memory reclaim, memory migrate...

所以基本流程是: 
* guest先通过mmap申请匿名内存空间, 调用完成后, kernel已经申请好了这段内存空间的
  virtual base address(`userspace_addr`)
* 调用`kvm_vm_ioctl -- KVM_SET_USER_MEMORY_REGION` 执行完成时, kvm 已经建立起了 `hva->gpa`映射
  关系
* guest访问gpa, 触发EPT violation trap kvm, kvm 调用 get_user_page() 申请page, 并建立`hva->hpa` 
  同时, 创建`gpa->hpa`的mmu pgtables(if guest enable EPT feature, is ept pgtable)

### re-set memory region

所以, 既然两者在set memory region 接口中就已经确立了映射关系, 那是不是只是保存下[hva, gpa]
就相当于cache了.

大部分情况下是这样, 但是在下面情况下, hva->gpa的映射关系会改变

1. guest call `kvm_vm_ioctl -- KVM_SET_USER_MEMORY_REGION`, map `[hva->gpa]->[hpa_1, gpa]`
2. guest call `kvm_vm_ioctl -- KVM_SET_USER_MEMORY_REGION` again, remap `[hva->gpa]->[hpa_2, gpa]`

在这种情况下, 映射关系就改变了.


所以, 我们需要一个机制, 在re-set memory region 发生之后, 我们再次 "access this cache"时, 需要
"invalidate this cache", 这就是该patch要做的事情.

## patch 细节

### change of struct 

```diff
 struct kvm_memslots {
 	int nmemslots;
+	u32 generation;
 	struct kvm_memory_slot memslots[KVM_MEMORY_SLOTS +
 					KVM_PRIVATE_MEM_SLOTS];
 };
```
* **generation**: 表示当前memslots 的generation, 也就是latest.

```diff
+struct gfn_to_hva_cache {
+	u32 generation;
+	gpa_t gpa;
+	unsigned long hva;
+	struct kvm_memory_slot *memslot;
+};
```
* **generation**: 获取cache时, memslots的`generation`, 可能是old的.
* **memslot**: 当前gpa所属的`memslot`, 主要用于 `mark_page_dirty`
  > 作者在这里有个小心思, 因为这个地方没有该成员也没有关系, 也可以执行, 
  > `mark_page_dirty`, 但是在执行时, 需要每次获取`memslot`, 所以作者想了,
  > 既然缓存, 那为什么不缓存多一些, 将`memslot`也缓存
  {:.prompt-tip}

### interface

#### cache init
```diff
+int kvm_gfn_to_hva_cache_init(struct kvm *kvm, struct gfn_to_hva_cache *ghc,
+			      gpa_t gpa)
+{
+	struct kvm_memslots *slots = kvm_memslots(kvm);
+	int offset = offset_in_page(gpa);
+	gfn_t gfn = gpa >> PAGE_SHIFT;
+
+	ghc->gpa = gpa;
+	//==(1)==
+	ghc->generation = slots->generation;
+	ghc->memslot = __gfn_to_memslot(kvm, gfn);
+	ghc->hva = gfn_to_hva_many(ghc->memslot, gfn, NULL);
+	//==(2)==
+	if (!kvm_is_error_hva(ghc->hva))
+		ghc->hva += offset;
+	else
+		return -EFAULT;
+
+	return 0;
+}
```
1. 将此时`slots->generation`赋值给`ghc->generation`
2. 错误情况暂时不看.

#### write cache
```diff
+int kvm_write_guest_cached(struct kvm *kvm, struct gfn_to_hva_cache *ghc,
+			   void *data, unsigned long len)
+{
+	struct kvm_memslots *slots = kvm_memslots(kvm);
+	int r;
+
+	//==(1)==
+	if (slots->generation != ghc->generation)
+		kvm_gfn_to_hva_cache_init(kvm, ghc, ghc->gpa);
+	
+	if (kvm_is_error_hva(ghc->hva))
+		return -EFAULT;
+
+	//==(2)==
+	r = copy_to_user((void __user *)ghc->hva, data, len);
+	if (r)
+		return -EFAULT;
+	//==(3)==
+	mark_page_dirty_in_slot(kvm, ghc->memslot, ghc->gpa >> PAGE_SHIFT);
+
+	return 0;
+}
```
1. 如果`slots->generation` 和当前cache generation(`ghc->generation`)不一致, 
   说明 该cache已经是stale的了, 需要update, 那就直接重新init cache(调用
	`kvm_gfn_to_hva_cache_init()`)
2. 将数据写入hva
3. 该接口是新增的, 为`mark_page_dirty()`的变体.

   ```diff
   -void mark_page_dirty(struct kvm *kvm, gfn_t gfn)
   +void mark_page_dirty_in_slot(struct kvm *kvm, struct kvm_memory_slot *memslot,
   +			     gfn_t gfn)
    {
   -	struct kvm_memory_slot *memslot;
   -
   -	memslot = gfn_to_memslot(kvm, gfn);
    	if (memslot && memslot->dirty_bitmap) {
    		unsigned long rel_gfn = gfn - memslot->base_gfn;
    
   @@ -1284,6 +1325,14 @@ void mark_page_dirty(struct kvm *kvm, gfn_t gfn)
    	}
    }
    
   +void mark_page_dirty(struct kvm *kvm, gfn_t gfn)
   +{
   +	struct kvm_memory_slot *memslot;
   +
   +	memslot = gfn_to_memslot(kvm, gfn);
   +	mark_page_dirty_in_slot(kvm, memslot, gfn);
   +}
   ```

   该变体较`mark_page_dirty()`来说, 主要是增加`memslot`参数. 原因在介绍数据结构的时候
   已经说明
   > 该功能和`dirty log`功能相关, guest可以通过bitmap知道那些page是dirty的,在热迁移
   > 的时候会用到, 这里不过多介绍
   {: .prompt-tip}

那`slots->generation` 什么时候改变的呢

### bump slots->generation

```diff
diff --git a/virt/kvm/kvm_main.c b/virt/kvm/kvm_main.c
index db58a1b..45ef50c 100644
--- a/virt/kvm/kvm_main.c
+++ b/virt/kvm/kvm_main.c
int __kvm_set_memory_region(struct kvm *kvm,
                            struct kvm_userspace_memory_region *mem,
                            int user_alloc)
{
skip_lpage:
  //==(1)==
  if (!npages) {
    r = -ENOMEM;
    slots = kzalloc(sizeof(struct kvm_memslots), GFP_KERNEL);
    if (!slots)
      goto out_free;
    memcpy(slots, kvm->memslots, sizeof(struct kvm_memslots));
    if (mem->slot >= slots->nmemslots)
      slots->nmemslots = mem->slot + 1;
+		slots->generation++;
    slots->memslots[mem->slot].flags |= KVM_MEMSLOT_INVALID;
    
    old_memslots = kvm->memslots;
    rcu_assign_pointer(kvm->memslots, slots);
    synchronize_srcu_expedited(&kvm->srcu);
    /* From this point no new shadow pages pointing to a deleted
     * memslot will be created.
     *
     * validation of sp->gfn happens in:
     *      - gfn_to_hva (kvm_read_guest, gfn_to_pfn)
     *      - kvm_is_visible_gfn (mmu_check_roots)
     */
    kvm_arch_flush_shadow(kvm);
    kfree(old_memslots);
  }
  //==(2)==
  r = kvm_arch_prepare_memory_region(kvm, &new, old, mem, user_alloc);
  if (r)
    goto out_free;
  
  /* map the pages in iommu page table */
  if (npages) {
    r = kvm_iommu_map_pages(kvm, &new);
    if (r)
      goto out_free;
  }
  
  r = -ENOMEM;
  slots = kzalloc(sizeof(struct kvm_memslots), GFP_KERNEL);
  if (!slots)
    goto out_free;
  memcpy(slots, kvm->memslots, sizeof(struct kvm_memslots));
  if (mem->slot >= slots->nmemslots)
    slots->nmemslots = mem->slot + 1;
+ slots->generation++;


```
1. 说明不是内存, 有可能是mmio, 这里变动memslots, 需要使用rcu机制,
   这样可以保证在无锁的情况下把这个动作完成
2. normal 内存

因为更新到了memslots, 说明`hva->gpa`的关系有改变, 所以需要更新`generation`


## history of change

* avi在[Re: \[PATCH v2 02/12\] Add PV MSR to enable asynchronous page faults delivery.][v2_avi_re_add_pv_msr] 中提到, 
  目前这一版本patch可能在遇到 memslots 情况下, 会有问题
  <details markdown="1" open>
  <summary>原文</summary>
  ```diff
  > +static int kvm_pv_enable_async_pf(struct kvm_vcpu *vcpu, u64 data)
  > +{
  > +	u64 gpa = data&  ~0x3f;
  > +	int offset = offset_in_page(gpa);
  > +	unsigned long addr;
  > +
  > +	addr = gfn_to_hva(vcpu->kvm, gpa>>  PAGE_SHIFT);
  > +	if (kvm_is_error_hva(addr))
  > +		return 1;
  > +
      //只初始化一次
  > +	vcpu->arch.apf_data = (u32 __user*)(addr + offset);
  > +
  > +	/* check if address is mapped */
  > +	if (get_user(offset, vcpu->arch.apf_data)) {
  > +		vcpu->arch.apf_data = NULL;
  > +		return 1;
  > +	}
  >    
  
  What if the memory slot arrangement changes?  This needs to be 
  revalidated (and gfn_to_hva() called again).

  > validate <==> invalidate
  > revalidate : 重新生效, 重新验证
  ```
* 在[\[PATCH v3 07/12\] Maintain memslot version number][v3_maintain_memslot_ver]和
  [\[PATCH v3 08/12\] Inject asynchronous page fault into a guest if page is swapped out.][v3_inject_async_pf]
  中, 作者引入了该功能, 不过该功能是嵌入到async pf 功能中, 并非独立接口

  <details markdown="1" open="1">
  <summary>代码</summary>

  ```diff
  diff --git a/include/linux/kvm_host.h b/include/linux/kvm_host.h
  index 600baf0..3f5ebc2 100644
  --- a/include/linux/kvm_host.h
  +++ b/include/linux/kvm_host.h
  @@ -163,6 +163,7 @@ struct kvm {
   	spinlock_t requests_lock;
   	struct mutex slots_lock;
   	struct mm_struct *mm; /* userspace tied to this vm */
  +	u32 memslot_version;
   	struct kvm_memslots *memslots;
   	struct srcu_struct srcu;
  @@ -364,7 +364,9 @@ struct kvm_vcpu_arch {
   	unsigned long singlestep_rip;
   
   	u32 __user *apf_data;
  +	u32 apf_memslot_ver;
   	u64 apf_msr_val;
  +	u32 async_pf_id;
   };
  +static int apf_put_user(struct kvm_vcpu *vcpu, u32 val)
  +{
  +	if (unlikely(vcpu->arch.apf_memslot_ver !=
  +		     vcpu->kvm->memslot_version)) {
  +		u64 gpa = vcpu->arch.apf_msr_val & ~0x3f;
  +		unsigned long addr;
  +		int offset = offset_in_page(gpa);
  +
  +		addr = gfn_to_hva(vcpu->kvm, gpa >> PAGE_SHIFT);
  +		vcpu->arch.apf_data = (u32 __user*)(addr + offset);
  +		if (kvm_is_error_hva(addr)) {
  +			vcpu->arch.apf_data = NULL;
  +			return -EFAULT;
  +		}
  +	}
  +
  +	return put_user(val, vcpu->arch.apf_data);
  +}
  ```
  可以看到, 相当于引入了两个version, 并在`apf_put_user()`时,比对两个version.
  </details>

* 作者在[Re: \[PATCH v4 08/12\] Inject asynchronous page fault into a guest if page is swapped out.][v4_author_ack_why_not_use_kvm_write_guest]
  回答了为什么不使用`kvm_write_guest`
  + Q: why
  + A: want to cache gfn_to_hva_translation
* avi 在[Re: \[PATCH v5 08/12\] Inject asynchronous page fault into a guest if page is swapped out.][v5_avi_suggest_provide_outside_interface]
  建议将该功能剥离, 因为这个功能很好,其他代码也可以用.

  <details markdown="1" open>
  <summary>原文</summary>

  ```
  This nice cache needs to be outside apf to reduce complexity for 
  reviewers and since it is useful for others.
  
  Would be good to have memslot-cached kvm_put_guest() and kvm_get_guest().
  ```
  </details>

* 作者在[Re: \[PATCH v5 08/12\] Inject asynchronous page fault into a guest if page is swapped out.][v5_author_first_complete_this_interface]
  首次提供该接口.

* Marcelo Tosatti 在[Re: \[PATCH v6 04/12\] Add memory slot versioning and use it to provide fast guest write interface][mtosatti_improve_some_details]
  提到两个问题:
  + 在`kvm_gfn_to_hva_cache_init`中使用`gfn_to_memslot` 获取memslot, 可能会造成如下问题
    <details markdown="1" open>
    <summary>自己的理解</summary>

    ```
    thread1                             thread2                          guest
    kvm_write_guest_cached
     kvm_gfn_to_hva_cache_init {        __kvm_set_memory_region
         slots = kvm_memslots(kvm) {
         rcu_dereference_check
       }
       ghc->generation = 
              slots->generation;
                                         slots->generation++;
       ghc->memslot = 
              gfn_to_memslot(
                  slots, gfn) {
         rcu_dereference_check {
           //may have a gp
                                         rcu_assign_pointer(
                                            kvm->memslots, slots);
         }
       ghc->hva = gfn_to_hva_many(
          ghc->memslot, gfn, NULL);
     }
    copy_to_user();

                                         kvm_arch_commit_memory_region
                                            do_munmap
                                                                         access apf 
                                                                         reason, 
                                                                            LOSS
    ```
    这样可能会导致在这个函数中, 前面和后面获取的信息来自于不同的memslots, 个人认为, 不仅仅是这样, 
    还可能导致, thread2 因为中间释放了rcu, 导致其流程和thread1有race, 最终导致 本次`copy_to_user()`
    数据丢失
    
    作者在下一版patch中将`gfn_to_memslot`修改为了`__gfn_to_memslot`, 该接口不会在使用`rcu_dereference_check`
    </details>

[v2_avi_re_add_pv_msr]: https://lore.kernel.org/all/4B0D23E8.3060508@redhat.com/
[v3_add_pv_msr]: https://lore.kernel.org/all/1262700774-1808-3-git-send-email-gleb@redhat.com/
[v3_maintain_memslot_ver]: https://lore.kernel.org/all/1262700774-1808-8-git-send-email-gleb@redhat.com/
[v3_inject_async_pf]: https://lore.kernel.org/all/1262700774-1808-9-git-send-email-gleb@redhat.com/

[v4_author_ack_why_not_use_kvm_write_guest]: https://lore.kernel.org/all/20100708180525.GA11885@redhat.com/
[v5_avi_suggest_provide_outside_interface]: https://lore.kernel.org/all/4C729F10.40005@redhat.com/

[v5_author_first_complete_this_interface]:https://lore.kernel.org/all/20100824122844.GA10499@redhat.com/
[mtosatti_improve_some_details]: https://lore.kernel.org/all/20101005165738.GA32750@amt.cnet/
