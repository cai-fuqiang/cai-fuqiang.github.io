## hibernate 总流程
```sh
hibernate
|-> freeze_processes()
|-> create_basic_memory_bitmaps()
    |-> memory_bm_create(bm2)
|-> hibernation_snapshot(hibernation_mode == HIBERNATION_PLATFORM)
|-> if in_suspend
    \-> error = swsusp_write(flags);
    ## free 掉之前保存的bitmap
    |-> swsusp_free();
    |-> if !error
        |-> if hibernation_mode == HIBERNATION_TEST_RESUME
            \-> snapshot_test = true
        --> else
            ## 如果不是test mode，这里将直接关机
            \-> power_down()
    ## 走到这里要么是前面出错了，要么是test模式，总之要走恢复流程了
    |-> in_suspend = 0;
## 走到这里说明是从resume流程的现场恢复的
--> else
    |-> pm_pr_dbg("Hibernation image restored successfully.\n");

## 下面会走一些resume流程
|-> free_basic_memory_bitmaps();
|-> unlock_device_hotplug();
|-> if (snapshot_test)
    ## 如果是test，则还没有从disk image中恢复memory
    \-> error = swsusp_check(false);
    |-> if !error
        \-> error = load_image_and_restore();
## 解冻task
|-> thaw_processes();


## ---------------
```

## frozen
```sh
hibernate
  freeze_processes
    try_to_freeze_tasks
    |=> while (true)
        |-> for_each_process_thread(g, p) {
             ## froze 每个task
             |-> if (p == current || !freeze_task(p))
                 \-> continue
             ## 如果是当前进程并且 freeze_task 返回true，则说明
             ## 还有事情要做
             |-> todo++;
         |-> if !todo || time_after(jiffies, end_time)
             ## 如果没有事情要做，并且时间已经到超时时间了, 则break
             |-> break
         ## 如果有pm wakup pending, 说明这是pm侧触发了wakeup, 则退出
         ## freeze
         |-> if pm_wakeup_pending()
             \-> wakeup = true
             \-> break
         |-> usleep_range(sleep_usecs / 2, sleep_usecs)
         ## 过一段时间再试试
         |-> if sleep_usecs < 8 * USEC_PER_MSEC
             \-> sleep_usecs *= 2
    ## 走到这里，并且有todo，说明 frozen 失败了
    |-> if todo:
        ## 如果没有wakup
        \-> if !wakeup || pm_debug_messages_on
            \-> for_each_process_thread(g, p)
                ## 打印哪些没有被frozen的task
                \-> if p != current && freezing(p) && !frozen(p)
                    \-> sched_show_task(p)
```

freeze_task:
```cpp
//RETURNs
//%false, if @p is not freezing or already frozen; %true, otherwise
//如果返回false则说明要么当前流程，已经退出freeze流程了, 要么该task
//已经frozen了
bool freeze_task(struct task_struct *p)
{
        unsigned long flags;

        spin_lock_irqsave(&freezer_lock, flags);
        //需要froze当前task的条件
        //1. 已经处于freezing的流程
        //2. 当前task不是frozen的状态
        if (!freezing(p) || frozen(p) || __freeze_task(p)) {
                spin_unlock_irqrestore(&freezer_lock, flags);
                //如果执行到这里，说明
                //  当前系统没有处于freeze流程   or
                //  该进程执行到if之前，已经是frozen的状态无需再处理    or
                //  该进程在执行 __freeze_task()已经被置为 frozen 状态
                return false;
        }

        if (!(p->flags & PF_KTHREAD))
                //如果不是内核线程, 发送一个假的信号，将其唤醒
                fake_signal_wake_up(p);
        else
                //如果是内核线程，则唤醒
                wake_up_state(p, TASK_NORMAL);

        spin_unlock_irqrestore(&freezer_lock, flags);
        return true;
}
/*
__freeze_task
  task_call_func(p, __set_task_frozen, NULL);
*/
```
`__set_task_frozen`:
```cpp
static int __set_task_frozen(struct task_struct *p, void *arg)
{
        unsigned int state = READ_ONCE(p->__state);

        /*
         * Allow freezing the sched_delayed tasks; they will not execute until
         * ttwu() fixes them up, so it is safe to swap their state now, instead
         * of waiting for them to get fully dequeued.
         */
        //如果task 已经在rq上，但是直到他们被调用ttwu() fixes 他们之前，都可以安全
        //swap他们的state，而不是等待他们完全的出队
        if (task_is_runnable(p))
                return 0;

        //当前的进程是不是该进程，并且有没有在其他的cpu上执行.
        if (p != current && task_curr(p))
                return 0;

        //只有满足下面三个状态之一，task才能被frozen
        if (!(state & (TASK_FREEZABLE | __TASK_STOPPED | __TASK_TRACED)))
                return 0;

        /*
         * Only TASK_NORMAL can be augmented with TASK_FREEZABLE, since they
         * can suffer spurious wakeups.
         */
        //只有 TASK_NORMAL 的才能配置 TASK_FREEZABLE, 因为他们可以 伪唤醒
        if (state & TASK_FREEZABLE)
                WARN_ON_ONCE(!(state & TASK_NORMAL));

#ifdef CONFIG_LOCKDEP
        /*
         * It's dangerous to freeze with locks held; there be dragons there.
         */
        if (!(state & __TASK_FREEZABLE_UNSAFE))
                WARN_ON_ONCE(debug_locks && p->lockdep_depth);
#endif
        //唤出state
        p->saved_state = p->__state;
        WRITE_ONCE(p->__state, TASK_FROZEN);
        return TASK_FROZEN;
}
```
当进程处理信号时:
```sh
get_signal
|-> try_to_freeze()
    |-> if !freezing(current)
        \-- return false
    |-> __refrigerator(false)
        ## swap current->__state
        |-> WRITE_ONCE(current->__state, TASK_FROZEN)
        |-> current->saved_state = TASK_RUNNING
        ## 查看当前是否还处于freezing的流程
        |-> freeze = freezing(current) && !(check_kthr_stop && kthread_should_stop())
        ## 如果不是，退出循环
        |-> if !freeze
            \-> break
        |-> schedule()
    |-> __set_current_state(TASK_RUNNING)
```
## hibernation_snapshot
```sh
hibernation_snapshot
|-> hibernate_preallocate_memory()
|-> freeze_kernel_threads()
## !!!!!!---DPM INTERFACE-----
|-> dpm_prepare()
## !!!!!!---DPM INTERFACE-----
|-> error = dpm_suspend()
|-> if (error || hibernation_test(TEST_DEVICES))
    \-> platform_recover(platform_mode)
|-- else:
    \-> error = create_image(platform_mode)
        |-> platform_pre_snapshot(platform_mode)
            |-> hibernation_ops->pre_snapshot()
        |-> pm_sleep_disable_secondary_cpus()
            |-> suspend_disable_secondary_cpus()
                |-> freeze_secondary_cpus()
                    \-> pr_info("Disabling non-boot CPUs ...\n")
                    |-> for_each_cpu()
                        |-> _cpu_down(cpu, 1, CPUHP_OFFLINE)
        |-> save_processor_state()
            |-> __save_processor_state(&saved_context);
                |-> save, gs,fs,ds,crX, msr...
            |-> x86_platform.save_sched_clock_state();
        ## save gen regs
        |-> swsusp_arch_suspend()
            |-> save regs:
                \-> rsp,rbp,rdi,....cr3
            ## copy images
            |-> swsusp_save
                |-> pr_info("Creating image:\n")
                |-> COPY PAGES
                |-> pr_info("Image created (%d pages copied, %d zero pages)\n", 
                       nr_copy_pages, nr_zero_pages)
        |-> platform_leave()
            |-> hibernation_ops->leave()
                ## acpi_hibernation_leave
                |-> suspend_nvs_restore();
        |-> syscore_resume()
        |-> pm_sleep_enable_secondary_cpus()
            |-> suspend_enable_secondary_cpus();
                |-> thaw_secondary_cpus();
                    |-> pr_info("Enabling non-boot CPUs ...\n");
                    |-> for_each_cpu()
                        \-> _cpu_up(cpu, 1, CPUHP_ONLINE)
            |-> cpuidle_resume();
## !!!!!!---DPM INTERFACE-----
|-> dpm_resume()
## !!!!!!---DPM INTERFACE-----
|-> dmp_complete()


## pre_snapshot
pre_snapshot -- acpi_hibernation_ops.acpi_pm_prepare
|-> error = __acpi_pm_prepare()
    |-> int error = acpi_sleep_prepare(acpi_target_sleep_state);
        |-> pr_info("Preparing to enter system sleep state S%d\n", acpi_state);
    |-> if error:
        \-> acpi_target_sleep_state = ACPI_STATE_S0
|-> if !error:
    \-> acpi_pm_pre_suspend();
        |-> acpi_pm_freeze();
        |-> suspend_nvs_save()
            |-> pr_info("Saving platform NVS memory\n");
```
### hibernate_preallocate_memory 注释

```
hibernate_preallocate_memory - Preallocate memory for hibernation image.

To create a hibernation image it is necessary to make a copy of every page
frame in use.  We also need a number of page frames to be free during
hibernation for allocations made while saving the image and for device
drivers, in case they need to allocate memory from their hibernation
callbacks (these two numbers are given by PAGES_FOR_IO (which is a rough
estimate) and reserved_size divided by PAGE_SIZE (which is tunable through
/sys/power/reserved_size, respectively).  To make this happen, we compute the
total number of available page frames and allocate at least

为了创建休眠镜像，必须复制所有正在使用的物理页框。同时，在休眠过程中还需要有一定
数量的空闲页框，用于在保存镜像时的内存分配，以及供设备驱动在其休眠回调中分配内存
时使用（这两部分的数量分别由 PAGES_FOR_IO（这是一个粗略估算值）和 reserved_size
除以 PAGE_SIZE（该值可通过 /sys/power/reserved_size 进行调整）给出）。为实现这一
点，我们会计算可用页框的总数，并至少分配

([page frames total] - PAGES_FOR_IO - [metadata pages]) / 2
 - 2 * DIV_ROUND_UP(reserved_size, PAGE_SIZE)

of them, which corresponds to the maximum size of a hibernation image.

这对应于休眠图像的最大大小。

If image_size is set below the number following from the above formula,
the preallocation of memory is continued until the total number of saveable
pages in the system is below the requested image size or the minimum
acceptable image size returned by minimum_image_size(), whichever is greater.

如果 image_size 设置得低于上述公式计算出的数量，则内存的预分配会持续进行，直到系
统中可保存的页总数低于所请求的 image_size，或者低于 minimum_image_size() 返回的
最小可接受镜像大小（两者取较大值）为止。
```

### hibernate_preallocate_memory
```sh
hibernate_preallocate_memory
## allocate memory for a memory bitmap
|-> memory_bm_create(orig_bm)
    |-> create_mem_extents(&mem_extent)
        ## 遍历每一个populated zone
        |-> for_each_populated_zone(zone)
            ## 将获取zone [start, end], 构造mem_extent, 链接到list链表中(从大到
            小)
            ## 处理好 merge的情况
            ## 这块代码似乎逻辑有问题，回头在看!!!!!

    |-> list_for_each_entry(ext, &mem_extent, hook)
        ## for one zone to create a radix tree
        |-> create_zone_bm_rtree()
            ## 通过chain_alloc 分配 mem_zone_bm_rtree 数据结构
            |-> zone  = chain_alloc(ca, sizeof(struct mem_zone_bm_rtree));
            |-> zone->start_pfn = start
            |-> zone->end_pfn = end
            ## 计算该 zone pages 数量所需要的bitmap空间, 需要多少个zone来存储
            |-> nr_blocks = DIV_ROUND_UP(pages, BM_BITS_PER_BLOCK)
            |-> for (i = 0; i < nr_blocks; i++)
                ## 在rtree中增加一个节点
                \-> add_rtree_block(zone, gfp_mask, safe_needed, ca)
        ## 将zone 串联到bm->zones中
        |-> list_add_tail(&zone->list, &bm->zones)
        ## p_list指向chain 链
        |-> bm->p_list = ca.chain
    |-> memory_bm_create(&copy_bm,,)
    |-> memory_bm_create(&zero_bm,,)
```
具体变量:

后半段流程，这段代码读着真的很爽(左右脑互博)
```cpp
int hibernate_preallocate_memory(void)
{
        ...

        alloc_normal = 0;
        alloc_highmem = 0;
        nr_zero_pages = 0;

        /*
         * saveable: 目前正在使用的，可以并且需要被save的page, 哪些内存
         * CAN't /no need save呢, 举几个例子:
         *   * offline page(不能)
         *   * page guard(不能)
         *   * free page(不需要)
         */
        /* Count the number of saveable data pages. */
        save_highmem = count_highmem_pages();
        saveable = count_data_pages();

        /*
         * Compute the total number of page frames we can use (count) and the
         * number of pages needed for image metadata (size).
         */
        count = saveable;
        saveable += save_highmem;
        highmem = save_highmem;
        size = 0;
        for_each_populated_zone(zone) {
                size += snapshot_additional_pages(zone);
                if (is_highmem(zone))
                        highmem += zone_page_state(zone, NR_FREE_PAGES);
                else
                        count += zone_page_state(zone, NR_FREE_PAGES);
        }
        /* saveable */
        avail_normal = count;
        /*
         * 这个实际上包括 saveable 以及free 内存, 但是需要减去 totalreserve_pages,
         * 降低对伙伴系统的影响
         * count = saveable
         * count += highmem
         * count -= totalreserve_pages
         */
        count += highmem;
        count -= totalreserve_pages;

        /* Compute the maximum number of saveable pages to leave in memory. */
        /* 
         * + 这里 / 2 是指，savepage 就是为需要保存的page创建副本，所以需要两份. 但是metadata 
         * 而PAGES_FOR_IO 是需要预留出的空间, 这两者都不用保存(个人认为, 有待确认)
         *
         * + reserve_size是指:
         *    the amount of memory reserved for allocations made by device
         *    drivers during the "device freeze" stage of hibernation.
         *
         *   但是需要注意的是，这里需要 * 2, 因为suspend和resume 都需要预留内存，那
         *   Q: 既然不能被伙伴系统保存，那为什么resume流程不能复用suspend中预留的内存呢?
         *   A: 虽然不用save to image， 但是这部分内存在伙伴系统中，标识被占用了，所以
         *      在resume流程中仍然是不可用的，这样相当于减少了image的大小.
         *   我只能说，内核大佬的抠 真的是做到了极致。
         *
         *   (上面仅是自己的猜测)
         */
        max_size = (count - (size + PAGES_FOR_IO)) / 2
                    - 2 * DIV_ROUND_UP(reserved_size, PAGE_SIZE);
        /* Compute the desired number of image pages specified by image_size. */
        /* image size 是用户配置的镜像的最大size，但是如果不满足，内核会尽量减少
         * image size.
         *
         * image size究竟影响什么，其实影响downtime，如果image size比较小，这里类
         * 似于热迁移里面的postcopy, suspend时，先将内存回收，然后满足image_size后,
         * 再将剩余内存保存到image中. 而恢复是，直将image中的内存恢复。所以image越小，
         * 其suspend和resume的时间就会越少，而用户在resume后，如果要用到image 恢复内存
         * 之外的内存，则再交换;
         */
        size = DIV_ROUND_UP(image_size, PAGE_SIZE);
        if (size > max_size)
                size = max_size;
        /*
         * If the desired number of image pages is at least as large as the
         * current number of saveable pages in memory, allocate page frames for
         * the image and we're done.
         */
        /* 
         * 如果image_size 足够大，能够容纳所有的saveable page, 那就不用想了，直接拒绝选择，
         * 全都要!!!
         */
        if (size >= saveable) {
                pages = preallocate_image_highmem(save_highmem);
                pages += preallocate_image_memory(saveable - pages, avail_normal);
                goto out;
        }

        /* Estimate the minimum size of the image. */
        /*
         * 预估saveable中，最小的page数量，作为最小的image_size
         */
        pages = minimum_image_size(saveable);
        /*
         * To avoid excessive pressure on the normal zone, leave room in it to
         * accommodate an image of the minimum size (unless it's already too
         * small, in which case don't preallocate pages from it at all).
         */
        /* 
         * avail_normal 表示，可在normal 区间 分配给image的内存大小, 这里会尽量满足normal
         * page的存储需求。尽量给normal_page 留空间.(也就是尽量把image分配到highmem)
         */
        if (avail_normal > pages)
                avail_normal -= pages;
        else
                avail_normal = 0;
        //如果size比pages还小，说明, size定的太小了。pages表示为必须要存到image
        //中的内存. max_size表示镜像的最大大小, 所以取几个中的最小值。
        if (size < pages)
                size = min_t(unsigned long, pages, max_size);

        /*
         * Let the memory management subsystem know that we're going to need a
         * large number of page frames to allocate and make it free some memory.
         * NOTE: If this is not done, performance will be hurt badly in some
         * test cases.
         */
        /* 这里先让伙伴系统回收内存, 回收内存数量为 saveable - size, 让image中保存的
         * page数量下降至size(尽量)
         *
         * 注意：该函数只会在 GFP_HIGHUSER_MOVABLE 中回收
         */
        shrink_all_memory(saveable - size);
        /*
         * The number of saveable pages in memory was too high, so apply some
         * pressure to decrease it.  First, make room for the largest possible
         * image and fail if that doesn't work.  Next, try to decrease the size
         * of the image as much as indicated by 'size' using allocations from
         * highmem and non-highmem zones separately.
         */
        //首先 在highmem中分配一半内存
        pages_highmem = preallocate_image_highmem(highmem / 2);
        //alloc 表示，将内存降低到 max_size 要分配 page的数量
        alloc = count - max_size;
        //如果alloc > pages_highmem, 说明上面分配的内存不够，还需要在其他地方分配
        if (alloc > pages_highmem)
                alloc -= pages_highmem;
        else
                alloc = 0;
        //在avail_normal中分配，但是不能超过avail_normal的值, 因为其想让image主要保存
        //avail_normal
        pages = preallocate_image_memory(alloc, avail_normal);
        //如果是 < alloc, 说明上面分配的不够，还需要继续分配
        if (pages < alloc) {
                /* We have exhausted non-highmem pages, try highmem. */
                alloc -= pages;
                pages += pages_highmem;
                //再从 highmem中分配
                pages_highmem = preallocate_image_highmem(alloc);
                //如果还是分配不到, 则GG，整个流程失败
                //这里为什么将内存压缩到max_size 就可以判断, prealloc流程基本可以成功执行了.
                //因为max_size 表示镜像的最大大小，所以，将内存能降到max_size就说明后续流程
                //基本可以执行成功, 但是如果降不到，那大概率GG, 所以这里就提前返回了.
                if (pages_highmem < alloc) {
                        pr_err("Image allocation is %lu pages short\n",
                                alloc - pages_highmem);
                        goto err_out;
                }
                pages += pages_highmem;
                /*
                 * size is the desired number of saveable pages to leave in
                 * memory, so try to preallocate (all memory - size) pages.
                 */
                //达到max_size的要求后，剩余的 max_size -> pages, 只能尽量分配抢占了.
                //如果完不成也没有办法
                alloc = (count - pages) - size;
                pages += preallocate_image_highmem(alloc);
        //这里说明已经达到了max_size的目标了, 但是还是尽力达成 size的目标.
        } else {
                /*
                 * There are approximately max_size saveable pages at this point
                 * and we want to reduce this number down to size.
                 */
                alloc = max_size - size;
                size = preallocate_highmem_fraction(alloc, highmem, count);
                pages_highmem += size;
                alloc -= size;
                size = preallocate_image_memory(alloc, avail_normal);
                pages_highmem += preallocate_image_highmem(alloc - size);
                pages += pages_highmem + size;
        }

        /*
         * We only need as many page frames for the image as there are saveable
         * pages in memory, but we have allocated more.  Release the excessive
         * ones now.
         */
        //这里我们只需要预留saveable pages, 用于snapshot, 其他的内存可以释放掉
        pages -= free_unnecessary_pages();

 out:
        stop = ktime_get();
        pr_info("Allocated %lu pages for snapshot\n", pages);
        swsusp_show_speed(start, stop, pages, "Allocated");

        return 0;
 err_out:
        swsusp_free();
        return -ENOMEM;
}
```

### swsusp_save
```sh
swsusp_save
|-> pr_info("Creating image:\n");
## 释放pcp pages
|-> drain_local_pages()
## 获取saveable pages 数量
|-> nr_pages = count_data_pages();
|-> nr_highmem = count_highmem_pages();
|-> pr_info("Need to copy %u pages\n", nr_pages + nr_highmem);
|-> if (!enough_free_mem(nr_pages, nr_highmem))
         |-> for_each_populated_zone(zone)
             |-> if !is_highmem(zone) 
                 \-> free += zone_page_state(zone, NR_FREE_PAGES);
         ## 查看查看highmem free pages 够不够分配 nr_highmem, nr_pages
         ## 表示highmem不够了，需要在normal pages中分配的内存页数量
         |-> nr_pages += count_pages_for_highmem(nr_highmem);
             ## current_free + prealloc_higmem
             |-> free_highmem = count_free_highmem_pages() + alloc_highmem;
             |-> if free_highmem >= nr_highmem:
                 \-> nr_highmem = 0
             --> else:
                 \-> nr_highmem -= free_highmem;
             |--> return nr_highmem;
         |-> pr_debug("Normal pages needed: %u + %u, available pages: %u\n",
                    nr_pages, PAGES_FOR_IO, free);
         ## free 需要大于 nr_pages + PAGES_FOR_IO
         ## 这里的PAGES_FOR_IO表示 resume过程中需要预留给device 执行  resume流程
         ## 的内存, 另外 PAGES_FOR_IO 要在 normal 内存中分配
         |-> return free > nr_pages + PAGES_FOR_IO;
    \-> return false
|-> if swsusp_alloc(&copy_bm, nr_pages, nr_highmem)
    |-> alloc pages and mark in COPY_BM
## During allocating of suspend pagedir, new cold pages may appear. Kill them.
|-> drain_local_pages(NULL);
    ## 从orig_bm 向copy_bm 以及 zero_bm 中copy
|-> nr_copy_pages = copy_data_pages(&copy_bm, &orig_bm, &zero_bm);
    |-> for_each_populated_zone(zone)
        ## 重新标记free_pages ??? why ???
        |-> for (pfn = zone->zone_start_pfn; pfn < max_zone_pfn; pfn++)
            |-> if page_is_saveable(zone, pfn)
                |-> memory_bm_set_bit(orig_bm, pfn);
    ## position reset for two bitmap
    |-> memory_bm_position_reset(orig_bm);
    |-> memory_bm_position_reset(copy_bm);
    ## 找到第一个copy_pfn，开始copy
    |-> copy_pfn = memory_bm_next_pfn(copy_bm);
    |-> for (;;)
        |-> pfn = memory_bm_next_pfn(orig_bm);
        |-> if (copy_data_page(copy_pfn, pfn))
            ## 如果返回true，说明该page是zero page
            ## 关于 copy_data_page 暂不展开, 涉及到map相关知识
            \-> memory_bm_set_bit(zero_bm, pfn);
            |-> continue
        |-> copied_pages++
        |-> copy_pfn = memory_bm_next_pfn(copy_bm);
    |-> return copied_pages
|-> nr_pages += nr_highmem;
|-> nr_zero_pages = nr_pages - nr_copy_pages;
## nr_meta_pages: 表示源数据，每个page占用一个 long
|-> nr_meta_pages = DIV_ROUND_UP(nr_pages * sizeof(long), PAGE_SIZE);
|-> pr_info("Image created (%d pages copied, %d zero pages)\n", nr_copy_pages, nr_zero_pages);
```

### swsusp_write
```sh
swsusp_write
|-> snapshot_get_image_size
    |-> nr_copy_pages + nr_meta_pages + 1
|-> error = get_swap_writer(&handle)
|-> 
```

## restore
## some log

```
[   25.365641] smpboot: Booting Node 0 Processor 30 APIC 0x1e
[   25.386706] CPU30 is up
[   25.386743] smpboot: Booting Node 0 Processor 31 APIC 0x1f
[   25.407836] CPU31 is up
[   25.411086] ACPI: PM: Waking up from system sleep state S4
[   25.428800] xhci_hcd 0000:01:00.0: xHC error in resume, USBSTS 0x401, Reinit
[   25.428805] usb usb1: root hub lost power or was reset
[   25.428807] usb usb2: root hub lost power or was reset
[   25.430029] virtio_blk virtio4: 32/0/0 default/read/poll queues
[   25.430049] virtio_blk virtio3: 32/0/0 default/read/poll queues
[   25.735630] ata3: SATA link down (SStatus 0 SControl 300)
[   25.743550] ata4: SATA link down (SStatus 0 SControl 300)
[   25.744108] ata1: SATA link down (SStatus 0 SControl 300)
[   25.744701] ata2: SATA link down (SStatus 0 SControl 300)
[   25.745342] ata6: SATA link down (SStatus 0 SControl 300)
[   25.746036] ata5: SATA link down (SStatus 0 SControl 300)
[   25.850068] PM: Using 3 thread(s) for compression
[   25.850069] PM: Compressing and saving image data (236817 pages)...
[   25.850085] PM: Image saving progress:   0%
[   25.946268] PM: Image saving progress:  10%
...

[   26.891044] PM: Image saving done
[   26.891045] PM: hibernation: Wrote 947268 kbytes in 1.04 seconds (910.83 MB/s)
[   26.891161] PM: S|
[   26.926693] printk: Suspending console(s) (use no_console_suspend to debug)
C
```
no s4:
```
[   24.631724] smpboot: Booting Node 0 Processor 30 APIC 0x1e
[   24.652834] CPU30 is up
[   24.652886] smpboot: Booting Node 0 Processor 31 APIC 0x1f
[   24.674105] CPU31 is up
[   24.686362] usb usb1: root hub lost power or was reset
[   24.690119] virtio_blk virtio2: 32/0/0 default/read/poll queues
[   24.690168] virtio_blk virtio3: 32/0/0 default/read/poll queues
[   24.926649] PM: Using 3 thread(s) for compression
[   24.926651] PM: Compressing and saving image data (230331 pages)...
[   24.926672] PM: Image saving progress:   0%
[   25.042600] PM: Image saving progress:  10%
[   25.144086] PM: Image saving progress:  20%
...
[   26.040985] PM: hibernation: Wrote 921324 kbytes in 1.11 seconds (830.02 MB/s)
[   26.041160] PM: S|
[   26.078108] ACPI: PM: Preparing to enter system sleep state S5
[   26.080062] kvm: exiting hardware virtualization
[   26.081262] reboot: Power down
```

## 参考链接
1. [Debugging hibernation and suspend](https://docs.kernel.org/power/basic-pm-debugging.html)
2. [Linux电源管理(12)_Hibernate功能](http://www.wowotech.net/pm_subsystem/hibernation.html)
3. 
