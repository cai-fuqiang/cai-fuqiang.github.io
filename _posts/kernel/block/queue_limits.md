## `queue_limits`

每个`request_queue`会维护一个`queue_limits` struct来描述block device
的硬件参数。

```cpp
struct request_queue {
  ...
  struct queue_limits limits;
  ...
};
```

其中有部分在`/sys/block/xxx/queue/` 下导出。

```sh
[root@A06-R08-I134-73-919XB72 openeuler-2203]# ls /sys/block/sda/queue/ |head -4
add_random
atomic_write_boundary_bytes  ## 对应atomic_write_boundary_sectors
atomic_write_max_bytes       ## 对应atomic_write_max_sectors
atomic_write_unit_max_bytes  ## 对应atomic_write_unit_max
...
```

### block_size

#### logical_block_size

> This is the smallest unit the storage device can
> address. It is typically 512 bytes.
{: .prompt-ref}

#### physical_block_size

> This is the smallest unit a physical storage device can
> write atomically.  It is usually the same as the logical
> block size but may be bigger.  One example is SATA
> drives with 4KB sectors that expose a 512-byte logical
> block size to the operating system.  For stacked block
> devices the physical_block_size variable contains the
> maximum physical_block_size of the component devices.
{: .prompt-ref}

这是物理存储设备可以原子性写入的最小单元。它通常与逻辑块大小相同，但也可能
更大。例如，某些带有4KB扇区的SATA硬盘会向操作系统呈现512字节的逻辑块大小。
对于`stacked block device`，physical_block_size 变量包含其组件设备中的最大
physical_block_size。

### discard

#### discard_granularity

> Devices that support discard functionality may have
> internal limits on the number of bytes that can be
> trimmed or unmapped in a single operation. Some storage
> protocols also have inherent limits on the number of
> blocks that can be described in a single command. The
> discard_max_bytes parameter is set by the device driver
> to the maximum number of bytes that can be discarded in
> a single operation. Discard requests issued to the
> device must not exceed this limit. A discard_max_bytes
> value of 0 means that the device does not support
> discard functionality.

支持丢弃（discard）功能的设备在一次操作中可以被修剪（trim）
或解除映射（unmap）的字节数可能有内部限制。一些存储协议在
单个命令中也限制了能描述的块数。discard_max_bytes 参数由设备
驱动程序设置，表示一次操作中可以被丢弃的
最大字节数。发送给设备的丢弃请求不能超过此限制。如果
discard_max_bytes 的值为0，表示该设备不支持丢弃功能。

> NOTE
>
> 一般固态会支持(virtio-blk 也支持)
{: .prompt-tip}

### sector limit

#### max_dev_sectors

> Some devices report a maximum block count for READ/WRITE requests.

单个request 大小上限, 目前只有scsi设备有这个限制

#### max_hw_sectors

> This is the maximum number of kilobytes supported in a single data transfer.

单个 DMA SG 操作的大小上限, 往往是DMA controller 的硬件属性

对应`max_hw_sectors_kb` sysfile

#### max_sectors

> This is the maximum number of kilobytes that the block layer will allow
> for a filesystem request. Must be smaller than or equal to the maximum
> size allowed by the hardware.

可以看到这个是一个软限制, filesystem request 到 block layer 的限制，必须小于
等于 `max_hw_sectors`

总之这个是`block layer` 入口, 当做split动作时需要去衡量的值; 并且merge 时，也不能
超过改值.

#### chunk_sectors

> This has different meaning depending on the type of the block device.
> For a RAID device (dm-raid), chunk_sectors indicates the size in 512B sectors
> of the RAID volume stripe segment. For a zoned block device, either host-aware
> or host-managed, chunk_sectors indicates the size in 512B sectors of the zones
> of the device, with the eventual exception of the last zone of the device which
> may be smaller.

不同的硬件有不同的来源:

* RAID device: RAID volume stripe segment  大小
* zoned block device: devices 的 zones 大小
* nvme: NOIOB 参数<sup>1</sup>

无论是什么来源，硬件/驱动要求block层最好不要超过这个界限，如果超过了，需要block 层
split(bio merge 同理)

### segment limit

sector limit 的限制往往是对一个request的限制，其限制通常来自于块存储设备。
而`segment limit`的限制通常来自于`DMA controller` 用来限制 physical segment
的数量，或者单个`segment`大小

#### max_segments

> Maximum number of segments of the device.

physical segment 数量的上限

在bio 与 request merge 或者request 之间 merge，(其都是merge 到一个request  -- 将bio
merge到一个bio list中), 往往会造成 io vector 增加，所以其需要根据该值判断是否可以merge。

#### max_segment_size

> Maximum segment size of the device.

单个physical segment 也存在限制.

如果两个bio 中的两个io vec地址上是连续的，理论上可以merge 成一个，但是需要判断merge后的io vec
大小，是否超过此限制

#### seg_boundary_mask

这个描述了 DMA controller 自身的寻址能力的限制, 例如有的DMA controller 只能有32bit寻址(低4G),
如果用于DMA buffer 超过了这个范围，往往会通过 IOMMU/swiotlb 解决这个问题。

#### virt_boundary_mask

virt_boundary_mask 的概念最初来源于 nvme，例如 nvme 中要求一个 request 包含的所有 physical
segment 中<sup>1</sup>

* 除了第一个 physical segment，其余 physical segment 的起始地址必须按照 PAGE_SIZE 对齐
* 同时除了最后一个 physical segment，其余 physical segment 的末地址也必须按照 PAGE_SIZE 对齐

> 也就是说, 整个segment ${[a,b], [c,d] , [e,f]}$, 除了 $a, f$, 不需要对齐，其他的都需要对齐.
{: .prompt-tip}

## bio merge/split code

### blk_mq_submit_bio

```sh
blk_mq_submit_bio
=> __bio_split_to_limits
   => case REP_OP_READ, REP_OP_WRITE
      => if bio_may_need_split {
            ## 这个规定了每个request不要超过的大小, 如果其有值，
            ## 可能单个segment 就有可能需要split
            => if lim->chunk_sectors
               => return true
            ## 多个vec 的话，可能会超过segment number的限制
            => if bio->bi_vcnt != 1
               => return true
            ## 这个没搞懂
            => return bio->bi_io_vec->bv_len + bio->bi_io_vec->bv_offset >
                     lim->min_segment_size
         }
         => bio_split_rw
           => return bio_submit_split(bio,
                bio_split_rw_at(bio, lim, nr_segs,
               get_max_io_size(bio, lim) << SECTOR_SHIFT));
=> blk_mq_bio_issue_init(q, bio);
=> blk_mq_attempt_bio_merge(q, bio, nr_segs)
   => if (!blk_queue_nomerges(q) && bio_mergeable(bio))
      ## 先从 plug 队列 merge
      => if (blk_attempt_plug_merge(q, bio, nr_segs))
         => return true
      ## 如果没有merge成功，再merge到调度队列 -- 软队列
      => if (blk_mq_sched_bio_merge(q, bio, nr_segs))
         => return true
```

### bio_split_rw

```sh
bio_split_rw
=> bio_submit_split(bio,
  bio_split_rw_at(bio, lim, nr_segs,
   get_max_io_size(bio, lim) << SECTOR_SHIFT));
```

get_max_io_size

```sh
## 获取单个request所能提交的最大的sector数量
get_max_io_size
=> unsigned pbs = lim->physical_block_size >> SECTOR_SHIFT;
=> unsigned lbs = lim->logical_block_size >> SECTOR_SHIFT;
=> bool is_atomic = bio->bi_opf & REQ_ATOMIC;
## 关于atomic req 有一个自己的字段规定其boundary_sectors -- 
## atomic_write_boundary_sectors
## 否则取boundary_sectors
=> unsigned boundary_sectors = blk_boundary_sectors(lim, is_atomic);
   => if (is_atomic && lim->atomic_write_boundary_sectors)
      => return lim->chunk_sectors
## 前两个条件都是特殊处理
=> if (bio_op(bio) == REQ_OP_WRITE_ZEROES)
   => max_sectors = lim->max_write_zeroes_sectors;
=> else if (is_atomic)
  => max_sectors = lim->atomic_write_max_sectors;
## 以max_sectors为基准
=> else
  => max_sectors = lim->max_sectors;
=> if (boundary_sectors) {
   ## 这里其实是划分各个chunk, 每个request不能超过chunk的边界，
   ## 举个例子:
   ##
   ## 如果bi_sector为31, size为8, 而boundary_sector 为8, 那么
   ## 就需要, 先提交 (8 - (31 & 7)) = 1, 先提交1个，在提交7个。
   => max_sectors = min(max_sectors,
      blk_boundary_sectors_left(bio->bi_iter.bi_sector,
           boundary_sectors));
## physical block size, 规定的是最小的寻址粒度
=> start = bio->bi_iter.bi_sector & (pbs - 1);
=> end = (start + max_sectors) & ~(pbs - 1)

## 如果块够大（够一个物理快), 则按照物理块对齐)
=> if end > start
   => return end - start;
## 如果不够大则按照逻辑块对齐
=> return max_sectors & ~(lbs-1)
```

bio_split_rw_at

```sh
## 上面得到了该bio 最大的sector(bytes), 该函数，则取获取该bio 在哪里split
bio_split_rw_at
## segs: [out] number of segments in the bio with the first half of the sectors
## @max_bytes: [in] maximum number of bytes per bio
## len_align_mask: [in] length alignment mask for each vector
=> bio_split_io_at(bio, lim, segs, max_bytes, lim->dma_alignment);
   => bio_for_each_bvec(bv, bio, iter)
      ## 每个segment的起始地址必须满足 dma_alignment, 包括len也需要满足
      ## len_align_mask, 对于该流程来说，起始地址结束地址都需要满足 dma_alignment
      => if (bv.bv_offset & lim->dma_alignment ||
           bv.bv_len & len_align_mask)
         => return -EINVAL
      ## 第一个不用处理
      => if (bvprvp && bvec_gap_to_prev(lim, bvprvp, bv.bv_offset))
           ## 该函数用来限制 -- queue_limits->virt_boundary_mask
           ## bvprvp 表示当前seg的前一个segment
           => bvec_gap_to_prev()
              => if (!lim->virt_boundary_mask)
                 => return false
              => return __bvec_gap_to_prev(lim, bprv, offset);
                 ## 我们分为三类 segments
                 ## first segment: 只需要segment end 对齐,
                 ## last segments: 只需要segment start对齐
                 ## middle segment: 需要segment start end 都对齐
                 ##
                 ## 检查prev seg end 和当前seg的start, 最终能达到上面效果
                 => return (offset & lim->virt_boundary_mask) ||
                    ((bprv->bv_offset + bprv->bv_len) & lim->virt_boundary_mask);
            =>  {
                  ## seg不能超过最大的seg number
                  ## bytes 不能超过最大的 max_bytes限制
                  ## seg 末尾不能超过  min_segment_size
                  if (nsegs < lim->max_segments &&
                      bytes + bv.bv_len <= max_bytes &&
                      bv.bv_offset + bv.bv_len <= lim->min_segment_size) {
                   nsegs++;
                   bytes += bv.bv_len;
                  } else {
                   ## 在做一次检查，判断其是否需要split
                   if (bvec_split_segs(lim, &bv, &nsegs, &bytes,
                     lim->max_segments, max_bytes))
                    goto split;
                  }
                }
         => goto split
      ## in foreach bvec
    => bvprv = bv;
    => bvprvp = &bvprv;
   ## end foreach vec
   => *segs = nsegs
   => return 0
   LABEL_split:
   ## 要求是split，但是现在却分割下发，不大行
   => if (bio->bi_opf & REQ_ATOMIC)
    => return -EINVAL;
   ## TODO: 这个不清楚为什么不支持 
   => if (bio->bi_opf & REQ_NOWAIT)
     => return -EAGAIN;
   ## 在此seg处分割
   => *segs = nsegs;
   ## 按照logical_block_size 向下对齐, 这样能够保证每个bio都会按照
   ## logical block size对齐，即使没有完全用尽硬件限制
   ##
   ## 然而有一些情况可能导致其byte的值为0:
   ## e.g.
   ## + seg太多了，达到了限制, 这样凑不齐 logical block size
   ## + 存在virtual boundary gap, 但是经split之后，达到了一个较小的
   ##   block size
   => bytes = ALIGN_DOWN(bytes, bio_split_alignment(bio, lim));
      => return -EINVAL
   => bio_clear_polled(bio);
   => return bytes >> SECTOR_SHIFT;
```

bio_submit_split

```sh
bio_submit_split
=> if (unlikely(split_sectors < 0))
   => bio->bi_status = errno_to_blk_status(split_sectors);
   => bio_endio(bio);
   => return NULL
=> if (split_sectors)
   => bio = bio_submit_split_bioset(bio, split_sectors,
    &bio->bi_bdev->bd_disk->bio_split);
   ## 我这里好不容易，将bio split 了, 下面还要merge ？ 没门
   => if (bio)
      => bio->bi_opf |= REQ_NOMERGE;

bio_submit_split_bioset
=> struct bio *split = bio_split(bio, split_sectors, GFP_NOIO, bs);
   => split = bio_alloc_clone(bio->bi_bdev, bio, gfp, bs)
      ## 从bio set 中分配一个bio
      => bio = bio_alloc_bioset(bdev, 0, bio_src->bi_opf, gfp, bs);
      => bio_clone()
      => bio->bi_io_vec = bio_src->bi_io_vec;
   ## 新搞出来的split 的bio, bio size  按照split sector设置
   => split->bi_iter.bi_size = sectors << 9
   ## 旧的bio则需要前进split bio的bio大小
   => bio_advance(bio, split->bi_iter.bi_size);
=> bio_chain(split, bio);
   ## 虽然是两个bio，但是block层之上，例如vfs层等待的是org bio complete
   ## 所以这里需要做一些额外操作，这里先不表
   => bio->bi_private = parent;
   => bio->bi_end_io> = bio_chain_endio;
   => bio_inc_remaining(parent);
```

### merge

#### blk_attempt_plug_merge

blk_attempt_plug_merge

```sh
blk_attempt_plug_merge
=> if (!plug || rq_list_empty(&plug->mq_list))
   ## 前无古人
   => return false
=> rq = plug->mq_list.tail;
## 这里获取最新添加的
   ## 是一个request queue, 就尝试merge
=> if (rq->q == q)
   => return blk_attempt_bio_merge(q, rq, bio, nr_segs, false) == BIO_MERGE_OK;
   ## 如果merge失败那就GG, 为什么? 因为要保证同一个request queue 中io的顺序

-> else if(!plug->multiple_queues)
   => return false;
## 注意，这里是从前向后遍历, 也就是从新向老遍历.
=> rq_list_for_each(&plug->mq_list, rq)
   => if (rq->q != q)  continue
   ## 这里其实也很奇怪, 前面是取最后一个，现在是从前向后遍历merge, 理论上如果不是一个
   ## request_queue, 应该在从后向前取最后一个（最新添加的，同一个request queue), 但是
   ## 这里却是从头向前遍历，效果感觉并不好
   ##
   ## 作者在commit 3中 给出的解释是:
   ##
   ## Ideally the latter scan would be a backwards scan of the list, but as it 
   ## currently stands, the plug list is singly linked and hence this isn't
   ## easily feasible
   ##
   ## 目前的单链表，反向遍历并不容易, 所以直接从头检查吧，检查到一个相同request
   ## queue, 但是不能merge的，直接GG，放弃!
   ##
   ## 而 4 链接中, 似乎有人遇到了性能倒退。不确定是否和这个强行正向遍历有关系.
   => if (blk_attempt_bio_merge(q, rq, bio, nr_segs, false) == BIO_MERGE_OK)
      => return true;
   => break
=> return false
```

blk_attempt_bio_merge

```sh
blk_attempt_bio_merge
=> if !blk_rq_merge_ok() return BIO_MERGE_NONE
## blk_try_merge 会根据该rq是否是discard, 如果是discard是否可以做discard层面的merge
## 另外如果不是discard，则去看该io是否和其他io是连续的，连续的方式有两种:
##
## * ELEVATOR_BACK_MERGE; request -- bio 是连续的，bio可以merge到 request 末尾
## * ELEVATOR_FRONT_MERGE: bio -- request 是连续的，bio可以merge到request 开始
## 不展开该函数.
=> switch (blk_try_merge(rq, bio))
   => case  ELEVATOR_BACK_MERGE:
      => if (!sched_allow_merge || blk_mq_sched_allow_merge(q, rq, bio))
         => return bio_attempt_back_merge(rq, bio, nr_segs);
   => case  ELEVATOR_FRONT_MERGE:
      => if (!sched_allow_merge || blk_mq_sched_allow_merge(q, rq, bio))
         => return bio_attempt_front_merge(rq, bio, nr_segs);
  => case ELEVATOR_DISCARD_MERGE:
     => return bio_attempt_discard_merge(q, rq, bio);
```

以`bio_attempt_back_merge` 为例:

```sh
bio_attempt_back_merge
## 是否可以向后merge
=> if (!ll_back_merge_fn(req, bio, nr_segs))
   => return BIO_MERGE_FAILED;
=> rq_qos_merge(req->q, req, bio);
=> {
      ## 将该bio merge到request中
      req->biotail->bi_next = bio;
      req->biotail = bio;
      req->__data_len += bio->bi_iter.bi_size;
   }
=> blk_account_io_merge_bio(req)
```

ll_back_merge_fn

```sh
ll_back_merge_fn
=> if (req_gap_back_merge(req, bio))  return 0;
   ## 返回true，表示不能merge
   => return bio_will_gap(req->q, req, req->biotail, bio);
      ## 如果不是这两者那可以merge
      => if (!bio_has_data(prev) || !queue_virt_boundary(q))
         => return false
      => if (prev_rq)
         => bio_get_first_bvec(prev_rq->bio, &pb);
      -- else
         => if (prev_rq)
          => bio_get_first_bvec(prev_rq->bio, &pb);
        -- else
          => bio_get_first_bvec(prev, &pb);
```

## 参考链接

1. [BLOCK 层这么多参数都是什么意思？](https://developer.aliyun.com/article/784610)
2. [struct queue_limits结构体参数学习](https://blog.csdn.net/qq_38158479/article/details/134812061)
3. [KERNEL DOC: sysfs-block](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-block)

## commit

1. block: only check previous entry for plug merge attempt
   * commit d38a9c04c0d5637a828269dccb9703d42d40d42b
   * Author: Jens Axboe <axboe@kernel.dk>
   * Date:   Thu Oct 14 07:24:07 2021 -0600
   * 比较老的实现，是遍历整个链表,
2. block: ensure plug merging checks the correct queue at least once
   * commit 5b2050718d095cd3242d1f42aaaea3a2fec8e6f0
   * Author: Jens Axboe <axboe@kernel.dk>
   * Date:   Fri Mar 11 10:21:43 2022 -0700
   * 提交1 只是检查最后一个 request, 但是在raid模式下，其io往往是在多个设备
     中交错的。所以这里做了另外的一些检查，只要检查到同一设备的最后一个请求
     无法merge，那就不merge
3. block: use plug request list tail for one-shot backmerge attempt
   * commit 961296e89dc3800e6a3abc3f5d5bb4192cf31e98
   * Author: Jens Axboe <axboe@kernel.dk>
   * Date:   Wed Jun 11 08:48:46 2025 -0600
4. [\[PATCH\] Revert "block: don't reorder requests in blk_add_rq_to_plug"](https://lore.kernel.org/linux-block/20250611121626.7252-1-abuehaze@amazon.com/)

## TODO

1. [ ] 对 commit 4 的更深层次的调研
