--- 
layout: post
title:  "when load control register during in switching  rmode 2 pmode"
author: fuqiang
date:   2024-04-22 10:30:00 +0800
categories: [my_test]
tags: [protect-mode]
---

# the intel sdm suggestion

From intel sdm `10.9.1 Switching to Protected Mode`, it give following
steps:

```
...

3. Execute a MOV CR0 instruction that sets the PE flag (and optionally the PG
   flag) in control register CR0.

4. Immediately following the MOV CR0 instruction, execute a far JMP or far CALL
   instruction. (This operation is typically a far jump or call to the next
   instruction in the instruction stream.)

5. It can be found that after executing "MOV to CR0" (set PE), the relevant
   instructions of the load control register can be executed.

...

9. After entering protected mode, the segment registers continue to hold the
   contents they had in real-address mode. The JMP or CALL instruction in step
   4 resets the CS register. Perform one of the following operations to update
   the contents of the remaining segment registers.

   + Reload segment registers DS, SS, ES, FS, and GS. If the ES, FS, and/or GS
      registers are not going to be used, load them with a null selector. 
...
```

This means that after we execute the MOV to CR0 (set PE) instruction, it is
best to execute a far jump or call immediately. After completing the above steps, 
go to load control register

But on my own opinion,  after executing "MOV to CR0" (set PE), the CPU has
entered protected mode. At this time, executing MOV to SS, MOV to DS will also
successfully load the control register from the segment descriptor.

# test
I wrote a small program and run it in qemu, part of it is as follows:

```
lgdt %cs:gdt_desc

mov $0x28, %eax
mov %eax, %es

mov $1, %eax
mov %eax, %cr0

mov $0x28, %eax
mov %eax, %es
ljmp $0x10, $.startup_prot
```

The above code modifies the ES selector before and after the mov to CR0 (set
PE) instruction. Debugging using qemu+gdb.

* gdb print information

```
(gdb) ni
38          mov $0x28, %eax
(gdb) ni
39          mov %eax, %es
(gdb)
41          mov $1, %eax
(gdb) ni
42          mov %eax, %cr0
(gdb) ni
44          mov $0x28, %eax
(gdb) ni
45          mov %eax, %es
(gdb) ni
46          ljmp $0x10, $.startup_prot
```

* When gdb is executed to position `39`, use the qemu monitor `info registers`
  command to obtain the ES register value:
  ```
  ES =0028 00000280 0000ffff 00009300
  ```
* When gdb is executed to position `46`, use the qemu monitor `info registers`
  command to obtain the ES register value:
  ```
  ES =0028 00000000 ffffffff 00cf9300 DPL=0 DS   [-WA]
  ```

It can be found that after executing "MOV to CR0" (set PE), the relevant
instructions of the load control register can be executed successfully.

So I want to ask, is it reasonable to execute the "load control register"
instruction immediately after MOV to CR0 (set PE), and what is the meaning of
step 5 in the manual?

Thanks
