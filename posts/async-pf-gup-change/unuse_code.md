
<!--
## non-para_virt async pf
我们知道, 如果达到这一目的, 就必须让 GUEST 去 sched out 当前触发 EPT violation 的 tasks, 
而非半虚拟化方式, 就是对 guest transparent, 所以, 又得要求guest 是靠自己当前的调度逻辑, 主动
的schedule, KVM 很巧妙的利用了操作系统使用时钟中断进行调度, 来达到这一目的, 主要步骤如下:

---
---
<details>
<summary>非半虚拟化方式</summary>

digraph G {
    subgraph cluster_host {
        style="filled"
        color="#71324556"
        subgraph cluster_host_vcpu_thread {
            get_user_pages_fast [
                label="get_user_pages() -- \nfast path"
            ]
            get_user_pages_fast_is_success [
                shape="diamond"
                label="get_user_pages_fast \nSUCCESS ?"
            ]

            halt_vcpu [
                label="halt vcpu"
            ]
            unhalt_vcpu_intr [
                shape="record"
                label="interrupt"
            ]

            unhalt_vcpu_kick [
                shape="record"
                label="other KVM \nproduce \nkvm_vcpu_kick()"
            ]

            unhalt_vcpu_and_re_VM_entry [
                label="unhalt and VM entry"
            ]
            unhalt_vcpu_and_inject_timer [
                label="unhalt and inject a timer intr"
            ]

            halt_vcpu->unhalt_vcpu_intr [
                label = "detect \nINTR \nevent, \nUNHALT"
            ]
            halt_vcpu->unhalt_vcpu_kick [
                label = "detect \nVCPU kick \nevent, \nUNHALT"
            ]
            unhalt_vcpu_kick->unhalt_vcpu_and_re_VM_entry 
            get_user_pages_fast->get_user_pages_fast_is_success

            unhalt_vcpu_intr->unhalt_vcpu_and_inject_timer
            get_user_pages_fast_is_success->halt_vcpu [
                label=N
            ]

            label="host kvm vcpu thread"
        }
        subgraph cluster_host_dedicated_thread {
            get_user_page_slow_path [
                label="get_user_pages(slow path)"
            ]

            have_get_page [
                label="get page, \nPAGE IS PRESENT!"
            ]
            
            get_user_page_slow_path->have_get_page
        
            label="dedicated thread"
        }
        subgraph cluster_host_timer {
            inject_a_timer_interrupt [
                label="inject a timer \ninterrupt to GUEST"
            ]
            "receive a timer \ninterrupt belong \nto GUEST"->
                inject_a_timer_interrupt->
                unhalt_vcpu_intr
            label="timer"
        }

        label = "host"
    }
    subgraph cluster_guest {
        style="filled"
        color="#12323456"
        subgraph cluster_guest_task1 {
            task1_access_a_memory [
                label="acesss a memory address [BEG]"
                color="white"
                style="filled"
            ]

            trigger_EPT_violation [
                label="trigger EPT violation"
            ]

            task1_access_a_memory ->
                trigger_EPT_violation [
                label="page NOT present"
            ]
            label="TASK1 trigger ept vioaltion"
        }
        
        subgraph cluster_guest_task2 {
        
        }
    
        subgraph cluster_guest_schedule_model {
            timer_schedule_handler [
                label="receive  a timer \ninterrupt, need schedule"
            ]
            label="schedule module"
        }
        label="guest"
    }
    trigger_EPT_violation->get_user_pages_fast

    unhalt_vcpu_and_inject_timer->timer_schedule_handler [
        label="inject intr event"
    ]
    have_get_page->unhalt_vcpu_kick
    unhalt_vcpu_and_re_VM_entry->task1_access_a_memory
    get_user_pages_fast_is_success->get_user_page_slow_path [
        label="N"
    ]
}

</details>
---
---

这里需要注意的是:
1. 上面是以timer interrupt 举例, 如果收到不是timer interrupt, 该中断也会inject 到
   guest中, 只不过guest在处理完interrupt后,还会返回到之前的task, 在page 没有present
   的情况下, 还会触发 EPT violation(包括如果收到了timer interrupt, 但是并没有执行sched
   动作. 也是同样的情况). But so what ? 本来引入async pf 的目的, 就是让vcpu 能够去做些
   别的任务? schedule other task && handle interrupt, 都可以让vcpu 继续运行, 和 get_user_page(slow
   path) 并行运行.
2. 该实现比较巧妙的时, 它对GUEST 完全透明, 当guest 触发async pf时, 当vcpu再次运行,
   无论是收到interrupt, 还是 async pf complete kick this vcpu, 对于guest而言, 就像是
   在触发异常指令之前的 instruction boundary执行了较长的时间(也就是触发异常的上一条指令)

## PV async pf

> NOTE
>
> 我们思考下, 该方式看似就已经解决问题了,为什么还要搞一个半虚拟化的方式, 来使该流程便复杂,
> 我们来看下该方式有何缺点:
>
> * 场景1
>   ```
>   vcpu_thread                 interrupt handler or work
>      halt_vcpu
>
>                               kick vcpu
>
>      unhalt
>      vcpu_enter
>   ```
>   可以看到在 halt_vcpu 之间, 到vcpu enter 之间, 有一个比较大的window, 如果能把 该window优化掉就好了
>
>
> * 场景2
>   ```
>   vcpu_thread_kvm   host_intr_handler_or_work           GUEST
>     halt_vcpu
>                     kick_vcpu
>     uhalt
>     vcpu_enter
>                                                         sched out task1
>                                                         sched in task1
>                                                         page is NOT present
>                                                         trigger EPT violation
>     vcpu_exit
>     halt_vcpu
>   ```
>   可以看到, 这里在vcpu enter后, 还有可能调度回 task1, 接着触发EPT violation, 如果page
>   还没有present的话, 本次调度, 仍然会VM exit, 继续halt vcpu, 还会有场景1 中的较大的window.
>
> 所以通过上面两种场景看, 该方式的实现, 并不能做到与vcpu 与 `get_user_page_slow_path`做到完全平行.
> 还是会在某些地方有block
{: .prompt-tip}

结合上述, 我们首先需要思考下, 半虚拟化的 async pf要达到一个什么样的目的:
1. 尽量不去 halt vcpu, 让其能够在`get_user_pages_fast()`没有成功的时候, 就可以VM-entry, 为了避免
   再次执行触发EPT violation的指令, 需要打破现有的执行流程, 并且执行调度.

   而打破现有的执行流程, 无非是通过 INTERRUPT/EXCEPTION
2. 能够让GUEST知道, 哪些task是因为async pf被调度走了, 避免再page没有present的情况下, 将这些task
   调度回来

而PV async pf, 就是多做了上面两件事.

-->
