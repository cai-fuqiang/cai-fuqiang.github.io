---
layout: post
title:  "readahead"
author: fuqiang
date:   2024-10-10 16:10:00 +0800
categories: [mm,readahead]
tags: [readahead]
---

# NOTE
## readahead 注释翻译

```
On-demand readahead design.

> on-demand 按需

The fields in struct file_ra_state represent the most-recently-executed
readahead attempt:

                       |<----- async_size ---------|
    |------------------- size -------------------->|
    |==================#===========================|
    ^start             ^page marked with PG_readahead

To overlap application thinking time and disk I/O time, we do
`readahead pipelining': Do not wait until the application consumed all
readahead pages and stalled on the missing page at readahead_index;
Instead, submit an asynchronous readahead I/O as soon as there are
only async_size pages left in the readahead window. Normally async_size
will be equal to size, for maximum pipelining.

> 为了重叠应用程序的thinking time 和磁盘 I/O 时间，我们采用“预读流水线”的方式：
> 不要等到应用程序消耗完所有的预读页面，并在 readahead_index 处因缺少页面而停滞；
> 而是在预读窗口中仅剩下 async_size 个页面时，就立即提交一个异步的预读 I/O 操作。
> 通常，为了实现最大化的流水线效果，async_size 将等于 size。

In interleaved sequential reads, concurrent streams on the same fd can
be invalidating each other's readahead state. So we flag the new readahead
page at (start+size-async_size) with PG_readahead, and use it as readahead
indicator. The flag won't be set on already cached pages, to avoid the
readahead-for-nothing fuss, saving pointless page cache lookups.

> 在交错的顺序读取中，同一文件描述符上的并发流可能会使彼此的预读状态失效。
> 因此，我们在 (start + size - async_size) 位置的新预读页面上标记 PG_readahead，
> 并将其用作预读指示器。该标记不会设置在已经缓存的页面上，以避免不必要的预
> 读操作，从而节省无意义的页面缓存查找。

prev_pos tracks the last visited byte in the _previous_ read request.
It should be maintained by the caller, and will be used for detecting
small random reads. Note that the readahead algorithm checks loosely
for sequential patterns. Hence interleaved reads might be served as
sequential ones.

> prev_pos 跟踪上一个读取请求中最后访问的字节。它应由调用方维护，并用
> 于检测小的随机读取。请注意，预读算法对顺序模式的检测较为宽松。因此，
> 交错的读取可能会被当作顺序读取来处理。

There is a special-case: if the first page which the application tries to
read happens to be the first page of the file, it is assumed that a linear
read is about to happen and the window is immediately set to the initial size
based on I/O request size and the max_readahead.

> 有一个特殊情况：如果应用程序尝试读取的第一页正好是文件的第一页，则会假设
> 即将进行线性读取，并立即将窗口设置为初始大小，依据 I/O 请求大小和 
> max_readahead 来确定。

The code ramps up the readahead size aggressively at first, but slow down as
it approaches max_readhead.

> 代码在开始时会积极地增加预读大小，但当接近 max_readahead 时会逐渐放缓速度。
```
