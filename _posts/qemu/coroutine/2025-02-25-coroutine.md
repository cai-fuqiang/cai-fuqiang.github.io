--- 
layout: post
title:  "qemu coroutine"
author: fuqiang
date:   2025-02-25 11:00:00 +0800
categories: [qemu,coroutine]
tags: [qemu, qemu_coroutine, completed]
media_subpath: /_posts/qemu/coroutine
image: /pic/coroutine_all.svg
---


* [Introduction](#introduction)
* [Linux User Context Switch](#linux-user-context-switch)
* [qemu coroutine](#qemu-coroutine)
  + [协程状态机](#协程状态机)
  + [CREATE and INIT](#create-and-init)
  + [enter](#enter)
  + [switch](#switch)
  + [yield](#yield)
* [Use Case for QEMU](#user-case-for-qemu)

## Introduction

多线程和协程都可以用于并行编程，但是他们实现方式和使用场景
有很大的区别，我们来对比下:

|对比项|协程|多线程|
|---|---|---|
|实现方式|**在用户态单线程中，完成上下文切换**|内核态完成上下文切换|
|开销|**开销较低**|线程创建销毁，以及切换都需要进入内核态，<br>开销较高|
|并发|只能在单个线程中来回切换完成并发|**可以实现真正的并行处理（在多核cpu)**|
|调度(切换)|协程类似于非抢占式调度，<br>只能在主动切换|**线程可以在任何时刻被中断和切换**|
|程序复杂度|**协程处理同步和资源共享较简单**|多线程编程需要处理线程间的同步和资 <br>源共享问题, 复杂度更高, 往往需要借助系统api<br>(锁，信号量)|


使用场景上:

* 协程
  + 当应用程序主要是 I/O 密集型任务，如网络请求、文件操作等
  + 当需要高并发但不需要并行计算
* 使用多线程的场景
  + 当应用程序是 CPU 密集型任务，需要利用多核 CPU 的并行计算能力
  + 当需要处理大量需要同时执行的计算任务时

协程比较适合那种需要wait的任务, 例如上面提到的I/O 密集型任务(qemu中的
aio, 可以在协程中下发多个aio，然后等待io complete event)

我们举个例子:

![协程vs多线程](./pic/协程_vs_多线程.svg)

在该图中, 有两个cpu core, A进程有3个thread, 其中thread1和thread2在
cpu0上运行，thread 3 有四个协程，在cpu1上运行, task A 的计算负载可
以分别落在cpu 0 和cpu 1上, 这也是多线程的很大的优点: 可以最大化的利
用多核cpu的并行处理能力。

thread1和thread2其靠kernel的任务抢占机制，来共享cpu 0, 在任何时间都有
可能被对方抢占. 而thread3 中的各个协程则是 根据自己任务的完成情况，
或者当前任务是否需要等待而主动选择调度。

## Linux User Context Switch

我们需要思考下，context switch 完成哪些任务:

* init new task context
  + like pthread_create()
  + need init IP, SP(a new stack), Params
* context switch
  + save...
  + load...
* destroy

如果用户态要完成context switch，需要处理好上面所列的三件事。而这些事情涉及的东西
太底层了，如设置ip，如传参等等，所以libc中提供了`ucontext`系列接口来完成这些事情:

### ucontext
#### ucontext API

|API name|作用|
|---|---|
|getcontext(ucontext_t *ucp)|获取当前上下文, 保存到ucp中|
|setcontext(ucp)|切换到目标(ucp)上下文|
|makecontext(ucp, (*func)(), int argc, ...)|用来modify ucp, 下面详述|
|swapcontext(oucp, ucp)|saves current thread context <br>in oucp and makes *ucp the currently <br>active context.|

在执行makecontext()之前，需要做一些准备工作:
1. 调用 getcontext() 来init ucp, 
2. 需要为其分配stack, init ucontext_t.uc_stack 相关成员
   + ss_sp: 指向具体的堆栈地址
   + ss_size: 堆栈大小
   + ss_flags:
3. 设置`ucp->uc_link`参数，根据是否设置`ucp->uc_link` 来确定func() 返回时，
   所执行的动作:
   + NULL: 进程退出
   + 隐式调用 setcontext(ucp->uc_link)

我们编写一个例子来演示下，该接口的使用方法和效果

#### ucontext example

<details markdown=1 open>
<summary>测试程序展开</summary>

```cpp
#include <stdio.h>
#include <ucontext.h>
#include <stdlib.h>

#define STACK_SIZE  (4096 * 2)

void print_current_stack()
{
        unsigned long stack_pointer;
        __asm__("movq %%rsp, %0" : "=r"(stack_pointer));
        printf("stack pointer(%lx)\n",  stack_pointer);

}

void func(int a, int b)
{
        printf("the co exec, sum(%d)\n", a+b);
        printf("print co stack \n");
        print_current_stack();
        return;
}
int main()
{
    int ret;
        char *stack = (char *)malloc(STACK_SIZE);

        ucontext_t uc, old_uc;

        int a, b = 0;
        printf("the new stack is %p\n", stack);
        printf("print main stack:\n");
        print_current_stack();
        getcontext(&uc);
        uc.uc_stack.ss_sp = stack;
        uc.uc_stack.ss_size = STACK_SIZE;

        uc.uc_link = &old_uc;
        while(1) {
                printf("main co a(%d) b(%d)\n", a, b);
                makecontext(&uc, (void (*)(void))func, 2, a, b);
                printf("swap context\n");
                swapcontext(&old_uc, &uc);
                printf("swap context end\n");
                if (a++ == 3)
                        break;
                b=b+2;

        }

        return 0;
}
```

</details>

在`main`中jum构建一个循环，来在另一个上下文中调用`func()`, 并设置
返回的context为调用者(main())的context，这样`func()`返回后，
直接返回到`main()`的`while`的上下文, 继续执行循环。

<details markdown=1 open>
<summary>输出示例</summary>

输出如下:
```
the new stack is 0x9d22a0
print main stack:
stack pointer(7fff0939ee50)
main co a(0) b(0)
swap context
the co exec, sum(0)
print co stack
stack pointer(9d4250)
swap context end
main co a(1) b(2)
swap context
the co exec, sum(3)
print co stack
stack pointer(9d4250)
swap context end
main co a(2) b(4)
swap context
the co exec, sum(6)
print co stack
stack pointer(9d4250)
swap context end
main co a(3) b(6)
swap context
the co exec, sum(9)
print co stack
stack pointer(9d4250)
swap context end
```
</details>

由上图可见，`func()`和`main()`运行在两个上下文，并且两个上下文切换示意图
如下:

![ucontext_switch](./pic/ucontext_switch.svg)

![ucontext_switch_c_code](./pic/ucontext_switch_c_code.svg)

另外，linux中还支持另外一组上下文切换的API -- sigsetjmp, siglongjmp

### sigsetjmp, siglongjmp

该系列函数一般用于实现C语言中的异常处理，如在信号处理流程中，跳转到
其他的执行流程. 避免再次执行到异常代码.

我们先来看下其API

* sigsetjmp(sigjmp_buf env, int savemask)
  + **功能**: 保存当前的上下文和信号掩码，以便以后可以通过 siglongjmp 恢复
  + **参数**:
    + env: 保存上下文信息
    + savemask: 如果非0， 当前的信号掩码也会被保存
  + **返回值**:
    + 调用者返回0
    + 如果通过`siglongjmp`恢复，而返回`siglongjmp`
      传递的值
* siglongjmp(sigjmp_buf env, int val)
  + **功能**: 恢复由 sigsetjmp 保存的上下文信息和信号掩码，并从 sigsetjmp 返回。
  + **参数**:
    + `env`: 由`sigsetjmp`保存的环境信息
    + `val`: `sigsetjmp`
      * 0: return 1
      * x(x != 0) : return x
  + 没有返回值(因为已经跳走了)

看起来sigxxxjmp也可以实现上下文切换，但是该系列接口有个很大的问题，比较适合 recover,
但不适合new。其不像`ucontext`接口, 可以通过`makecontext()`接口先new一个context, `sigsetjmp`
只能保存当前的现场, 所以相当于只能先走到要切换的流程中埋好点，然后才能切换，很不方便.

但是`sigxxxjmp()`对比`makecontext()`也有好处. 其更加轻量化. 它不会涉及完整的上下文切换,
例如其可以设置不切换信号掩码，减少因系统调用而产生的切换损耗. 

而qemu中的协程实现主要有三种

* `ucontext + sigjmp`: util/coroutine-ucontext.c 
* `sigaltstack`: util/coroutine-sigaltstack.c
* `coroutine-win32`

本文主要介绍第一种，由`ucontext`和`sigjmp`结合实现。其中，`ucontext`系列接口负责
new context, 为`sigjmp`接口埋点, 而`sigjmp` 系列接口负责协程切换.

接下来，我们来看下qemu实现:

## qemu coroutine

### 协程状态机

![协程状态机](./pic/协程状态机.svg)

这是一个典型的由 leader 创建协程的状态机，进入协程上下文会做两种事:

* 埋sigxxxjmp跳转点, 为之后再次切换进协程做准备
* work...

协程运行期间，可能因为wait io等事件选择先切出协程(COROUTINE_YIELD),
此时协程是suspend状态。

等待协程处理完完整的事物后，会切出协程上下文，并置为terminal 状态.

另外除了首次进入协程是使用`ucontext`接口, 剩余的协程/leader之间的切换，
均使用`sigxxxjmp`系列接口，这样可以尽量减少因切换上下文带来性能损耗。

### 整体流程
整个流程如下图:

![co all](./pic/coroutine_all.svg)

### CREATE and INIT
create流程主要是为协程准备好上下文环境, init 流程主要是在协程中
打好跳转点, 流程包括:

1. 为协程分配堆栈空间
2. 使用makecontext(), swapcontext() 执行到一个新的上下文
3. 在协程上下文中，埋 sig jmp的点
4. 跳转回leader 上下文


INIT流程只是为协程搭建了一个上下文，但是该上下文接下来要执行什么任务，
需要leader指明，所以在切回leader上下文后，leader还需要为协程准备协程要
执行的函数，以及函数参数(<span style="background-color: #CC0066; color: #00FFFF;">红底蓝字部分</span>)

### enter

在`create && INIT` 章节中，我们介绍到首次进入协程是通过`swapcontext()`接口,
而之后再次进入协程，就需要使用`sigxxxjmp`系列接口，本章节主要介绍第二种。

而`enter`这个动作既有可能发生在`leader`上下文，也有可能发生在协程上下文,
所以我们以下面的场景为例子，看下qemu是怎么处理的。

* leader enter 协程A
* 协程A enter 协程B
* 假设协程A, 协程B 在处理过程中不会yield, 直接terminal.

整个流程如下图:

![协程enter](./pic/协程enter.svg)

这样处理，会导致协程只能串行，不能嵌套执行。

我们来想下为什么要这样做, 首先我们来看下，两者上下文切换次数:
* 串行执行
  ```
  leader->A->leader->B->leader
  ```
  切换4次
* 嵌套执行
  ```
  leader->A->B->A->leader
  ```
  切换4次

两者切换次数相同。

所以这里的原因(猜测)很可能是，防止协程可能带来的
同步问题（避免A上下文中嵌入B的上下文从而带来死锁)

### switch

接下来，我们再来看下switch过程。switch过程比较简单。主要的函数是,
`qemu_coroutine_switch()`, 函数原型:

```cpp
CoroutineAction qemu_coroutine_switch(Coroutine *from_, Coroutine *to_,
                                    CoroutineAction action);
```

参数有三个:
* from: 切出的协程
* to: 切入的协程
* action: 本次操作的类型
  + `COROUTINE_YIELD`: 暂停from协程
  + `COROUTINE_TERMINATE`: 终止from协程
  + `COROUTINE_ENTER`: 进入to协程

我们以一个没有执行过yield协程生命周期来看下switch的细节:

![qemu_coroutine_switch](./pic/qemu_coroutine_switch.svg)

可以看到在执行`qemu_coroutine_switch()`时，action参数会作为
`siglongjmp(, action)`传入，这样在另一个上下文中，会通过
`sigsetjmp()`的返回值，获取到action, 而`qemu_aio_coroutine_enter()`
会根据协程返回状态，来选择一些action:

* COROUTINE_TERMINATE: 销毁协程
* COROUTINE_YIELD: 忽略，继续执行leader流程

这里我们来总结下，不同的switch过程:

* leader->co
  + ENTER:
* co->leader
  + TERMINATE
  + YIELD

### yield

yield是一个比较特殊的存在，因为yield动作时，还需要保存协程的现场，
以便之后，再次切回协程。并且在协程yield切回leader后，leader会继续
运行执行其他流程。等待该协程的等待的事件到来后，需要再次执行enter
切换回该协程，如下图所示:

![协程yield](./pic/协程_yield.svg)

## Use Case for QEMU

## 附录
### virtio-blk触发堆栈
```sh
virtio_blk_handle_vq
## 从avail ring中获取req
=> blk_io_plug()
=> while (virtio_blk_get_request())
=> virtio_blk_submit_multireq()
   => foreach request:
      ## 可能会merge submit
      => submit_requests()
         => init qemu iovc
         => blk_aio_pwritev/blk_aio_preadv
=> blk_io_unplug()

blk_aio_pwritev
=> blk_aio_prwv(,,,,co_entry::blk_aio_write_entry, flags, 
        cb:: virtio_blk_rw_complete,opaque)
   => init acb::BlkAioEmAIOCB
   => qemu_coroutine_create(co_entry, acb)
   => bdrv_coroutine_enter(blk_bs(blk), co)
```

## 参考资料

1. [huangyong -- 深入理解qemu协程](https://blog.csdn.net/huang987246510/article/details/93139257?ops_request_misc=%257B%2522request%255Fid%2522%253A%252203d32d36da34d66cc6d602cb63fa9f6e%2522%252C%2522scm%2522%253A%252220140713.130102334.pc%255Fblog.%2522%257D&request_id=03d32d36da34d66cc6d602cb63fa9f6e&biz_id=0&utm_medium=distribute.pc_search_result.none-task-blog-2~blog~first_rank_ecpm_v1~rank_v31_ecpm-1-93139257-null-null.nonecase&utm_term=%E5%8D%8F%E7%A8%8B&spm=1018.2226.3001.4450s)
2. [_银叶先生 -- 协程的原理与实现：qemu 之 Coroutine](https://blog.csdn.net/chengm8/article/details/94023921)
