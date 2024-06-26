```
commit d40891e75fc1f646dce57d5d3bd1349a6aaf7a0e
Author: Ingo Molnar <mingo@elte.hu>
Date:   Fri Feb 16 01:28:10 2007 -0800

    [PATCH] i386: enable dynticks in kconfig

    Enable dynamic ticks selection.

commit 741673473a5b26497d5390f38d478362e27e22ad
Author: Ingo Molnar <mingo@elte.hu>
Date:   Fri Feb 16 01:28:07 2007 -0800

    [PATCH] i386 prepare for dyntick


commit d36b49b91065dbfa305c5a66010b3497c741eee0
Author: Thomas Gleixner <tglx@linutronix.de>
Date:   Fri Feb 16 01:28:06 2007 -0800

    [PATCH] i386 rework local apic timer calibration

commit e9e2cdb412412326c4827fc78ba27f410d837e6e
Author: Thomas Gleixner <tglx@linutronix.de>
Date:   Fri Feb 16 01:28:04 2007 -0800

    [PATCH] clockevents: i386 drivers

    Add clockevent drivers for i386: lapic (local) and PIT/HPET (global).  Update
    the timer IRQ to call into the PIT/HPET driver's event handler and the
    lapic-timer IRQ to call into the lapic clockevent driver.  The assignement of
    timer functionality is delegated to the core framework code and replaces the
    compile and runtime evalution in do_timer_interrupt_hook()

    Use the clockevents broadcast support and implement the lapic_broadcast
    function for ACPI.

    No changes to existing functionality.

    [ kdump fix from Vivek Goyal <vgoyal@in.ibm.com> ]
    [ fixes based on review feedback from Arjan van de Ven <arjan@infradead.org> ]
    Cleanups-from: Adrian Bunk <bunk@stusta.de>
    Build-fixes-from: Andrew Morton <akpm@osdl.org>
    Signed-off-by: Thomas Gleixner <tglx@linutronix.de>
    Signed-off-by: Ingo Molnar <mingo@elte.hu>
    Cc: john stultz <johnstul@us.ibm.com>
    Cc: Roman Zippel <zippel@linux-m68k.org>
    Cc: Andi Kleen <ak@suse.de>
    Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
    Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>

commit 79bf2bb335b85db25d27421c798595a2fa2a0e82
Author: Thomas Gleixner <tglx@linutronix.de>
Date:   Fri Feb 16 01:28:03 2007 -0800

    [PATCH] tick-management: dyntick / highres functionality

    With Ingo Molnar <mingo@elte.hu>

    Add functions to provide dynamic ticks and high resolution timers.  The code
    which keeps track of jiffies and handles the long idle periods is shared
    between tick based and high resolution timer based dynticks.  The dyntick
    functionality can be disabled on the kernel commandline.  Provide also the
    infrastructure to support high resolution timers.

    Signed-off-by: Thomas Gleixner <tglx@linutronix.de>
    Signed-off-by: Ingo Molnar <mingo@elte.hu>
    Cc: john stultz <johnstul@us.ibm.com>
    Cc: Roman Zippel <zippel@linux-m68k.org>
    Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
    Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>

commit f8381cba04ba8173fd5a2b8e5cd8b3290ee13a98
Author: Thomas Gleixner <tglx@linutronix.de>
Date:   Fri Feb 16 01:28:02 2007 -0800

    [PATCH] tick-management: broadcast functionality

    With Ingo Molnar <mingo@elte.hu>

    Add broadcast functionality, so per cpu clock event devices can be registered
    as dummy devices or switched from/to broadcast on demand.  The broadcast
    function distributes the events via the broadcast function of the clock event
    device.  This is primarily designed to replace the switch apic timer to / from
    IPI in power states, where the apic stops.

    Signed-off-by: Thomas Gleixner <tglx@linutronix.de>
    Signed-off-by: Ingo Molnar <mingo@elte.hu>
    Cc: john stultz <johnstul@us.ibm.com>
    Cc: Roman Zippel <zippel@linux-m68k.org>
    Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
    Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>

commit 906568c9c668ff994f4078932ec6ae1e3950d1af
Author: Thomas Gleixner <tglx@linutronix.de>
Date:   Fri Feb 16 01:28:01 2007 -0800

    [PATCH] tick-management: core functionality

    With Ingo Molnar <mingo@elte.hu>

    The tick-management code is the first user of the clockevents layer.  It takes
    clock event devices from the clock events core and uses them to provide the
    periodic tick.

    Signed-off-by: Thomas Gleixner <tglx@linutronix.de>
    Signed-off-by: Ingo Molnar <mingo@elte.hu>
    Cc: john stultz <johnstul@us.ibm.com>
    Cc: Roman Zippel <zippel@linux-m68k.org>
    Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
    Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>

commit d316c57ff6bfad9557462b9100f25c6260d2b774
Author: Thomas Gleixner <tglx@linutronix.de>
Date:   Fri Feb 16 01:28:00 2007 -0800

    [PATCH] clockevents: add core functionality

    Architectures register their clock event devices, in the clock events core.
    Users of the clockevents core can get clock event devices for their use.  The
    clockevents core code provides notification mechanisms for various clock
    related management events.

    This allows to control the clock event devices without the architectures
    having to worry about the details of function assignment.  This is also a
    preliminary for high resolution timers and dynamic ticks to allow the core
    code to control the clock functionality without intrusive changes to the
    architecture code.

    [Fixes-by: Ingo Molnar <mingo@elte.hu>]
    Signed-off-by: Thomas Gleixner <tglx@linutronix.de>
    Signed-off-by: Ingo Molnar <mingo@elte.hu>
    Cc: Roman Zippel <zippel@linux-m68k.org>
    Cc: john stultz <johnstul@us.ibm.com>
    Cc: Andi Kleen <ak@suse.de>
    Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
    Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
```
