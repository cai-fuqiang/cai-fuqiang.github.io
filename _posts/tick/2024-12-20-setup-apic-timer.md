---
layout: post
title:  "apic timer"
author: fuqiang
date:   2024-12-20 10:10:00 +0800
categories: [timer,apic-timer]
tags: [apic-timer]
math: true
---


## setup timer

boot cpu
```sh
start_kernel
=> time_init();
   => choose early clocksource in [hpet, pm, pit] to  
      calibrate_tsc
      ## 以hpet计算tsc 为例
      ## 这里主要是因为hpet/pit/pm频率是确定的，但是tsc
      ## 频率不确定, 需要用其他的clocksource来计算下
      => cpu_khz = hpet_calibrate_tsc();
         => ((tsc_delta) * 1000000000L) / hpet_delta *
   => enable early timer
      => setup_irq(0, &irq0)
   # ifndef CONFIG_SMP
   => time_init_gtod()
=> rest_init
   => kernel_thread(init, NULL, CLONE_FS | CLONE_SIGHAND);
      => smp_prepare_cpus
      => setup_boot_APIC_clock  ## want to use APIC clock
         => disable irq
         => calibration_result = calibrate_APIC_clock()
         => setup_APIC_timer(calibration_result);
         => enable irq
```

time_init_gtod
```cpp
/*
 * Decide what mode gettimeofday should use.
 */
void time_init_gtod(void)
{
    char *timetype;

    if (unsynchronized_tsc())
        notsc = 1;

    if (cpu_has(&boot_cpu_data, X86_FEATURE_RDTSCP))
        vgetcpu_mode = VGETCPU_RDTSCP;
    else
        vgetcpu_mode = VGETCPU_LSL;

    //有hpet 没有tsc ，优先使用hpet
    if (vxtime.hpet_address && notsc) {
        //timetype -- [timer, clocksource]
        timetype = hpet_use_timer ? "HPET" : "PIT/HPET";
        //如果使用hpet timer
        if (hpet_use_timer)
            //HPET_T0_CMP 表示下一次要到期的cycle
            //hpet_tick 表示 一次tick所占用的cycle
            //两者相减代表上次到期的cycle
            vxtime.last = hpet_readl(HPET_T0_CMP) - hpet_tick;
        else
            vxtime.last = hpet_readl(HPET_COUNTER);
        vxtime.mode = VXTIME_HPET;
        do_gettimeoffset = do_gettimeoffset_hpet;
#ifdef CONFIG_X86_PM_TIMER
    /* Using PM for gettimeofday is quite slow, but we have no other
       choice because the TSC is too unreliable on some systems. */
    } else if (pmtmr_ioport && !vxtime.hpet_address && notsc) {
        timetype = "PM";
        do_gettimeoffset = do_gettimeoffset_pm;
        vxtime.mode = VXTIME_PMTMR;
        sysctl_vsyscall = 0;
        printk(KERN_INFO "Disabling vsyscall due to use of PM timer\n");
#endif
    } else {
        timetype = hpet_use_timer ? "HPET/TSC" : "PIT/TSC";
        vxtime.mode = VXTIME_TSC;
    }

    printk(KERN_INFO "time.c: Using %ld.%06ld MHz WALL %s GTOD %s timer.\n",
           vxtime_hz / 1000000, vxtime_hz % 1000000, timename, timetype);
    printk(KERN_INFO "time.c: Detected %d.%03d MHz processor.\n",
        cpu_khz / 1000, cpu_khz % 1000);
    vxtime.quot = (USEC_PER_SEC << US_SCALE) / vxtime_hz;
    vxtime.tsc_quot = (USEC_PER_MSEC << US_SCALE) / cpu_khz;
    vxtime.last_tsc = get_cycles_sync();

    set_cyc2ns_scale(cpu_khz);
}
```

## calibrate_APIC_clock

$$
\begin{align}
delta = LAPIC\_CAL\_LOOPS * one\_TICK\_counter\_delta \\
deltatsc = LAPIC\_CAL\_LOOPS * one\_TICK_counter\_tsc\_delta
\end{align}
$$

所以:

$$
\begin{align}
lapic\_timer\_period &= \frac{delta * APIC\_DIVISOR}{ LAPIC\_CAL\_LOOPS} \\
&= one\_TICK\_counter\_delta * APIC\_DIVISOR
\end{align}
$$

`APIC_DIVISOR`是apic `Divide Configuration Register`所代表的值，是kernel用的默认
精度。这里乘以该值表示最大精度。

所以`lapic_timer_period`表示 一个TICK 所增长的counter 值.

而

$$
\begin{align}
deltatsc / LAPIC\_CAL\_LOOPS / (1000000 / HZ)  \\
= \frac{one\_TICK\_counter\_tsc\_delta * HZ}{1MHz}
\end{align}
$$

其实表示的是1s钟之内，tsc counter 增长的值。以MHz为单位.

而如果`apic_timer_period`也转换为1s/MHz，需要在上面delta值上除1000，假设
`HZ=1000`

我们来看下这两个值的打印:
```sh
[    0.188106] Using local APIC timer interrupts. Calibrating APIC timer ...
[    0.290833] ... lapic delta = 624930
[    0.290937] ... PM-Timer delta = 357914
[    0.290998] ... PM-Timer result ok
[    0.290998] ..... delta 624930
[    0.290998] ..... mult: 26839250
[    0.290998] ..... calibration result: 99988         ## 等式(3)
[    0.290998] ..... CPU clock speed is 2599.0706 MHz. ## 等式(4)
```

99988/1000 = 99.88， 其最大精度大概是tsc的`2599/99 = 26`


我们来看下oneshot时钟和tsc-deadline时钟的kernel中使用的精度差, 以及其`set_next`函数

* oneshot
  ```
  lapic_init_clockevent
  |-> lapic_clockevent.mult = div_sc(lapic_timer_period/APIC_DIVISOR,
                                TICK_NSEC, lapic_clockevent.shift);
  lapic_next_event
  |-> apic_write(APIC_TMICT, delta);
  ```
* tsc-deadline
  ```
  setup_APIC_timer
  |-> clockevents_config_and_register(levt,
                                tsc_khz * (1000 / TSC_DIVISOR),
                                0xF, ~0UL);
  lapic_next_deadline
  |-> tsc = rdtsc();
  |-> wrmsrq(MSR_IA32_TSC_DEADLINE, tsc + (((u64) delta) * TSC_DIVISOR));
  ```

  这里的 / `TSC_DIVISOR` 没看懂啥意思。在`clockevents_config_and_register`除去
  有在`set_next`时乘上....

所以, 在kernel使用中, lapic oneshot 精度(包括period)还要下降`APIC_DIVISOR`(16)倍

精度差在 26 * 16 = 416. 没有特别特别高的精度差别。(况且oneshot也可以通过修改
`DIVISOR`提升精度)
