[root@localhost ~]# [ 1981.302758] BUG: kernel NULL pointer dereference, address: 0000000000000000
[ 1981.304802] #PF: supervisor read access in kernel mode
[ 1981.306146] #PF: error_code(0x0000) - not-present page
[ 1981.307517] PGD 0 P4D 0
[ 1981.308195] Oops: 0000 [#1] PREEMPT SMP PTI
[ 1981.309319] CPU: 0 PID: 0 Comm: swapper/0 Not tainted 5.15.0+ #22
[ 1981.310879] Hardware name: QEMU Standard PC (i440FX + PIIX, 1996), BIOS rel-1.17.0-0-gb52ca86e094d-prebuilt.qemu.org 04/01/2014
[ 1981.313787] RIP: 0010:update_blocked_averages+0x354/0x6b0
[ 1981.315201] Code: 01 00 00 00 00 00 00 48 89 83 48 01 00 00 48 8b 83 a0 00 00 00 48 85 c0 0f 85 12 02 00 00 48 83 bb b0 00 00 00 00 44 0f 45 e8 <49> 8b 84 24 40 01 00 00 49 8d ac 24 40 01 00 00 4c 89 e3 4c 8d a0
[ 1981.319877] RSP: 0018:ffffaf8940003eb8 EFLAGS: 00010046
[ 1981.321218] RAX: 0000000000000000 RBX: ffff989b42faba00 RCX: ffff989b7baec110
[ 1981.323046] RDX: 0000000000000000 RSI: ffff989b51b69600 RDI: 0000000000000050
[ 1981.324861] RBP: ffff989b42fabb40 R08: 0000000000000000 R09: 0000000000000115
[ 1981.326684] R10: 0000000000000000 R11: 0000000000000000 R12: fffffffffffffec0
[ 1981.328502] R13: 0000000000000001 R14: ffff989b7bcab7c0 R15: 0000000000000000
[ 1981.330329] FS:  0000000000000000(0000) GS:ffff989b7ba00000(0000) knlGS:0000000000000000
[ 1981.332369] CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
[ 1981.333840] CR2: 0000000000000000 CR3: 00000001084f2000 CR4: 00000000000006f0
[ 1981.335666] Call Trace:
[ 1981.336352]  <IRQ>
[ 1981.336909]  ? rebalance_domains+0xe5/0x3b0
[ 1981.338004]  ? kvm_clock_read+0x14/0x30
[ 1981.339015]  _nohz_idle_balance.isra.135+0x276/0x300
[ 1981.340320]  __do_softirq+0xf3/0x2e6
[ 1981.341279]  irq_exit_rcu+0xb7/0xf0
[ 1981.342175]  sysvec_call_function_single+0x9e/0xc0
[ 1981.343452]  </IRQ>
[ 1981.344018]  <TASK>
[ 1981.344615]  asm_sysvec_call_function_single+0x12/0x20
[ 1981.345933] RIP: 0010:native_safe_halt+0xb/0x10
[ 1981.347113] Code: 69 ff ff ff 7f 5b c3 65 48 8b 04 25 c0 bb 01 00 f0 80 48 02 20 48 8b 00 a8 08 75 c3 eb 82 cc eb 07 0f 00 2d 19 ca 4f 00 fb f4 <c3> 0f 1f 40 00 eb 07 0f 00 2d 09 ca 4f 00 f4 c3 cc cc cc cc cc 0f
[ 1981.351785] RSP: 0018:ffffffff96c03e98 EFLAGS: 00000202
[ 1981.353126] RAX: ffffffff9610f870 RBX: 0000000000000000 RCX: 7ffffe32be2d510c
[ 1981.354953] RDX: 0000000000000000 RSI: ffffffff96934b22 RDI: ffffffff96946dee
[ 1981.356772] RBP: ffffffff971b7260 R08: 000002586b2d7255 R09: ffff989b52b2e600
[ 1981.358595] R10: 0000000000000018 R11: 0000000000000000 R12: ffffffffffffffff
[ 1981.360416] R13: 0000000000000000 R14: 0000000000000000 R15: ffffffff96c14940
[ 1981.362214]  ? mwait_idle+0x80/0x80
[ 1981.363143]  default_idle+0xa/0x10
[ 1981.364050]  default_idle_call+0x33/0xe0
[ 1981.365085]  do_idle+0x20c/0x2a0
[ 1981.365951]  cpu_startup_entry+0x19/0x20
[ 1981.366984]  start_kernel+0x682/0x6a9
[ 1981.367962]  secondary_startup_64_no_verify+0xc2/0xcb
[ 1981.369284]  </TASK>
[ 1981.369881] Modules linked in: sunrpc i2c_piix4 i2c_core sg floppy pcspkr joydev ip_tables xfs libcrc32c sd_mod t10_pi crc_t10dif crct10dif_generic ata_generic crct10dif_common pata_acpi virtio_net net_failover ata_piix virtio_scsi failover libata virtio_pci virtio_pci_legacy_devw
[ 1981.377127] CR2: 0000000000000000
[ 1981.378023] ---[ end trace 8dd81892567853e6 ]---
[ 1981.379214] RIP: 0010:update_blocked_averages+0x354/0x6b0
[ 1981.380621] Code: 01 00 00 00 00 00 00 48 89 83 48 01 00 00 48 8b 83 a0 00 00 00 48 85 c0 0f 85 12 02 00 00 48 83 bb b0 00 00 00 00 44 0f 45 e8 <49> 8b 84 24 40 01 00 00 49 8d ac 24 40 01 00 00 4c 89 e3 4c 8d a0
[ 1981.385284] RSP: 0018:ffffaf8940003eb8 EFLAGS: 00010046
[ 1981.386632] RAX: 0000000000000000 RBX: ffff989b42faba00 RCX: ffff989b7baec110
[ 1981.388451] RDX: 0000000000000000 RSI: ffff989b51b69600 RDI: 0000000000000050
[ 1981.390263] RBP: ffff989b42fabb40 R08: 0000000000000000 R09: 0000000000000115
[ 1981.392058] R10: 0000000000000000 R11: 0000000000000000 R12: fffffffffffffec0
[ 1981.393875] R13: 0000000000000001 R14: ffff989b7bcab7c0 R15: 0000000000000000
[ 1981.395701] FS:  0000000000000000(0000) GS:ffff989b7ba00000(0000) knlGS:0000000000000000
[ 1981.397745] CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
[ 1981.399210] CR2: 0000000000000000 CR3: 00000001084f2000 CR4: 00000000000006f0
[ 1981.401036] Kernel panic - not syncing: Fatal exception in interrupt
[ 1982.461954] Shutting down cpus with NMI
[ 1982.463063] Kernel Offset: 0x14800000 from 0xffffffff81000000 (relocation range: 0xffffffff80000000-0xffffffffbfffffff)
[ 1982.465747] ---[ end Kernel panic - not syncing: Fatal exception in interrupt ]---
