
### address_space

`address_space` 用于联系文件和后端存储器(backing dev):

```cpp
struct address_space {
 struct inode    *host;    /* owner: inode, block_device */
 struct radix_tree_root  page_tree;  /* radix tree of all pages */
 spinlock_t    tree_lock;  /* and lock protecting it */
 unsigned int    i_mmap_writable;/* count VM_SHARED mappings */
 struct prio_tree_root i_mmap;   /* tree of private and shared mappings */
 struct list_head  i_mmap_nonlinear;/*list VM_NONLINEAR mappings */
 spinlock_t    i_mmap_lock;  /* protect tree, count, list */
 unsigned int    truncate_count; /* Cover race condition with truncate */
 unsigned long   nrpages;  /* number of total pages */
 pgoff_t     writeback_index;/* writeback starts here */
 const struct address_space_operations *a_ops; /* methods */
 unsigned long   flags;    /* error bits/gfp mask */
 struct backing_dev_info *backing_dev_info; /* device readahead, etc */
 spinlock_t    private_lock; /* for use by the address_space */
 struct list_head  private_list; /* ditto */
 struct address_space  *assoc_mapping; /* ditto */
} __attribute__((aligned(sizeof(long))));
```
* **page_tree** : 列出该`address_space` 中的所有物理内存页, key 为`page index`, value
  为该`struct page` 的地址;
* **i_mmap** : 所有映射的页都可在该树中找到
* **backing_dev_info** : 包含`address_space` 相关的`backing dev` 相关信息
* **private_list** : 将包含文件系统的元数据的`buffer_head`实例链接起来（不过
  有一些文件系统有自己的文件系统元数据管理结构，例如xfs)

### backing_dev_info
```cpp
struct backing_dev_info {
  unsigned long ra_pages; /* max readahead in PAGE_CACHE_SIZE units */
  unsigned long state;  /* Always use atomic bitops on this */
  unsigned int capabilities; /* Device capabilities */
  congested_fn *congested_fn; /* Function pointer if device is md/dm */
  void *congested_data; /* Pointer to aux data for congested func */
  void (*unplug_io_fn)(struct backing_dev_info *, struct page *);
  void *unplug_io_data;
 
  struct percpu_counter bdi_stat[NR_BDI_STAT_ITEMS];
 
  struct prop_local_percpu completions;
  int dirty_exceeded;
 
  unsigned int min_ratio;
  unsigned int max_ratio, max_prop_frac;
 
  struct device *dev;
 
#ifdef CONFIG_DEBUG_FS
  struct dentry *debug_dir;
  struct dentry *debug_stats;
#endif
};
```
* **ra_pages** : 指定了预读的最大条目
* **capabilities**: 保存了后备存储器有关信息，例如是否可以支持writeback。（ramdisk则标记 
  `BDI_CAP_NO_WRITEBACK`， 因为内存设备回写没有意义。
* **congested_fn, congested_data**: 和md/dm相关

### address_space_operations
```cpp
struct address_space_operations {
  int (*writepage)(struct page *page, struct writeback_control *wbc);
  int (*readpage)(struct file *, struct page *);
  void (*sync_page)(struct page *);
 
  /* Write back some dirty pages from this mapping. */
  int (*writepages)(struct address_space *, struct writeback_control *);
 
  /* Set a page dirty.  Return true if this dirtied it */
  int (*set_page_dirty)(struct page *page);
 
  int (*readpages)(struct file *filp, struct address_space *mapping,
     struct list_head *pages, unsigned nr_pages);
  
  int (*write_begin)(struct file *, struct address_space *mapping,
       loff_t pos, unsigned len, unsigned flags,
       struct page **pagep, void **fsdata);
  int (*write_end)(struct file *, struct address_space *mapping,
       loff_t pos, unsigned len, unsigned copied,
       struct page *page, void *fsdata);
  
  /* Unfortunately this kludge is needed for FIBMAP. Don't use it */
  sector_t (*bmap)(struct address_space *, sector_t);
  void (*invalidatepage) (struct page *, unsigned long);
  int (*releasepage) (struct page *, gfp_t);
  ssize_t (*direct_IO)(int, struct kiocb *, const struct iovec *iov,
     loff_t offset, unsigned long nr_segs);
  int (*get_xip_mem)(struct address_space *, pgoff_t, int,
           void **, unsigned long *);
  /* migrate the contents of a page to the specified target */
  int (*migratepage) (struct address_space *,
     struct page *, struct page *);
  int (*launder_page) (struct page *);
  int (*is_partially_uptodate) (struct page *, read_descriptor_t *,
         unsigned long);
};
```

* **writepage, writepages**: 将 `address_space` 的一页或者多页写回到`backing dev`
* **readpage, readpages**: 从`backing dev`读取一页或者多个连续的页。
* **sync_page**: 将尚未`writeback`的页同步到 `backing dev`(TODO 关注和writepages
  不同)
* **set_page_dirty**: 将一页标记为脏(TODO 关注其调用者)
* **prepare_write, commit_write**: 和日志相关
* **direct_IO** : 用于实现直接读写访问

### writeback_control
```
/*
 * A control structure which tells the writeback code what to do.  These are
 * always on the stack, and hence need no locking.  They are always initialised
 * in a manner such that unspecified fields are set to zero.
 */
struct writeback_control {
  struct backing_dev_info *bdi; /* If !NULL, only write back this
            queue */
  enum writeback_sync_modes sync_mode;
  unsigned long *older_than_this; /* If !NULL, only write back inodes
            older than this */
  long nr_to_write;   /* Write this many pages, and decrement
            this for each page written */
  long pages_skipped;   /* Pages which were not written */
│ 
  /*
   * For a_ops->writepages(): is start or end are non-zero then this is
   * a hint that the filesystem need only write out the pages inside that
   * byterange.  The byte at `end' is included in the writeout request.
   */
  loff_t range_start;
  loff_t range_end;
│ 
  unsigned nonblocking:1;   /* Don't get stuck on request queues */
  unsigned encountered_congestion:1; /* An output: a queue is full */
  unsigned for_kupdate:1;   /* A kupdate writeback */
  unsigned for_reclaim:1;   /* Invoked from the page allocator */
  unsigned for_writepages:1;  /* This is a writepages() call */
  unsigned range_cyclic:1;  /* range_start is cyclic */
  unsigned more_io:1;   /* more io to be dispatched */
  /*
   * write_cache_pages() won't update wbc->nr_to_write and
   * mapping->writeback_index if no_nrwrite_index_update
   * is set.  write_cache_pages() may write more than we
   * requested and we want to make sure nr_to_write and
   * writeback_index are updated in a consistent manner
   * so we use a single control to update them
   */
  unsigned no_nrwrite_index_update:1;
};
```

* **writeback_sync_modes**:  
  + WB_SYNC_NONE
  + WB_SYNC_ALL
* **older_than_this**: 如果不是空，值writeback 比该inode older的inode
* **for_kupdate**: 表示是`kupdate` 流程调用
* **for_writepages**: 表示是`writepages` 流程调用
* **more_io**: 

## 页缓存相关接口

### alloc pagecache
```
page_cache_alloc
```

### lockup pagecache
```
find_get_page
```

### wait on page
等待pagecache 状态变更为预期值:

```sh
wait_on_page_writeback
=> if PageWriteback(page)
   => wait_on_page_bit(page, PG_writeback)
      => DEFINE_WAIT_BIT(wait, &page->flags, bit_nr);
      => if test_bit(bit_nr, &page->flags)
         => __wait_on_bit(page_waitqueue(page), &wait, sync_page
                 TASK_UNINTERRUPTIBLE);



## __wait_on_bit 首先会现将任务加入到相应的等待队列中，并且设置进程
## 状态
## 
## 并查看page->flags有没有`PG_writeback`,如果没有
## 则调用 sync_page, sync_page(), sync_page()会调用io_schedule()
## 此时进程D住，等待唤醒。
__wait_on_bit
=> do
     => prepare_to_wait
        => wait->flags &= ~WQ_FLAG_EXCLUSIVE
        => if(list_empty(&wait->task_list))
           ## 如果没有加到waitq中 
           => __add_wait_queue()
        => set_current_state
     => test_bit(q->key.bit_nr, q->key.flags)
        ## action 为 sync_page
        => ret (*action)(q->key.flags)
   while test_bit(q->key.bit_nr, q->key.flags) &*& !ret

sync_page(flag) -- action
=> mapping = page_mapping(page);
=> if mapping && mapping->a_ops && mapping->a_ops->sync_page
   ## 调用address_space的 sync_page
   => mapping->a_ops->sync_page(page);
=> io_schedule()
```
以`block device`为例, 查看sync接口:
```sh
block_sync_page
=> mapping = page_mapping(page)
=> if mapping
   => blk_run_backing_dev()
      => if (bdi && bdi->unplug_io_fn)
         => bdi->unplug_io_fn(bdi, page);
```
如果没有`unplug_io_fn` 啥也不做。


## set writeback

```sh
test_set_page_writeback
=> if mapping
   => ret = TestSetPageWriteback(page);
   ## 别的流程还未设置
   => if !ret
      => radix_tree_tag_set(&mapping->page_tree,
                page_index(page),
                PAGECACHE_TAG_WRITEBACK));
      ## 增加bdi WRITEBACK 计数
      => if bdi_cap_account_writeback(bdi)
         => __inc_bdi_stat(bdi, BDI_WRITEBACK);
            => __add_bdi_stat(bdi, item, 1);
               => __percpu_counter_add(&bdi->bdi_stat[item], amount, BDI_STAT_BATCH);
   -> else
      => ret = TestSetPageWriteback()
=> if !ret
   =>  inc_zone_page_statet(page, NR_WRITEBACK)
```

## clear writeback

```sh
end_page_writeback
=> TestClearPageReclaim
   => rotate_reclaimable_page
## PG_writeback被别人清掉了
=> if !test_clear_page_writeback(page)
   => BUG()
## 唤醒其他wait page 进程
=> wake_up_page(page, PG_writeback);
```

## 相关堆栈
```sh
DIFF_FILESYSTEM_writepage ##e.g., blkdev_writepage
=> block_write_full_page
   => __block_write_full_page
      ## 准备好bh后
      => set_page_writeback(page);
      => do 
          => struct buffer_head *next = bh->b_this_page
          => if buffer_sync_write(hb)
             =>submit_bh(WRITE, bh)
             => nr_underway++
          => bh = next
      while bh != head
=> if nr_underway == 0
   => end_page_writeback
```


##  更上层流程

### sb 级别sync
```sh
sync_sb_inodes
=> generic_sync_sb_inodes
   ## 不是周期性回写, 或者 sb->s_io为空
   ## 将s_more_io merge 到 s_io,
   => if !wbc->for_kupdate || list_empty(&sb->s_io)
      => queue_io(sb, wbc->older_than_this);
         ## 将 s_more_io merge到 s_io
         => list_splice_init(&sb->s_more_io, sb->s_io.prev);
         => move_expired_inodes(&sb->s_dirty, &sb->s_io, older_than_this);
            ## move_expired_inodes(struct list_head *delaying_queue,
            ##     struct list_head *dispatch_queue,
            ##     unsigned long *older_than_this)
            ##
            ## * delaying_queue:  延迟处理的，优先级低
            ## * dispatch_queue: 即将 writeback,
            ## * older_than_this: 规定一个锚点inode, 如果目标inode比其还要老,
            ##   则会移动到 dispatch_queue
            => while !list_empty(delaying_queue)
               => struct inode *inode = list_entry(delaying_queue->prev
                    struct inode, i_list);
               => if older_than_this && time_after(inode->dirtied_when,
                         *older_thaty_this)
                  => break
               => list_move(&inode->i_list, dispatch_queue)
      ## queue_io_end
      ## 总结:
      ## 将 sb->s_more_io, sb->s_dirty 转移到 s_io 等待writeback 
   ## 依次处理sb->s_io中的每个inode
   => while (!list_empty(&sb->s_io))
      => struct backing_dev_info *bdi = mapping->backing_dev_info
      ## 该bdi不支持writeback -- ! BDI_CAP_NO_WRITEBACK
      => if !bdi_cap_writeback_dirty(bdi)
         => redirty_tail(inode);
            ## 如果sb->s_dirty 不为空
            => if !list_empty(&sb->s_dirty)
               ## 找到末尾inode
               => tail_inode = list_entry(sb->s_dirty.next, struct inode, i_list);
               ## 末尾inode表示最近变脏的，如果发现其比原来末尾变脏的时间要更老, 
               ## 将dirtied_when 更新到当前jiffies
               => if (!time_after_eq(inode->dirtied_when, tail_inode->dirtied_when))
                  => inode->dirtied_when = jiffies
            ## 将 inode 移动到 sb->s_dirty 的末尾
            => list_move(&inode->i_list, &sb->s_dirty);
         ## 如果是 blkdev_sb，那可能是访问到了ramdisk的块设备，仅skip该块设备文件
         => if (sb_is_blkdev_sb(sb))
            => continue
         ## 如果不是blkdev_sb 则说明整个文件系统中的inode都是不能writeback的。跳过整个
         ## 文件系统
         => break
      ## END if !bdi_cap_writeback_dirty
      => if (inode->i_state & I_NEW)
         => requeue_io(inode)
            ## requeue inode for re-scanning after sb->s_io list is exhausted.
            => list_move(&inode->i_list, &inode->i_sb->s_more_io);
         => continue
      ## 如果 wbc 不允许阻塞，并且bdi 目前已经是拥塞的
      => if wbc->nonblocking && bdi_write_congested(bdi)
         ## 则将  encountered_congestion = 1
         => wbc->encountered_congestion = 1
         ## 如果不是 blkdev sb, 则直接break
         => if !sb_is_blkdev_sb(sb)
            => break;
         ## 如果是blkdev sb，则requeue_io 继续处理
         => requeue_io(inode)
         => continue
      ## 如果wbc指定了bdi，但是该bdi不同于inode->mapping->backing_dev_info
      => if wbc->bdi && bdi != wbc->bdi
         => if !sb_is_blkdev_sb
            => break
         => requeue_io(inode)
         => continue
      ## 如果该inode是在 start(进入该函数后变脏的，则无需同步, 因为sync总需要一个时间点，
      ## 否则可能没完没了)
      => if time_after(inode->dirtied_when, start)
         => break
      ## 如果current是pdflush，但是其他的pdflush已经处理了该bdi
      ## writeback_acquire() -- !test_and_set_bit(BDI_pdflush, &bdi->state)
      => if current_is_pdflush() && !writeback_acquire(bdi)
         => break
      => __iget(inode)
      => pages_skipped = wbc->pages_skipped;
      => __writeback_single_inode(inode, wbc);
      => if current_is_pdflush()
         ## 释放掉
         => writeback_release(bdi);
      ...
```

<!--  192
```sh
set_page_writeback
=> test_set_page_writeback
   => __test_set_page_writeback

__test_set_page_writeback
=> if mapping && mapping_use_writeback_tags(mapping)
   ## test and set
   => ret = TestSetPageWriteback(page);
   ## 说明此时没有人进行writeback
   => if !ret
      => on_wblist = mapping_tagged(mapping, PAGECACHE_TAG_WRITEBACK)
         => return radix_tree_tagged(&mapping->i_pages, tag);
      ## 设置该page tag为writeback
      => radix_tree_tag_set(&mapping->i_pages, page_index(page),
            PAGECACHE_TAG_WRITEBACK);
      ## 支持account writeback
      => if bdi_cap_account_writeback(bdi)
         => inc_wb_stat()
      ## mapping 有inode（backlog dev) 并且之前没有在radix tree 中tag
      ## writeback
      => if mapping->host && !on_wblist
         => sb_mark_inode_writeback(mapping->host)
            ## 串联到 sb->s_inode_wb 上
            => list_add_tail(&inode->i_wb_list, &sb->s_inode_wb)
```
-->
