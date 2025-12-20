# nohz

## note
1. nohz 作为替代 period tick的产物，其依赖什么
   + timer: oneshot timer device
     - 我们可以在很多代码角落找到这一证据
       + tick_check_new_device(): prefer one shot capable devices
     - why

       无论是因为nohz的作用就是替代周期性的tick，所以需要一个oneshot timer
       来设置下次要到期的timer.

2. nohz 和hrtimer的关系
   + nohz 和 hrtimer 两者都需要高精度timer source， 所以两者是竞争关系，
     为了解决这个问题，在enable hrtimer的情况下, tick-sched内置的timer使用
     hrtimer， 而hrtimer则直接操控tick-device -- (`tick_program_event`)


## commit
* High resolution timer / dynamic tick update -- (first instrucduce)
  + https://lore.kernel.org/all/20070123211159.178138000@localhost.localdomain/
  + 950f4427c2ddc921164088a20f01304cf231437c - 289f480af87e45f7a6de6ba9b4c061c2e259fe98
    + Thomas Gleixner
    + 2007-02-16
* nohz: Basic full dynticks interface
  + https://lore.kernel.org/all/1356028391-14427-1-git-send-email-fweisbec@gmail.com/
  + https://lore.kernel.org/all/20130505110351.GA4768@gmail.com/
  + a831881be220358a1d28c5d95d69449fb6d623ca
    + Frederic Weisbecker <fweisbec@gmail.com>
    + 2012-02-18
  + 1c20091e77fc5a9b7d7d905176443b4822a23cdb
    + nohz: Wake up full dynticks CPUs when a timer gets enqueued
  + 1a55af2e45cc sched: Update rq clock earlier in unthrottle_cfs_rq
  + 1ad4ec0dc740 sched: Update rq clock before calling check_preempt_curr()
  + 71b1da46ff70 sched: Update rq clock before setting fair group shares
  + 77bd39702f0b sched: Update rq clock before migrating tasks out of dying CPU


* Allow CPU0 to be nohz full
  + https://lore.kernel.org/all/20190404120704.18479-1-npiggin@gmail.com/
  + 08ae95f4fd3b38b257f5dc7e6507e071c27ba0d5
    + Nicholas Piggin
    + 2019-04-11

## other
https://events.linuxfoundation.org/wp-content/uploads/2024/02/Joel-Fernandes-Mentorship-Webinar-The-Ticking-Beast-LF-webinar-Feb-22nd-2024-public-copy.pdf

### timer
https://wiki.osdev.org/Timer_Interrupt_Sources


[RTC](https://www.compuphase.com/int70.txt)

https://wiki.osdev.org/Timer_Interrupt_Sources#Local_APIC_timer_(newer,_with_TSC_deadline_mode)

https://ieeexplore.ieee.org/document/4685768

https://cwiki.apache.org/confluence/display/NUTTX/Power+Management+-+Final+Report

https://www.codingshuttle.com/blogs/operating-systems-in-one-shot/

https://lore.kernel.org/all/20061001225720.115967000@cruncher.tec.linutronix.de/
