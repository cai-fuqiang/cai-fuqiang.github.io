```
commit 1af452e4a4cb8ddc83cb3cee6f2bd8cc5b69cb86
Author: Rusty Russell <rusty@rustcorp.com.au>
Date:   Mon Mar 8 01:12:54 2004 -0800

    [PATCH] make module code use stop_machine.c

    Now we've moved the bogolock code out to stop_machine.c and
    generalized it a little, use it in module.c and delete the duplicate
    code there.

commit 80037662455b250aa5bd6369d6ad164c3ac97615
Author: Rusty Russell <rusty@rustcorp.com.au>
Date:   Mon Mar 8 01:12:45 2004 -0800

    [PATCH] stop_machine_run: Move Bogolock Code Out of module.c

    The "bogolock" code was introduced in module.c, as a way of freezing
    the machine when we wanted to remove a module.  This patch moves it
    out to stop_machine.c and stop_machine.h.

    Since the code changes affinity and proirity, it's impolite to hijack
    the current context, so we use a kthread.  This means we have to pass
    the function rather than implement "stop_machine()" and
    "restart_machine()".
```
