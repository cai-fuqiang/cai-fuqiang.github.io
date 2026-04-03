# blk_plug

## 顺序

plug队列顺序应该是`FIFO`, 至少是从plug->`ctx queue`, 或者hctx，或者
direct dispatch 的顺序保持`FIFO`（历史上的设计可能从plug队列取是
`LIFO`, 但是其也是添加到了`LIFO`队列，负负得正)

首先向 plug 队列加的时候:

```sh
blk_add_rq_to_plug
## 向tail加
=> rq_list_add_tail(&plug->mq_list, rq);
```

flush plug代码:

```sh
blk_mq_flush_plug_list
=> blk_mq_dispatch_queue_requests
   => blk_mq_run_dispatch_ops(q, __blk_mq_flush_list(q, rqs))
      => __blk_mq_flush_list
         => q->mq_ops->queue_rqs(rqs);

## 以virtio-blk为例
virtio_queue_rqs
### 从头部获取, 获取的最老的
=> while ((req = rq_list_pop(rqlist)))
   => if (vq && vq != this_vq)
      => virtblk_add_req_batch(vq, &submit_list);
         ## 从head获取, 获取最老的
         => while ((req = rq_list_pop(rqlist)))
            ...
      => if (virtblk_prep_rq_batch(req))
         ## 加到另一个队列的tail
         => rq_list_add_tail(&submit_list, req);
   ...
```

所以在最新代码中，所有的`rq_list` 均保持了`FIFO`的性质，方便走读代码。

## interface

### blk_add_rq_to_plug

```sh
blk_add_rq_to_plug
=> struct request *last = rq_list_peek(&plug->mq_list);
## 第一个吃到西红柿的靓仔
##
## TODO 如果blk_queue_nomerges()配置了
=> if (!plug->rq_count)
   => trace_block_plug(rq->q);
## 实话说这里没有看懂， 参考 commit 1
## 这里会考虑blk_rq的大小, 如果都是一些大请求，频繁的plug
## 反而会造成磁盘利用率降低
##
## 另外考虑下nomerge, 目前的做法是, 如果request_queue 是
## nomerges, 则不需要检查, 如果是 mergeable, 则需要对前一个
## 请求做检查,  这里我没有想通.
=> else if (plug->rq_count >= blk_plug_max_rq_count(plug) ||
     (!blk_queue_nomerges(rq->q) &&
      blk_rq_bytes(last) >= BLK_PLUG_FLUSH_SIZE))
   => blk_mq_flush_plug_list()
## 表示plug 中有多个队列
=> if (!plug->multiple_queues && last && last->q != rq->q)
   => plug->multiple_queues = true;
=> rq_list_add_tail(&plug->mq_list, rq);
=> plug->rq_count++;
```

## TODO

* [ ] `blk_add_rq_to_plug()` 中 `blk_queue_nomerges()`, 不知道在搞啥

## commit

1. blk-mq: immediately dispatch big size request
   * commit 600271d9000027c013c01be87cbb90a5a18c5c3f
   * Shaohua Li <shli@fb.com>
   * Thu Nov 3 17:03:54 2016 -0700
   * [mail](https://lore.kernel.org/all/05e8cb8c7e09903c7db36e81a6bbd0b39b24deff.1478217670.git.shli@fb.com/)

2. block: change plugging to use a singly linked list
   * commit : bc490f81731e181b07b8d7577425c06ae91692c8
   * Jens Axboe <axboe@kernel.dk>
   * Mon Oct 18 10:12:12 2021 -0600
