---
layout: post
title:  "rcu - overflow"
author: fuqiang
date:   2025-12-29 20:26:00 +0800
categories: [os, synchronization]
tags: [os, synchronization, rcu]
media_subpath: /_posts/synchronization/rcu
---

## RCU 基本概念

RCU (Read-Copy update) 是一种同步机制, 在Linux内核中大放异彩。用于多读少写的同步
场景。

基本原理是, 将写动作氛围下面几个步骤(正如其完整的英文名所示):

* copy
* write
* update

即在写入时首先copy一个副本, 然后在该副本上完整修改，在替换原来的就数据。该机制优秀
的点在于其对读者访问特别友好:

![copy-write-update](pic/copy-write-update.png)

**读者访问不需要加锁，不需要原子操作, 甚至不需要内存屏障(Alpha 除外)**

但是对于写者就没有那么友好, 首先 copy 动作需要写者来做，另外，update后替换旧副本释放
旧副本资源，也增加了写者复杂度。如果是同步操作的话，甚至需要写者阻塞等待读临界区
完成.

## 机制

RCU 的机制主要有以下三个部分<sup>1</sup>:

* Publish-Subscribe Mechanism (for insertion)
* Wait For Pre-Existing RCU Readers to Complete(for deletion)
* Maintain Multiple Versions of Recently Updated Objects (for readers)

### Publish-Subscribe Mechanism

在看rcu 的 insert 流程之前，我们先简单了解发布订阅机制（模式）概念:

发布订阅模式是一种消息传递模式, 用于将消息生成组件与消息消费组件解耦。其核心思想
是，发送者不与接受者直接通信，而是通过一个中间媒介（事件总线 / 主题中心）传递消息，
双方无需知道对方的存在，从而降低耦合度<sup>6, 7</sup>。

而对应于rcu而言，其中间媒介就是`critical resource`(可以理解为一个地址), 发布者和订阅
者通过相应的API去操作"中间媒介".

![rcu_publish_subscribe](pic/rcu_publish_subscribe.png)

> NOTE
>
> 上图来自<sup>2</sup>
{: .prompt-ref}

***

而对于rcu而言对于 updater 和reader 之间也提出了一些要求:

_读者可以看不到最新的更新，但是不能看到不完整的更新_。

例如下面的写者程序<sup>1</sup>
```cpp
  1 struct foo {
  2   int a;
  3   int b;
  4   int c;
  5 };
  6 struct foo *gp = NULL;
  7
  8 /* . . . */
  9
 10 p = kmalloc(sizeof(*p), GFP_KERNEL);
 11 p->a = 1;
 12 p->b = 2;
 13 p->c = 3;
 14 gp = p;
```
写者需要负责让读者看到的new publish foo 为 `(a: 1, b: 2, c: 3)` 的组合，不能是一个
中间状态。聪明的小伙伴可以想到，这是一个典型的内存模型（memory order)的问题。也就是
让`gp = p`的这个动作一定发生在p数据结构初始化之后。所以`gp = p`这个动作需要内存屏障进行
封装, 内核中用`rcu_assign_pointer(gp, p);` 实现.

(关于`rcu_assign_pointer(, )`的实现(内存屏障相关)，在 **TODO TODO TODO TODO** 中详细描述。

对于读者来说，也需要保证一定的内存顺序<sup>1</sup>, 例如下面的顺序:
```cpp
  1 p = gp;
  2 if (p != NULL) {
  3   do_something_with(p->a, p->b, p->c);
  4 }
```
这个程序看起来有内存顺序的问题么? 我们期望的是`p->a`, `p->b`, `p->c`的组合是一致
性的，但是这三个值看起来是在获取到p的值之后才能获取, 而写者保证了p赋值时，
`p->x`已经更新, 所以直观上来说，这个程序不会有问题。不需要任何内存屏障。

但是, 实际上并不是这样。文章<sup>1</sup>中提到了两个场景:
* alpha 架构推测执行优化
* value-speculation compiler optimizations

总之，在这些场景下，会在获取p 值之前，先获取到`p->a`, `p->b`, `p->c` 的值.
`value-speculation compiler optimizations` 优化比较直观，其会先推测p的值, 然后
获取`p->a, p->b, p->c`的值，然后在获取实际的 p的值，对比自己的猜测是否正确。

> 不过，这种优化我是不太理解.
>
> value-speculation compiler optimizations 类似于cpu的预测执行，但是预测执行会根据
> p的值选择保留还是放弃预测执行的结果。不影响最终的结果。
>
> 我这里能想到的编译器优化是:
> ```
> reader first read gp = 0xfffa [1, 2, 3]
>
> //write relase org gp, and update gp = 0xfffb [2,3,4]
>
> reader read gp again
> But reader don't read gp from memory instead of reg, so gp = 0xfffa, read old
> data.
> ```
> 按照上面的场景，需要让读操作为标注为voliate 即可.
{: .prompt-info}

我们上面定义的读操作定义为`Publish`, 写操作为`Subscribe`.

虽然rcu可以应用于各个场景，但是RCU的一个典型场景是链表。

Linux 为链表定义了一套RCU的版本， 并将这些`publish`, `Subscribe` 嵌入到
这些代码中。

#### list_add
```cpp
static inline void list_add_rcu(struct list_head *new, struct list_head *head)
{
       __list_add_rcu(new, head, head->next);
}
static inline void __list_add_rcu(struct list_head *new,
              struct list_head *prev, struct list_head *next)
{
        if (!__list_add_valid(new, prev, next))
                return;
        new->next = next;
        new->prev = prev;
        rcu_assign_pointer(list_next_rcu(prev), new);
        next->prev = new;
}
```
new是要添加的成员, 所以在publish之前，需要将其成员初始化完整.

那么问题来了, publish动作是对应是 对一个指针更新？那选择那个指针更新呢?
```
prev->next
```

Linux链表遍历是正向遍历，也就意味着，读者在遍历过程中只读取`entry->next`,
所以其保证，该object 初始化完成后(包括其object.list), 对 `prev->next` 执行
合理的publish动作即可.

> `list_next_rcu` 也有RCU的版本:
> ```cpp
> #define list_next_rcu(list)     (*((struct list_head __rcu **)(&(list)->next)))
> # define __rcu          __attribute__((noderef, address_space(__rcu)))
> ```
> 这里更像是做了一些编译器check **TODO**

#### loop

`list_for_each_rcu()`的代码:

```cpp
#define list_for_each_rcu(pos, head)              \
        for (pos = rcu_dereference((head)->next); \
             !list_is_head(pos, (head)); \
             pos = rcu_dereference(pos->next))
```

代码非常直接在获取`entry->next`时, 使用`rcu_dereference()`接口

#### del

关于del大家可以简单思考下, 其需要内存屏障来保序么? add 操作需要内存屏障是因为防
止object 更新在发布之后执行。而del操作不会在更改这个object。只是等着释放了。

```cpp
static inline void __list_del(struct list_head * prev, struct list_head * next)
{
    next->prev = prev;
    WRITE_ONCE(prev->next, next);
}
```

这里的`WRITE_ONCE`只是voliate 原语, 防止编译器优化, 例如读写撕裂(`Read/write
"tearing"`) <sup>8</sup>。


## 参考链接
1. [What is RCU, Fundamentally?](https://lwn.net/Articles/262464/)
2. [Linux 核心設計: RCU 同步機制](https://hackmd.io/@sysprog/linux-rcu#%E5%B0%8D%E6%AF%94%E5%85%B6%E4%BB%96-lock-free-%E5%90%8C%E6%AD%A5%E6%A9%9F%E5%88%B6)
3. [QEMU RCU implementation ](https://terenceli.github.io/%E6%8A%80%E6%9C%AF/2021/03/14/qemu-rcu)
4. [Using RCU (Read-Copy-Update) for synchronization](https://www.qemu.org/docs/master/devel/rcu.html)
5. [Hierarchical RCU](https://lwn.net/Articles/305782/#Review%20of%20RCU%20Fundamentals)
6. [发布订阅模式详解](https://mayouchen.blog.csdn.net/article/details/155784820)
7. [Publish–subscribe pattern](https://en.wikipedia.org/wiki/Publish%E2%80%93subscribe_pattern)
8. [WRITE_ONCE in linux kernel lists](https://stackoverflow.com/questions/34988277/write-once-in-linux-kernel-lists)
