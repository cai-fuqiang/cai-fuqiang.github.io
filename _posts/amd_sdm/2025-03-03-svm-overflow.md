---
layout: post
title:  "svm"
author: fuqiang
date:   2025-03-03 13:30:00 +0800
categories: [amd_spec, svm]
tags: [svm]
---

> 文章主要来自AMD sdm `15 Secure Virtual Machine

## overflow

SVM 提供了由硬件扩展，旨在实现高效, 经济的虚拟机系统。其功能主要分为
virtualization support 和 security support, 概述如下:

* virtualization support
  + memory
    + guest/host tagged TLB
    + External (DMA) access protection for memory
    + Nested paging support
  + interrupt virtualization
    + Intercepting physical interrupt delivery
    + virtual interrupts
    + Sharing a physical APIC
    + Direct interrupt delivery
  + CPU virtualization: guest mode && host mode
    + switch
    + intercept: ability to intercept selected instructions or events·
      in the guest
* securitry support
  + Attestation: SKINIT
  + Encrypted memory: SEV, SEV-ES
  + Secure Nested Paging: SEV-SNP
## CPU
### Enabling SVM

虚拟化扩展指令

* VMRUN
* VMLOAD
* VMSAVE
* CLGI
* VMMCALL
* INVLPGA

执行需要`EFER.SVME` 被设置为1, 否则执行这些指令将会产生`#UD`.

另外
* SKINIT
* STGI

指令执行需要
+ EFER.SVME 设置为1
+ CPUID Fn8000_0001_ECX[SKINIT] 设置为1

否则执行也会产生`#UD`

在使能SVM之前，如那件需要如下判断SVM是否能被enable.

```
if (CPUID Fn8000_0001_ECX[SVM] == 0)
    return SVM_NOT_AVAIL;

if (VM_CR.SVMDIS == 0)
    return SVM_ALLOWED;

if (CPUID Fn8000_000A_EDX[SVML]==0)
    return SVM_DISABLED_AT_BIOS_NOT_UNLOCKABLE
// the user must change a platform firmware setting to enable SVM
else 
    return SVM_DISABLED_WITH_KEY;
// SVMLock may be unlockable; consult platform firmware or TPM to obtain the key.
```

### VMCB

VMCB中即包括了guest上下文，也包括了用于vmm控制guest的配置信息。主要包括:

* 在guest 中要拦截的一些列的instruction or event
* 各种控制位用于指定guest 的execution envirionment，或指示在运行来宾代码之前需要采
  取的特殊操作，以及
* guest processor state (例如, 控制寄存器)

VMCB位于内存中, 某些指令和事件会根据vmcb构建guest上下文，或者将guest上下文writeback回vmcb，完成host和
guest之间的切换, 我们下面详细介绍

#### VMRUN and #VMEXIT

使用VMRUN指令操作数需指定一个VMCB地址, 即`rAX`, 在`VMRUN`时, 会从`rAX`指向的VMCB
内存中，先将当前cpu状态保存下来，然后再将部分字段load到当前CPU的上下文，
将全部cpu 状态load后，就相当于进入guest了。

具体操作是:
* remember VMCB address(rAX) for next #VMEXIT
* save host state -> `VM_HSAVE_PA` MSR
* load control information
  + intercept vector
  + TSC offset
  + interrupt control
  + EVENTINJ field
  + ASID
* load guest state
  + ES, CS...
  + GDTR IDTR
  + CRxxx

**此时，cpu context 已经是guest**

* execute command store in TLB_CONTROL
* 
  ```
  IF (EVENTINJ.V)
   cause exception/interrupt in guest
  else
    jump to first guest instruction
  ```
上面的某些信息，在这个过程中会替换掉当前host的上下文, 如GDTR. 但是某些字段是
不属于cpu context的, 例如`control information`, 这部分就相当于专门的cpu cache。
目的是:

vmcb中的这些字段在guest中可能会频繁访问，例如, intercept INTR control field,
在每次外部中断到来时, 都会使用该字段。为了加速, 虚拟机运行时的性能，在VMRUN指令
执行时，会将`VMCB`中的大部分字段，加载到cpu内部的cache中.

如下图:

![VMCB overflow](./pic/VMCB.svg)

从上图可知:
* VMCB的cache以该VMCB在内存中的base physical address为tag, 在VMRUN时，会将
  VMCB load到memory
* 当intecept 某些events时，可能会从触发 `#VMEXIT`. 这时，会将VMCB cache 
  writeback 到memory
* VMCB cache，并不是cache了 VMCB 全部, 包括:
  + interrupt shadow
  + Event injection: 事件注入相关信息，在 `VMRUN` 时, 获取一次，并在进入guest之前，注入该event, 
    在之后guest运行过程中，不再需要这个字段, 所以这个信息没有必要cache
  + TLB Control: 和上同理
  + RFLAGS, RIP, RSP, RAX: CPU: CPU 上下文信息, 这些信息在#VMEXIT后，很可能会改变，并且
    这些字段是load 到cpu context的。所以没有必要cache.(猜测)


另外, 在`VMRUN`和`#VMEXIT`时，需要save，load host state。这些CPU也做了相应的
类似于VMCB的cache。手册中的描述如下:

> Processor implementations may store only part or none of host state in the
> memory area pointed to by VM_HSAVE_PA MSR and may store some or all host
> state in hidden on-chip memory. Different implementations may choose to save
> the hidden parts of the host’s segment registers as well as the selectors.
> For these reasons, software must not rely on the format or contents of the
> host state save area, nor attempt to change host state by modifying the
> contents of the host save area.


大致的意思是, 处理器可能会store 部分或者不会store 由 VM_HSAVE_PA MSR 指向的 
host state,  并可能将部分或全部主机状态store 在 on-chip memory中。不同的实现
可能会选择保存主机段寄存器的隐藏部分以及选择器。因此，软件不能依赖于主机状态
保存区域的格式或内容，也不能通过修改主机保存区域的内容来尝试更改主机状态。

所以，guest host上下文切换，主要涉及 `VMCB -- VM_HSAVE_PA` 中包含的上下文
内容的切换, 但是某些event只需要简单处理后，又继续返回guest执行。这样就没有
必要切换一些寄存器。（使用guest的即可)

另外在大部分的场景下，在多次`VMRUN`, `#VMEXIT`期间, `VMCB`中的很多字段并没有改变。
为了加速guest, host的切换. `SVM`支持控制某些字段在`VMRUN`时才会load.


上面提到的两种情况，amd通过如下方式解决:
* VMCB clean Bits
* VMLOAD, VMSAVE

##### VMCB Clean Bits

> 该功能在amd spec `15.15 VMCB State Caching`章节中有详细讲述

首先该功能在VMCB 新增了 `VMCB Clean field`(VMCB offset 0C0h, bit 31:0),
这些bit决定了在`VMRUN`时，需要load哪些register. 每个bit可能代表某个或
某组寄存器。该bit设置为0时，需要处理器去load VMCB到cache。
但是这些bit是hint, 因此processor可能会忽略掉厚谢被设置为1的bits，无条件
的从VMCB 中load。另外，当clear bits 设置为0时，总是需要load。

所以这样就需要vmm判断，在上次 `#VMEXIT`到本次`VMRUN`之间，有哪些字段改变了.
从而使用`VMCB clean field`完成高效的guest/host切换。

有一些场景需要VMCB clear field都被设置为0, 如下:

* 该guest第一次 run
* guest 被切到另一个cpu上运行
* hypervisor将 guest VMCB 切到另一个物理地址

上面提到过，VMCB cache时根据VMCB的physical address 作为tag去match. 当CPU
发现`VMRUN`指定的 VMCB physical address 和 cache中所有的 条目都不匹配时，
会将VMCB clean field 都当作zero.

VMCB Clean field 具体字段如下:

![VMCB_CLEAN_FIELD](pic/VMCB_CLEAN_FIELD.png)

##### VMLOAD, VMCLEAN

在`VMRUN`包括`#VMEXIT`过程中，即使`VMCB Clean Bits`都设置为0, cpu也不会
将所有的字段全部load/save, 需要通过额外的指令

* VMLOAD
* VMSAVE

这些字段包括:
* FS, GS, TR, LDTR (including all hidden state)
* KernelGsBase
* STAR, LSTAR, CSTAR, SFMASK
* SYSENTER_CS, SYSENTER_ESP, SYSENTER_EIP

这样做的目的是，为了快速的完成guest和host的切换, 来处理一些简单的event,
虽然在实际的KVM代码中，并没有这样做。

> NOTE
>
> 可以参照SVM的代码, `svm_vcpu_enter_exit`中关于vmload和vmsave
> 指令的使用.
>
> kvm选择在`VMRUN`之前，无条件的执行`VMLOAD guest vmcb`，在
> `#VMEXIT`时，`VMSAVE guest vmcb`, `VMLOAD host save area`<sup>2</sup>
>
> 但是手册中并未找到关于`MSR_VM_HSAVE_PA`指向的`host state`
> 的格式。所以, 这里猜测`host state`格式和`vmcb`相同.
{: .prompt-info}

### intercept
关于cpu虚拟化中，比重最大的部分，就是intercept。host通过 intercept guest中
的敏感行为，trap到host，然后由vmm进行emulate后，再次进入guest。

intercept operation主要分为两类:
* Exception intercept:
* instruction intercept:

当发生了intercept时，需要将VMEXIT的reasion，还有一些其他的信息
传递到host, 这些信息被写在:

* EXITCODE: intercept的原因
* EXITINTINFO: 当guest想要使用 IDT deliver interrupt or exception
              时发生了intercept，这时需要有一个地方保存着该信息，
              以便处理完该event之后，再次向guest注入 interrupt/exception
* EXITINFO1, EXITINFO2: 提供了某些intercept的额外信息

intercept就意味着需要保存guest state，并切换到host state，那该从哪个点保存
guest state呢?

这个和host上触发exception or interrupt的需求是一样的，都需要保存一个上下文
切换到另一个上下文, 而host上触发excp/intr 是发生在指令边界处. (在
[interrupt and exception context switch](#interrupt-and-exception-context-switch)
章节中介绍了host触发excp/intr的逻辑)

而 intercept 的逻辑也是这样，也是在指令边际处来切换. 但是其和host 上切换逻辑
不同的是:

|不同点|host| guest intercept|
|---|---|---|
|是否切换|根据当前cpu的状态|结合cpu状态以及vmcb control field|
|切换信息量|fewer register and non-visible state| more register and non-visible state|
|切换信息方式|stack->cpu|cache -- vmcb -- host state|

所以综合来看，intercept的整体要复杂, 其代价更大, 所以现在虚拟化主要的优化方式，
就是在硬件中emulate，减少vmm intercept.

关于intercept的细节有很多。不同的intercept event的触发条件，相关control field，
以及EXITCODE/EXITINFO 均不同，我们不再这里描述。

## memory

内存虚拟化我们这里主要关注两部分
* nested page Table
* TLB

## interrupt

### background

这里的interrupt虚拟化，囊括了异常和中断，其中异常的处理要简单些，我们来比较下:

|中断|异常|
|---|---|
|中断的产生源是可能是software，也可能是hardware|异常产生源是cpu|
|中断处理，需要cpu和apic的配合|异常完全是cpu自己的逻辑|
|cpu需要判断当前的状态<br/>来决定是处理中断还是pending中断|异常一旦发生，就需要立即处理|
|在一个中断将要被处理时，<br/>还有其他pending的中断, <br/>这就意味着，硬件需要根据配置<br/>来将多个中断连续处理|当异常被处理之前，不会有pending的异常 |

从上面来看，中断处理涉及的组件更多，处理细节也更复杂. 所以针对中断优化要更
多一些。

在介绍SVM的中断虚拟化之前，我们以比较复杂的中断为例，看看硬件处理中断需要完
成哪些步骤:

![hardware handle interrupt](./pic/hardware_handle_interrupt.svg)

1. IO Device 将中断发送到中断控制器
2. 中断控制器和CPU进行交互(可屏蔽中断的处理逻辑), 根据配置依次向cpu deliver
   中断
3. CPU侧会根据自己的状态，在某些时刻接收中断
4. 接收中断后, cpu根据IDT完成中断的处理。

我们来设想下，如果我们要将hardware的中断直接注入到guest中(终极目标:完全bypas
vmm)，那就意味着，中断处理链上的所有组件都要被虚拟化.

我们接下来看下, hardware emulate 了哪些部分，是怎么emulate的。

### overflow

为了能够给guest注入中断/异常，SVM支持event injection 机制(这里的event是对interrupt
和exception的统称)。可以让cpu在执行VMRUN后，在进入guest之前，由硬件触发对event的
处理流程（例如根据IDT进行上下文切换). 这样就避免了对 VMM 进行纯软件层面的模拟，大大
减少了复杂度.

而为了进一步优化中断的处理, SVM 先后引入了:
* virtual interrupt: 引入虚拟中断, 在guest状态下引入对虚拟中断的评估逻辑。
* AVIC: 引入对apic的虚拟化, 引入apic虚拟化后，大大增加了guest中处理中断的
  能力。可以尽量避免vmm参与virtual interrupt emulate.

### event injection

我们先来看下event inject的实现:

event injection 具体实现是在VMCB中引入 <font color=red><strong>`EVENTINJ`</strong></font>
字段, VMM可以设置该字段的某些field，来完成event inject. 在guest 代码执行之前，插入了中断
代码的执行。

实现注入在guest来看是透明的, 正常发生的。但是有一些例外:

* Inject event 接受 intercept check. (但是如果在delivery 该inject event时，触发了
  第二个异常, 这个异常受限于exception intercept)

  > 也就是说，当前VMCB中配置了 intercept #PF，如果本次注入的是#PF, 本次注入将不会被
  > intercept, 但是如果 #PF 的IDT handler配置的有问题，则会产生#GP<sup>待考证</sup>
  > 异常, 该异常可能会被intercept
* injected NMI 将不会阻塞未来的 NMIs delivery

  > 该限制是为了防止guest可以block host的NMI delivery

* 如果VMM注入了一个guest mode可能发生的 event(e.g.,在guest位于64-bit mode 时注入#BR),
  该event inject将会fail，并且guest state 将不会发生改变。本次VMRUN 也会立即退出，
  error code为`VMEXIT_INVALID`

* 使用vector 3 /4 来injecting exception(Type=3) 就像使用INT3 INTO 指令发起trap一样，
  处理器需要在dispatch to handler 之前，检查IDT 中的 DPL

* software interrupt 将不会在不支持`NextRIP`字段的被正确注入。(CPUID Fn8000_000A_EDX[NRIPS] = 1)
  VMM应该在`NextRIP`不支持的情况下，模拟对software interrupt 的event injection.

* <font color="lightgray">ICEBP TODO</font>

`EVENTINJ` 字段:

![EVENTINJ_field](pic/EVENTINJ_field.png)

* **_VECTOR_**: event IDT vector, 如果 **_TYPE_** 是2, 则忽略该字段(因为NMI是固定的vector)
* **_TYPE_**: 指定exception或者interrupt的类型. 支持的类型如下:

  |value|Type|
  |----|----|
  |0|INTR(external or virtual interrupt)|
  |2|NMI|
  |3|Exception|
  |4|software interrupt|
* **_EV_** (error code valid):  如果为1，则需要将error code push到stack上。
* **_ERRORCODE_**: ^^
* **_V_**(vaild): 表明该event是否要inject到guest.

如果`EVENTINJ`配置的有问题, VMRUN 则会以error code `VMEXIT_INVALID` 退出，
例如下面配置:

* TYPE设置了除上面展示的其他的值 
* 指定TYPE=3(exception), 但是该vector不可能是expception(例如vector 2, 是NMI)

<font color=red size=5><strong>总结</strong></font>

event inject 只是将interrupt delivery by IDT的逻辑虚拟化到硬件了. VMM可以只注入
一个vector，硬件自动完成，对这个vector的后续处理.

<font color=blue><strong>SVM TODO</strong></font>

event inject  机制这对于异常来说这个机制已经足够了, 注入异常流程大概是:

![inject exception](./pic/inject_exception.svg)

通过上面来看注入异常的出发点，是guest执行了某些指令, 因为某些原因`#VMEXIT`, 
host intercept后, 会来判断该条指令的emulate 需不需要inject exception，如果需要
则inject exception. 这套流程，完全契合inject exception，而且很难找出优化的空间.
因为其是完全串行，sync的处理流程。

> NOTE
>
> 其实我们从另一个角度来思考，虽然异常注入的流程不好再优化，那其实可以优化异常
> 产生, 也就是host可以更好的从硬件层面更好的emulate guest指令的执行环境, 使其
> 更少的vmexit。（例如NPT, 引入npt后，大大减少了#PF异常的产生). 但这部分不是
> 中断虚拟化的范畴。（当然，本身也没有那么严格的界限，但是为了避免混乱, 我们这
> 里放到 CPU虚拟化的章节中介绍)
{: .prompt-tips}

而对于中断而言，event injection 完成的是整个链条中哪部分处理呢?

![event inject](./pic/event_inject.svg)

从上图来看，event inject主要完成CPU 接收events(interrupt or expection)之后的一些流程,
即`handle interrupt vector`(也就是主要完成从当前guest上下文->中断上下文切换).

所以中断而言，离终极目标还有很长一段距离。

### virtual interrupt

virtual interrupt是对event inject的进一步升级, 在guest中执行中断评估逻辑, guest有能力
在 指令边界处识别并处理中断(virtual), 这就意味着，我们需要虚拟化出一套可以用于虚拟
中断执行的资源。我们先来看cpu这边关于物理中断准备了哪些资源:

![handle interrupt hardware support](./pic/handle_interrupt_hardware_support.svg)

* **_CR8/TPR_**: 用来指定当前cpu可以处理的最低中断优先级, 如果pending的中断没有TPR大，
          CPU不处理该中断

   > CR8虽然是CPU的寄存器, 但是最终映射于LAPIC的CR8, 所以其中断是否向CPU发送，
   > 需要首先走LAPIC的中断评估逻辑。不过为了方便介绍下面的章节，我们暂将CR8
   > 作用于CPU 的处理流程里。

* **_RFLAGS.IF_**: CPU 侧的中断屏蔽位，用来指示当前CPU要不要阻塞apic pending
               的中断（也就是要不要 回应/ack lapic).

* **interrupt shadows**: interrupt shadows -- a single-instruction windows during
  which interrupts are not recognized. 例如: STI 指令（开中断）的下一条指令，
  仍然是不接收中断的。

SVM 新增了 virtual interrupt 运行的资源，用于只处理virtual interrupt，而不影响
phyiscal interrupt, 如下图所示:

![virtual_interrupt_env](./pic/virtual_interrupt_env.svg)

> NOTE
>
> AMD spec 中没有提到 vRFLAGS.IF, 

除了增加了用于virtual interrupt处理的资源，还增加了用于配置virtual interrupt的
VMCB 字段以及其他字段.

#### V_INTR_MASKING

为了防止guest block INTR(physical interrupt), SVM 提供了一个VMCB control bit:
V_INTR_MASKING, 这个control bit控制guest EFLAGS.IF和 TPR/CR8 的作用范围:

* 1: 作用于 virtual interrupt
* 0: 作用于virtual interrupt and physical interrupt

分别来看下, 其具体的作用者:

#### EFLAGS.IF

+ if V_INTR_MASKING == 1:
  + The host EFLAGS.IF at the time of the VMRUN
    is saved and controls physical interrupts while
    the guest is running.
  + The guest value of EFLAGS.IF controls virtual 
    interrupts only.
+ else:
  + EFLAGS.IF control VINTR and INTR

#### CR8/TPR
svm 新增了 virtual TPR register -- VTPR, 在VMRUN时，从VMCB
load，并且在#VMEXIT时，writeback to VMCB, APIC TPR 仅控制
physical interrupt，V_TPR 仅控制 virtual interrupt

+ if V_INTR_MASKING == 1:
  + Writes to CR8 affect only the V_TPR register.
  + Reads from CR8 return V_TPR.
+ else:
  + Writes to CR8 affect both the APIC's TPR and the V_TPR register.
  + Reads from CR8 operate as they would without SVM.

上面所说的TPR virtualization 仅作用于通过访问CR8触发。但是在32-bit
mode中, 没有CR8, 软件只能通过访问TPR，访问TPR只能使用传统MMIO的方式
(xapic), vmm需要做一些emulate处理，大致流程如下:

1. VMM 不映射 guest 的 APIC page address
2. guest 访问该区域将产生#PF intercept
3. VMM根据这个物理地址来确定，该地址属于apic，并且是TPR的offset，
   执行相关emulate代码

为了提高 32 位模式下 TPR 访问的效率，SVM 通过一种 MOV TO/FROM CR8
的替代编码（即带有 LOCK 前缀的 MOV TO/FROM CR0）使 32 位代码可以使用
CR8。为了实现更好的性能，应该修改 32 位客户机以使用这种访问方法,
而不是使用内存映射的 TPR。

即使在 EFER.SVME 中禁用 SVM，这些 MOV TO/FROM CR8 指令的替代编码仍然
可用。它们在 64 位和 32 位模式下均可使用。

> INTERESTING!!!
{: .prompt-info}

#### injecting virtual interrupt

virtual interrupt 允许host将一个interrupt(#INTR)传递给guest. 当运行在
guest中时，会执行和host一样的中断评估逻辑， 例如中断是否taken受(EFLAGS.IF 
以及 vTPR值的影响). 所以virtual interrupt的引入，实际上是在每次指令的边界，
添加了关于virtual interrupt的处理逻辑。

inject细节如下:
+ inject 流程

  新增了三个用于存储virtual interrupt的字段:
  + **_VIRQ_** : 指示是否有VINTR需要注入
  + **_V_INTR_PRIO_** : priority of VINTR
  + **_V_INTR_VECTOR_** : vector of VINTR

+ taken 条件:

  如果下面条件满足, 处理器将taken virtual INTR interrupt:
  + if V_IRQ == 1 &&  V_INTR_PRIO > V_TPR  **and**
  + if EFLAGS.IF == 1 **and**
  + if GIF == 1  **and**
  + if the processor not in an interrupt shadow

+ VINTR vs INTR:

  所以通过上面来看VINTR和INTR 在处理上的区别很小, 后者需要INTACK 
  来获取中断信息，而前者从V_INTR_VECTOR 中获取

+ external handle on VMEXIT:

  + 上面提到只有在合适的时机，virtual interrupt 才会被taken，在处理器
    taken后，dispatch virtual interrupt时（through IDT), V_IRQ 在检查 
    intercept of virtual interrupt 之后，并在访问 IDT（中断描述符表）之前，
    V_IRQ 被清除。

  + 在#VMEXIT时，会将V_IRQ writeback to VMCB, 允许VMM 来跟踪该virtual 
    interrupt 有没有 taken.
  + 另外在#VMEXIT时，处理器会clear到CPU缓存中的 V_IRQ 和 V_INTR_MASKING,
    所以virtual interrupt不会在VMM中pending

+ other
  + 在guest运行时，VMM可以通过使能 INTR intercept 来 intercept INTR
  + physical interrupt的优先级永远高: 

    Physical interrupts take priority over virtual interrupts, whether 
    they are taken directly or through a `#VMEXIT`.

  + V_IGN_TPR可以控制当前pending的virtual interrupt不受  TPR 影响:

    V_IGN_TPR field in the VMCB can be set to indicate that the currently 
    pending virtual interrupt is not subject to masking by TPR. The priority 
    comparison against V_TPR is omitted in this case. This mechanism can be
    used to inject ExtINT-type interrupts into the guest.

上面提到 **_GIF_** :

global interrupt (GIF) 用来控制 **_interrupt and other event_** 是否可以被当前处理器
taken。**_STGI_** 和 **_CLGI_** 指令用来set clear该bit.

下面时GIF取值对于event taken的影响:

![GIF_impact](pic/GIF_impact.png)

<font color=red size=5><strong>总结</strong></font>:

离终极目标，满血版中断虚拟化又进了一步。现在在guest中增加了中断的评估
逻辑，使得guest可以去处理自己的中断（VINTR)。并且处理方式很像物理中断，
中断评估逻辑可以发生在guest的几乎任何指令边界处。**_这个优化很关键，相当于
打开了一个枷锁, 允许中断注入和中断taken异步发生_**

我们较event inject来比较下:

|~|event inject|virtual interrupt|
|--|--|--|
|when to delivery|end of VMRUN|like INTR, guest every inst boundary</br>Meet the conditions for being<br/>taken|
|conditions of taken|NO CONDITIONS| like INTR, </br>need check EFLAGS.IF TPR, </br>interrupt shadow...|

> Q: 像INTR有什么好处?
>
> A: 因为这是vm的需求，其总要求运行起来要<font size=5>像</font> 物理机一样。
>    所以硬件如果模拟的不像，就需要软件来模拟的像一些.
>
>    举个例子:
>
>    如果在VMRUN之前，如果vcpu处于interrupt shadow, event inject此时就不能注入
>    event，vmm还需要做好额外的intercept，尽量在intercept shadow刚关闭时，立即
>    退出guest，来inject event，来减小interrupt 延迟。
>
>    但是使用, virtual interrupt 考虑的就少很多了，不管啥样，直接在VMRUN之前注入
>    virtual interrupt， guest cpu 会自己判断interrupt shadow啥时候关闭，从而
>    更高效的 inject.
{: .prompt-tip}

那virtual interrupt 完成了，中断处理链条中的哪些部分呢?

![virtual_interrupt_handle](./pic/virtual_interrupt_handle.svg)

<!--
### other event support

#### INIT support

<font color=lightgray> TODO </font>

#### NMI support

<font color=lightgray> TODO </font>

#### SMM support

<font color=lightgray> TODO </font>
-->

### Advanced Virtual Interrupt Controller

AVIC 是AMD虚拟化中的重要的一个增强。其为guest的每个vcpu
都提供了和LAPIC兼容的副本。基于这个副本，我们可以对apic
中的很多功能做虚拟化。

#### introduction

## 参考链接
1. amd spec
2. [KVM: SVM: use vmsave/vmload for saving/restoring additional host state](https://patchwork.kernel.org/project/kvm/patch/20201210174814.1122585-1-michael.roth@amd.com/#23839851)

## 附录

### interrupt and exception context switch

interrupt, fault exception 和trap exception 其上下文切换都是发生在指令边界处，
这样做的好处，是明确规定了上下文切换的点，让指令执行原子化，方便软件进行处理.

但是三者的机制不太相同。分别来看:

#### interrupt

![interrupt_context_switch.svg](./pic/interrupt_context_switch.svg)

当APIC发出一个interrupt后(我们这里以maskable interrupt为例), cpu会在指令边际处检查
是否有pending的中断, 会根据当前的cpu状态评估(interrupt window)，要不要接收该interrupt, 
如果接收, 就向apic 要详细的中断信息，然后通过IDT进行上下文切换（当然不仅仅是IDT，还有
其他desc中的信息，这里不赘述)

#### fault

![fault_context_switch.svg](./pic/fault_context_switch.svg)

fault一般是指令执行过程中，发现该指令执行的有问题，例如，`#PF`是在寻址过程中，发现
page table walk 出现了问题，但是此时该指令还未执行完成，所以需要将cpu恢复到该指令
执行之前的上下文，然后，deliver一个exception

#### trap

![trap_context_switch](./pic/trap_context_switch.svg)

trap的处理十分简单，如上图所示，trap的触发是通过trap指令，该指令的作用就是在该指令
之后的位置，挖一个坑，该坑通往处理该trap的异常处理程序。当异常处理程序返回时，执行
trap指令的下一条指令。
