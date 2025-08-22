---
layout: post
title:  "[mm:la57] switch to la57"
author: fuqiang
date:   2024-10-11 16:57:00 +0800
categories: [mm,la57]
tags: [mm,la57]
---

## overview

在intel sdm `4.1.2 Paging-Mode Enabling`, 中提到:

> CR4.PAE and CR4.LA57 cannot be modified while either 4-level paging or 5-level
> paging is in use (when **CR0.PG = 1 and IA32_EFEe.LME = 1** ). Attempts to do so
> using MOV to CR4 cause a general-protection exception (#GP(0)).
>
> > 不能在 long mode分页时开启修改 CR4.LA57以及CR4.PAE, 否则会触发 **#GP**
> {: .prompt-tip}
{: .prompt-ref}

而kernel 又支持配置`no5lvl`, 来决定是否使能`la57` feature:
* **set no5lvl** : 4-level page table
* **not set no5lvl** : 5-level page table

那我们来看下, 内核是如何根据该参数切换的。

## 内核启动 -- startup64

`compressed/vmlinux.lds.S` 会设置compressed 程序 efi的入口(`ENTRY()`)，以及架构
(`OUTPUT_ARCH()`), 引导器会根据该配置, 在进入`ENTRY()`之前，进入相应的cpu mode.

> 引导器可能是startup_32, 页可能是64bit bootloader
{: .prompt-tip}

```cpp
#ifdef CONFIG_X86_64
OUTPUT_ARCH(i386:x86-64)
ENTRY(startup_64)
#else
OUTPUT_ARCH(i386)
ENTRY(startup_32)
#endif
```
例如，如果配置(`i386:x86-64`), cpu 就会进入long mode, 调用`startup_64`, 
之前会通过`esi`传入`boot_params`参数, 而在`startup_64`函数中，则会调用
`paging_prepare()`为切换`CR4.LA57`, 做好跳板:


## paging_prepare

`startup_64` 调用`paging_prepare()`代码如下
```cpp
SYM_CODE_START(startup_64)

    ...

    /*
     * paging_prepare() sets up the trampoline and checks if we need to
     * enable 5-level paging.
     *
     * paging_prepare() returns a two-quadword structure which lands
     * into RDX:RAX:
     *   - Address of the trampoline is returned in RAX.
     *   - Non zero RDX means trampoline needs to enable 5-level
     *     paging.
     *
     * RSI holds real mode data and needs to be preserved across
     * this function call.
     */
    pushq   %rsi
    movq    %rsi, %rdi      /* real mode address */
    call    paging_prepare
    popq    %rsi
```
而`paging_prepare()`, 需要做如下事情:

1. 准备页表
2. 准备跳板代码

```cpp
SYM_CODE_START(startup_64)
    ...
    /* Save the trampoline address in RCX */
    movq    %rax, %rcx

    /*
     * Load the address of trampoline_return() into RDI.
     * It will be used by the trampoline to return to the main code.
     */
    leaq    trampoline_return(%rip), %rdi

    /* Switch to compatibility mode (CS.L = 0 CS.D = 1) via far return */
    pushq   $__KERNEL32_CS
    leaq    TRAMPOLINE_32BIT_CODE_OFFSET(%rax), %rax
    pushq   %rax
    lretq
trampoline_return:
    /* Restore the stack, the 32-bit trampoline uses its own stack */
    leaq    rva(boot_stack_end)(%rbx), %rsp
```

## 参考链接
1. x86/boot/compressed: Enable 5-level paging during decompression stage
   + 34bbb0009f3b7a5eef1ab34f14e5dbf7b8fc389c
2. intel spec: 2.2 MODES OF OPERATION
   + Figure 2-3. Transitions Among the Processor’s Operating Modes
3. 
