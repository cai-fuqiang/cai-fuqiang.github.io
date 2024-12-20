---
layout: post
title:  "apic timer"
author: fuqiang
date:   2024-12-20 10:10:00 +0800
categories: [timer,apic-timer]
tags: [apic-timer]
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
