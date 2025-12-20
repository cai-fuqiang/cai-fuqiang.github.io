---
layout: post
title:  "async pf -- GUP change"
author: fuqiang
date:   2024-04-16 15:00:00 +0800
categories: [kvm,async_pf]
tags: [para_virt]
---

### 参考代码

> 该部分代码, mail list中和commit中内容不同, 而且mail list中也没有提到为什么当时没有全部
> 合入, 我们先以mail list 为准:
>
> [KVM: Add host swap event notifications for PV guest][v7]
>
> 后续, 我们在另一篇文章中详细介绍: [link][2]
>
>> 遗留问题
>{: .prompt-danger}
{: .prompt-warning }


#### get_user_pages_noio

> 该部分代码来自于: [Add get_user_pages() variant that fails if major fault is required.][3]
> 社区并没有合入该patch
{: .prompt-info}

该patch 引入了 `get_user_page()`的noio 版的变体, 他只在不需要 `major fault`的情况下才会
成功的 get page reference

> 以上来自该patch的commit message
>
> ```
> This patch add get_user_pages() variant that only succeeds if getting
> a reference to a page doesn't require major fault.
> ```


具体改动是:

* 增加了新的flow flag和fault flag
  <details open markdown="1">
  <summary>flow/fault flag细节</summary>

  + **flow flag**: 

    该flag会作为`gup_flags`入参传入`__get_user_pages()`, 可以作为一些约束
    e.g., `FOLL_WRITE` 表明要要get的pages必须是可写入的
    > 会对比vma->vm_flags 是否是可写的.
 
    另外, 会在 follow page期间, 影响`handle_mm_fault`的fault flag

    e.g., `FOLL_WRITE`->`FAULT_FLAG_WRITE`

    新增的flag为:
    ```diff
    +#define FOLL_MINOR	0x20	/* do only minor page faults */  
    ```
    表明要在 follow page期间, 只允许处理 minor page fault.(不能处理swapin)

  + **fault flag**: 

    用于`handle_mm_fault()`入参flags, 表明本次`fault`的类型.该参数可以用于一些
    优化和约束.
    
    e.g. 如果检测到没有`FAULT_FLAG_WRITE`, 说明是read access, 而又是第一次建立
    映射, 那么可以建立和zero page的映射

    ```cpp
    do_anonymous_page()
    {
        ...
        if (!(flags & FAULT_FLAG_WRITE)) {
                entry = pte_mkspecial(pfn_pte(my_zero_pfn(address),
                                                vma->vm_page_prot));
                page_table = pte_offset_map_lock(mm, pmd, address, &ptl);
                if (!pte_none(*page_table))
                        goto unlock;
                goto setpte;
        }
        ...
    }
    ```

    新增的flag为:
    ```diff
    +#define FAULT_FLAG_MINOR	0x08	/* Do only minor fault */
    ```
    是由 `FOLL_MINOR`转化而来, 和其作用一样.
  + **vm fault reason**:

    其实, 还有一些flag, 是用于表示`handle_mm_fault()`的原因, 例如这里我们遇到的:
    `VM_FAULT_MAJOR`, 实际上是表明, 该函数返回失败是由于该fault是 major fault.

  </details>

  我们下面会结合代码改动详细看下, 这些flag的应用

* 关于处理这些`"flags"`具体代码流程改动: 

  <details open markdown="1">
  <summary>"flags"具体代码改动</summary>

  + `__get_user_pages`->`handle_mm_fault`

    ```diff
    @@ -1441,10 +1441,13 @@ int __get_user_pages(struct task_struct *tsk, struct mm_struct *mm,
     			cond_resched();
     			while (!(page = follow_page(vma, start, foll_flags))) {
     				int ret;
    +				unsigned int fault_fl =
    +					((foll_flags & FOLL_WRITE) ?
    +					FAULT_FLAG_WRITE : 0) |
    +					((foll_flags & FOLL_MINOR) ?
    +					FAULT_FLAG_MINOR : 0);
     
    -				ret = handle_mm_fault(mm, vma, start,
    -					(foll_flags & FOLL_WRITE) ?
    -					FAULT_FLAG_WRITE : 0);
    +				ret = handle_mm_fault(mm, vma, start, fault_fl);
    ```

    可以看到, 这里会将 `FOLL_WRITE`->`FAULT_FLAG_WRITE`, `FOLL_MINOR`->`FAULT_FLAG_MINOR`
 
  + `do_swap_page`

    ```diff
    @@ -2648,6 +2670,9 @@ static int do_swap_page(struct mm_struct *mm, struct vm_area_struct *vma,
     	delayacct_set_flag(DELAYACCT_PF_SWAPIN);
     	page = lookup_swap_cache(entry);
     	if (!page) {
    +		if (flags & FAULT_FLAG_MINOR)
    +			return VM_FAULT_MAJOR | VM_FAULT_ERROR;
    +
     		grab_swap_token(mm); /* Contend for token _before_ read-in */
     		page = swapin_readahead(entry,
     					GFP_HIGHUSER_MOVABLE, vma, address);
    ```
    如果没有在swap cache中找到, 说明该page 被swap出去, 并且被free了,需要swapin, 这时, 如果有`FAULT_FLAG_MINOR`,
    表明只允许处理 minor fault, 而swapin, 属于 major fault, 不允许处理, 需要返回错误, 同时把错误原因:
    `VM_FAULT_MAJOR`也返回
  + `filemap_fault`

    和swapcache 相对应的还有pagecache
    ```diff
    diff --git a/mm/filemap.c b/mm/filemap.c
    index 3d4df44..ef28b6d 100644
    --- a/mm/filemap.c
    +++ b/mm/filemap.c
    @@ -1548,6 +1548,9 @@ int filemap_fault(struct vm_area_struct *vma, struct vm_fault *vmf)
     			goto no_cached_page;
     		}
     	} else {
    +		if (vmf->flags & FAULT_FLAG_MINOR)
    +			return VM_FAULT_MAJOR | VM_FAULT_ERROR;
    ```
    也是同样的处理逻辑

  + `handle_mm_fault() --return`->`__get_user_pages() --handle retval`

    ```diff
    @@ -1452,6 +1455,8 @@ int __get_user_pages(struct task_struct *tsk, struct mm_struct *mm,
     					if (ret &
     					    (VM_FAULT_HWPOISON|VM_FAULT_SIGBUS))
     						return i ? i : -EFAULT;
    +					else if (ret & VM_FAULT_MAJOR)
    +						return i ? i : -EFAULT;
     					BUG();
    ```
    如果是 `FAULT_MAJOR`并且没有get 到 page, 直接返回错误

  </details>

* 新增`get_user_pages_noio`接口

  ```diff
  +int get_user_pages_noio(struct task_struct *tsk, struct mm_struct *mm,
  +		unsigned long start, int nr_pages, int write, int force,
  +		struct page **pages, struct vm_area_struct **vmas)
  +{
  +	int flags = FOLL_TOUCH | FOLL_MINOR;
  +
  +	if (pages)
  +		flags |= FOLL_GET;
  +	if (write)
  +		flags |= FOLL_WRITE;
  +	if (force)
  +		flags |= FOLL_FORCE;
  +
  +	return __get_user_pages(tsk, mm, start, nr_pages, flags, pages, vmas);
  +}
  +EXPORT_SYMBOL(get_user_pages_noio);
  +
  ```
  不多解释, 在该接口中将`FOLL_MINOR`置位.

> NOTE
> 
> 所以该部分patch的主要作用就是增加了`get_user_pages_noio()`, 使其, 只处理minor fault
> (假如只是alloc page, 那属于minor fault), 但是不能处理major fault.(例如swapin, pagecache
> in)
> > 目前个人理解是这样, 之后还需要看下page fault的相关细节
> {: .prompt-warning}
{: .prompt-tip}

---

我们接下来看下, async pf 框架是如何利用上面`GUP noio`接口的

#### usage of GUP noio in async pf

我们先看下, 触发 async pf 的入口, 我们上面介绍到, 在 EPT violation hook 
中会去start 该work, 过程如下:

##### tdp_page_fault

```diff
@@ -2609,7 +2655,11 @@ static int tdp_page_fault(struct kvm_vcpu *vcpu, gva_t gpa,

    mmu_seq = vcpu->kvm->mmu_notifier_seq;
    smp_rmb();
    //==(1)==
-   pfn = gfn_to_pfn(vcpu->kvm, gfn);
+
    //==(2)==
+   if (try_async_pf(vcpu, gfn, gpa, &pfn))
+       return 0;
+
+   /* mmio */
    if (is_error_pfn(pfn))
```

1. 将现有的`gfn_to_pfn()`, 替换为`try_async_pf()`, 之前的gfn2pfn接口, 是必须async, 也就是
   上面提到的使用GUP时, 可以处理 `MAJOR FAULT`. 而现在替换为了 `try_async_pf()`, 打算尝试
   执行 async pf(也可能不需要, 例如遇到了 `MINOR FAULT`. 我们接下来会详细看下该接口
2. `tdp_page_fault()`中会执行`try_async_pf()`该函数返回值为true, 表示已经做了async pf,
   所以现在还不能去 map GPA->HPA. 需要该接口直接返回. 对于`HALT`的处理方式, 则是让vcpu
   block. 我们下面会看到.

##### old version of gfn_to_pfn

在看`try_async_pf`之前, 我们先看下合入patch之前的 `gfn_to_pfn`接口.

```
gfn_to_pfn {
  __gfn_to_pfn(atomic=false) {
    gfn_to_hva {
      gfn_to_hva_many
        gfn_to_hva_memslot
    } //gfn_to_hva
    -----

    上面 gfn_to_hva
    下面 hva_to_pfn

    -----
    hva_to_pfn(atomic=false) {
      if (atomic)
         __get_user_pages_fast()
      else
         //走这个路径
         get_user_pages_fast()
    } //hva_to_pfn
  } //__gfn_to_pfn
} //gfn_to_pfn
```

关于`__get_user_pages_fast`和`get_user_pages_fast`的不同, 主要是:
* `__get_user_pages_fast()`是atomic版本(IRQ-safe), 主要是因为`get_user_pages_fast`
  需要走slow path, 这个时候需要开中断, 而`__get_user_pages_fast`则不需要, 所以
  其过程是关中断的, 也可以在关中断的情况下执行
* 由于上面提到的原因, `get_user_pages_fast` 并不保存中断状态, 所以该函数必须在
  开中断的情况下执行

---
---

<details open markdown="1">

<summary>两个接口前的代码注释, 以及大致流程</summary>

* `get_user_pages_fast`

  ```cpp
  /**
   * get_user_pages_fast() - pin user pages in memory
   * @start:      starting user address
   * @nr_pages:   number of pages from start to pin
   * @write:      whether pages will be written to
   * @pages:      array that receives pointers to the pages pinned.
   *              Should be at least nr_pages long.
   *
   * Attempt to pin user pages in memory without taking mm->mmap_sem.
   * If not successful, it will fall back to taking the lock and
   * calling get_user_pages(). 
   *
   * > 在不拿mm->mmap_sem 锁的情况下, 尝试将user page pin 到memory中.
   * > 如果没有成功, 它将fall back 来拿锁, 并且调用get_user_pages()
   *
   * Returns number of pages pinned. This may be fewer than the number
   * requested. If nr_pages is 0 or negative, returns 0. If no pages
   * were pinned, returns -errno.
   *
   * > 返回 page 被 pinned数量. 他可能比所需的数量要少. 如果nr_pages是0,
   * 或者是负数, 返回0. 如果没有page被pinned, 返回 -errno
   */
  get_user_pages_fast {
    local_irq_disable
    fast_path {
      //仅去看有多少page present
    }
    local_irq_enable
    get_user_page
  }
  ```
  
  `__get_user_pages_fast`
  
  ```cpp
  /*
   * Like get_user_pages_fast() except its IRQ-safe in that it won't fall
   * back to the regular GUP.
   *
   * 除了他的 IRQ-safe(因为他不会fall bak to regular GUP), 其他的和 
   * get_user_pages_fast()一样
   */
  __get_user_pages_fast {
    local_irq_save()
    fast_path
    local_irq_restore()
  }
  ```
</details>

---
---

这里, 我们不再过多展开GUP的代码, 总之, 早期的`__get_user_pages_fast`不会fall back
到 regular GPU(slow path`get_user_pages`)

我们再来看下其改动, 

##### gfn_to_pfn->get_user_pages

新增`gfn_to_pfn_async()`, 替代现有流程中的`gfn_to_pfn()`, 该接口新增了
`async:bool*`参数, 该参数是一个`iparam && oparam`

* iparam: 表示只走`get_user_page fast path`也就是`__get_user_pages_fast`
* oparam: 表示是否需要做 async pf

具体改动如下
```diff
+pfn_t gfn_to_pfn_async(struct kvm *kvm, gfn_t gfn, bool *async)
+{
+   return __gfn_to_pfn(kvm, gfn, false, async);
+}
+EXPORT_SYMBOL_GPL(gfn_to_pfn_async);
+
 pfn_t gfn_to_pfn(struct kvm *kvm, gfn_t gfn)
 {
-   return __gfn_to_pfn(kvm, gfn, false);
    //可以走slow path
+   return __gfn_to_pfn(kvm, gfn, false, NULL);
 }
 EXPORT_SYMBOL_GPL(gfn_to_pfn);

/*
 * !!MY NOTE!!
 * __gfn_to_pfn {
 *   ...
 *   //先初始化为false
 *   if (async)
 *     *async = false;
 *   ...
 *   return hva_to_pfn(kvm, addr, atomic, async);
 * }
 */
```

我们再来看下`hva_to_pfn`改动:
```diff
+static pfn_t hva_to_pfn(struct kvm *kvm, unsigned long addr, bool atomic,
+           bool *async)
 {
    struct page *page[1];
-   int npages;
+   int npages = 0;
    pfn_t pfn;

-   if (atomic)
+   /* we can do it either atomically or asynchronously, not both */
+   BUG_ON(atomic && async);
    //==(1)==
+   if (atomic || async)
        npages = __get_user_pages_fast(addr, 1, 1, page);
-   else {
+
    //==(2)==
+   if (unlikely(npages != 1) && !atomic) {
        might_sleep();
-       npages = get_user_pages_fast(addr, 1, 1, page);
+       
+       if (async) {
+           down_read(&current->mm->mmap_sem);
+           npages = get_user_pages_noio(current, current->mm,
+         			     addr, 1, 1, 0, page, NULL);
+           up_read(&current->mm->mmap_sem);
+       } else
+           npages = get_user_pages_fast(addr, 1, 1, page);
    }
    if (unlikely(npages != 1)) {
       struct vm_area_struct *vma;

       if (atomic)
               goto return_fault_page;

       down_read(&current->mm->mmap_sem);
       if (is_hwpoison_address(addr)) {
               up_read(&current->mm->mmap_sem);
               get_page(hwpoison_page);
               return page_to_pfn(hwpoison_page);
       }

       vma = find_vma(current->mm, addr);

       if (vma == NULL || addr < vma->vm_start ||
                !(vma->vm_flags & VM_PFNMAP)) {
            //==(3)==
+           if (async && !(vma->vm_flags & VM_PFNMAP) &&
+               (vma->vm_flags & VM_WRITE))
+               *async = true;

            up_read(&current->mm->mmap_sem);
return_fault_page:
            get_page(fault_page);
            return page_to_pfn(fault_page);
        }

        pfn = ((addr - vma->vm_start) >> PAGE_SHIFT) + vma->vm_pgoff;
        up_read(&current->mm->mmap_sem);
        BUG_ON(!kvm_is_mmio_pfn(pfn));
    } else
        pfn = page_to_pfn(page[0]);

    return pfn;
}
```
1. 如果是`async`, 会先尝试走一次fast path, 如果成功了, 则 `npages = 1`
2. 如果上面fast path 失败了, 并且还是async, 则会执行`get_user_pages_noio()`
   该函数上面也提到过, 该过程不处理 MAJOR fault.
3. 这里说明失败了, 也就是因为遇到了MAJOR fault, 所以该fault 并没有handle,
   需要异步处理, 那么就将 oparam `async` 置为`true`.
   > 这里我们先不关心这里的几个判断条件, 之后放到GUP/内存管理的章节中介绍
   >
   >> 遗留问题
   > {: .prompt-warning}
   {: .prompt-info }

