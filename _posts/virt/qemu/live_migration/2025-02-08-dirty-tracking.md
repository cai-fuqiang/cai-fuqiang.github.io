---
layout: post
title:  "KVM dirty tracking"
author: fuqiang
date:   2025-02-08 22:20:00 +0800
categories: [live_migration]
tags: [live_migration]
---

<!-- 目录-->

- [abstract](#abstract)
- [dirty tracking hardware support](#dirty-tracking-hardware-support)
  + [D flag in pte](#d-flag-in-pte)
  + [write-protected]()
  + [PML]()
- [Q & A]()
  + [tracking and stop tracking]()
  + [how to tracking hugetlb dirty]()
- [API -- bitmap]()
- [具体流程]()
  + [prepare]()
  + [enable dirtylog tracking]()
  + [enable dirty tracking]()
  + [tracing page to be dirty and record it]()
  + [get dirty page to userspace]()
    + [get and sync dirty log -- old interface]()
    + [split get and sync dirty log -- KVM_CAP_MANUAL_DIRTY_LOG_PROTECT]()
      + [get dirty log]()
      + [sync dirty log]()


## abstract

KVM dirty tracking用来跟踪在某一时间段内，有哪些page 从clean 变为 dirty,
然后将信息传递给qemu，qemu会对这些dirty page进行一些处理（例如热迁移会做
save page动作，将dirty page 发送到目的端.

我们首先会来看下，硬件端对于脏页是如何跟踪的。硬件提供了多种方式可以做这个
事情，我们来看下KVM侧用到了哪些，以及其优缺点。

然后我们会来看下KVM和QEMU交互的API。API目前有两套:
* dirty-bitmap
* dirty-ring

在本文中，以`dirty-bitmap`为例子讲述，dirty-ring我们之后放到其他文章中。

最后，我们结合代码来看下整个过程的细节。


## dirty tracking hardware support

以intel硬件为例，目前dirty tracking有三种方式
+ D flag in pte
+ write-protected
+ PML

目前, KVM用到了后两个，我们先介绍下 D flag，再来思考下，为什么不能通过tracking
D flag，来tracking page dirty

### D flag in pte


在介绍这些feature之前，我们先来思考一个问题

<font color="red" size=5><strong><em>Q: KVM 脏页跟踪的需求</em></strong></font>

（需求决定方案嘛)

1. hardware notify host

   一般来说，查看一个object状态是否改变，一般有两种方式:
   * polling
   * notify

   而对于KVM来说，polling动作似乎代价很大, 首先硬件得支持将dirty信息save下来，


   在guest写page时, 需要hardware 通知 KVM:
   _hey, VMM, guest write a page, you should mark it to dirty_

![tu  2](./pic/dirtypage_tracking_struct.svg)

![tu  1](./pic/dirtypage_tracking_all.svg)

## 相关引用
1. [PML]()
2. [KVM ]()
3. [dirty-ring]()
4. [KVM同步脏页原理- huang yong](https://blog.csdn.net/huang987246510/article/details/108348207?spm=1001.2014.3001.5501)
