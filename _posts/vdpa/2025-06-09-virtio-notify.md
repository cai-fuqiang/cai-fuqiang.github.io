---
layout: post
title:  "virtio notify"
author: fuqiang
date:   2025-06-09 18:10:00 +0800
categories: [virt,io_virt]
tags: [io_virt]
---

## virtio feature : VIRTIO_RING_F_EVENT_IDX

我们这里抽象下，先定义一个producer, consumer的模型, 将
event_idx定义为head，将vring.idx定义为tail, 即
```
consumer modify head
producer modify tail(和vring.idx一样，表示producer下次要存储数据的位置)
```

整个逻辑如下:

consumer:
```
while have_notify():
   while head < tail:
     handle data ring[head]
     head++
     STORE head
```
producer: 
```
while get_put_data() as data:
   put data into ring[tail]
   t1 = get_tail_last_notify()
   t2 = tail

   tail++

   if head in [t1, t2):
      send_notify()

   set_tail_last_notify(tail)
```

整个的代码逻辑是:

1. **_producer_**

   其在收到notify后, 观测到`head < tail`, 就会继续处理循环处理ring中的数据.

2. **_consumer_**

   假定producer一定满足1, 所以其在更新tail后，会观测, head 是否在
   本次更新后的tail，和上次tail的范围内`[t1, t2)`

   + head < t1: 说明 consumer 还在处理(x, t1) 范围内的数据，处理完(x, t1) 范围内的数据
     后, 按照1的原则，肯定还会继续处理[t1, t2] 范围内的数据。所以, 无需notify.
   + head ∈ [t1, t2): 说明, consumer 在过去某个时刻追上了head, 追上后，又可能因
       producer这边tail还没有更新, 已经退出loop，需要等待新的notify 后，才会继续处理.
   + head == t2: 说明: consumer 发动秘术"一日千里", 在produer执行完`tall++`后, 执行
     `if head in [t1, t2)`之前, 就已经把该ring[t2-1]处理完，并且更新完head->t2, 十分
     迅速, 无需notify.
   + head > t2: consumer发动锦囊: "无中生有", producer可以不跟他玩了。(consumer
       有BUG)

从上面流程, 可以看出，双方都需要观测对方更新的数据后, 再继续做判断, 也就是
```
producer              consumer(考虑下次的loop)
STORE tail            STORE head
LOAD head             LOAD tail
```
像这种`store->load`操作即便是在x86-TSO内存模型下，也是允许乱序的:

我们举个两个例子，分别来看下producer 和consumer 乱序，所带来的影响
初始状态和之后的动作:
* initial:
  + tail = 1
  + head = 0
  + get_tail_last_notify() = 1(说明上次notify后, consumer还没有处理)
* producer 侧动作:

  再次向ring放入一个desc，更新tail

* producer out of order:
  ```cpp
  producer                     consumer

  tail(1)++

  /* but STORE inst
   * have not COMMIT,
   * still in write 
   * buffer
   */

  if head(0) in [t1(1), t2)
     DON'T SEND NOTIFY
                               get data ring[head(0)]

                               head(0)++
                               if head(1) == tail(1)  // stale data
                                  break_LOOP
  COMMIT STORE tail
  ```

* consumer out of order

  ```c
  producer                     consumer
                               get_data_ring[head(0)]

                               head(0)++
                               /* but STORE inst
                                * have not COMMIT,
                                * still in write 
                                * buffer
                                */
                               if head(1) == tail(1)
                                  break_LOOP
  tail(1)++
  //head is stale
  if head(0) in [t1(1), t2)
    DON'T SEND NOTIFY
                               COMMIT STORE head
  ```

最终的状态都是有问题的:
```cpp
tail = 2
head = 1

no pending notify
```

这里，我们仅以kernel代码为例，查看kenrel 作为guest driver, 作为avail_ring生产者，
以及used_ring的消费者，是如何添加memory_barrier的.

## kernel code


* avail vring producer
  ```cpp
  @@ -308,9 +308,9 @@ bool virtqueue_kick_prepare(struct virtqueue *_vq)
          bool needs_kick;
  
          START_USE(vq);
  -       /* Descriptors and available array need to be set before we expose the
  -        * new available array entries. */
  -       virtio_wmb(vq);
  +       /* We need to expose available array entries before checking avail
  +        * event. */
  +       virtio_mb(vq);
  
          old = vq->vring.avail->idx - vq->num_added;
          new = vq->vring.avail->idx;
  ```
  该patch来自于:

  [virtio: correct the memory barrier in virtqueue_kick_prepare()](https://github.com/torvalds/linux/commit/a72caae21803b74e04e2afda5e035f149d4ea118)

  是对`ee7cd89("virtio: expose added descriptors immediately")`的fix, `ee7cd89`
  patch将`virtio_mb` 修改为`virtio_wmb`, 但是wmb的作用是保证`store-store`的顺序，
  而这里需要保证`store-load`的顺序, 即`STORE(avail_idx)-LOAD(avail_event_idx)`之
  间的顺序.

  所以该patch，又改了回来

* used vring consumer

  ```diff
  @@ -324,6 +331,14 @@ void *virtqueue_get_buf(struct virtqueue *_vq, unsigned int *len)
          ret = vq->data[i];
          detach_buf(vq, i);
          vq->last_used_idx++;
  +       /* If we expect an interrupt for the next entry, tell host
  +        * by writing event index and flush out the write before
  +        * the read in the next get_buf call. */
  +       if (!(vq->vring.avail->flags & VRING_AVAIL_F_NO_INTERRUPT)) {
  +               vring_used_event(&vq->vring) = vq->last_used_idx;
  +               virtio_mb();
  +       }
  +
          END_USE(vq);
          return ret;
   }
  ```
  可以看到, 在STORE used_event后, 加了一个内存屏障，从而保证`STORE
  used_event_idx - LOAD used_idx`之间的顺序.
