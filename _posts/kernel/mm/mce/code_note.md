## do_machine_check
```sh
do_machine_check
=> mce_gather_info
   => m->mcgstatus = mce_rdmsrl(MSR_IA32_MCG_STATUS);
   => if regs
      => if m->mcgstatus & (MCG_STATUS_RIPV|MCG_STATUS_EIPV):
         ## MCG_STATUS_RIPV: 说明可以从当前异常现场恢复到 被interrupted 现场
         ## 也就是说regs->ip 是有效的，如果该field为0，说明保存的这个ip很可能
         ## 不是之前被中断的现场的ip了
   
         ## MCG_STATUS_EIPV: 说明是异常堆栈中保存的ip指向的指令触发的MCE
         => m->ip = regs->ip;
         => m->cs = regs->cs;
     => if (mca_cfg.rip_msr)
        => m->ip = mce_rdmsrl(mca_cfg.rip_msr)
=> no_way_out = mce_no_way_out(err, msg, *validp, regs)
   => loop every banks
      => m->status = mce_rdmsrl(mca_msr_reg(i, MCA_STATUS))
      ## 说明，本次mce，不是由该bank 代表的error触发的，其内的信息是无
      ## 效的
      => if (!(m->status & MCI_STATUS_VAL))
         => continue
      => arch___set_bit(i, validp);
      ## 这两个ifu相关的需要看下spec 
      => if (mce_flags.snb_ifu_quirk) quirk_sandybridge_ifu(i, m, regs)
      => if (mce_flags.zen_ifu_quirk) quirk_zen_ifu(i, m, regs)
      => m->bank = i;
      ## 如果该bank的错误处理已经需要PANIC了, 可以直接处理该错误，不需要
      ## 再看其他的bank了
      ##
      ## 如果是PANIC 以上的动作，则返回1。表示no_way_out, 含义是:
      ## 机器都坏成这样了，我能怎么办...
      => if mce_severity(m, regs, &tmp, true) >= MCE_PANIC_SEVERITY:
         => if intel : mce_severity_intel(m, regs, msg, is_excp)
         => if amd   : mce_severity_amd(m, regs, msg, is_excp);
         => mce_read_aux()
         => *msg = tmp;
         => return 1;
   => return 0
=> if !(m->mcgstatus & MCG_STATUS_RIPV):
   ## 说明异常堆栈中存储的ip 是无效的，如果从堆栈中恢复被中断的上下文，
   ## 得到的很可能是错误的上下文，所以kill it
   => kill_current_task = 1

=> if m->cpuvendor == X86_VENDOR_INTEL || m->cpuvendor == X86_VENDOR_ZHAOXIN
   ## intel cpu 的MCG_STATUS 上支持 LMCES bit. 而LMCES位使能，表示mce只发送到该cpu上
   => lmce = m->mcgstatus & MCG_STATUS_LMCES
   ## 如果只发送给这个cpu的话，直接panic
=> if (lmce)  
   => if (no_way_out) mce_panic("Fatal local machine check", &err, msg);
-> else 
   => order = mce_start(&no_way_out);

=> taint = __mc_scan_banks(&err, regs, final, toclear, valid_banks, no_way_out, &worst);
=> mce_end()
....
```


##  mce_severity_amd
```sh
mce_severity_amd
=> if m->status & MCI_STATUS_PCC: 
   ## 处理器状态corrupt, 需要重启
   => return MCE_PANIC_SEVERITY
=> if m->status & MCI_STATUS_DEFERRED
   ## 是deffer error, 不需要立即处理
   ## 但是deffer error，优先级也挺高，毕竟也是
   ## UC, 这个字段只有amd支持
   => return MCE_DEFERRED_SEVERITY
   ## 代码注释:
   ## 
   ## If the UC bit is not set, the system either corrected 
   ## or deferred the error. No action will be required after 
   ## logging the error.
   ## 
   ## 但是deferred error 会走到这个地方么
=> if !m->status & MCI_STATUS_UC:
   => return MCE_KEEP_SEVERITY

## 下面主要处理 UC

## amd sdm中有提到，如果在不支持 overflow recov的机器上出现了
## overflow, 无法error recovery:
## 
##   > Error recovery is not possible when:
##   > - The error-overflow status bit (MCi_STATUS[OVER]) is set
##   >   and the processor does not support
##   >   recoverable MCi_STATUS overflow (as indicated by feature bit CPUID
##   >   Fn8000_0007_EBX[McaOverflowRecov] = 0).

=> if m->status & MCI_STATUS_OVER) && !mce_flags.overflow_recov:
   => return MCE_PANIC_SEVERITY

## 处理器不支持error recovery
## 
## > The processor does not support Machine Check Recovery
## > as indicated by feature bit CPUID Fn8000_0007_EBX[SUCCOR].
=> if mce_flags.succor:
   => return MCE_PANIC_SEVERITY

## 如果UC出现在用户态上下文，kernel可以选择杀用户态
## UC 一旦出现在了kernel 上下文, kernel只能自杀了
=> if error_context(m, regs) == IN_KERNEL:
   => ret = MCE_PANIC_SEVERITY
```

## `__mc_scan_banks`

## mce_log
最终会`sched_work(&mce_work)` -- `mce_gen_pool_process`
```sh
mce_gen_pool_process
=> foreach mce_event_list
   => x86_mce_decoder_chain --> amd_decode_mce

amd_decode_mce
=> if boot_cpu_has(X86_FEATURE_SMCA)
   => decode_smca_error

decode_smca_error
=> decode_dram_ecc --> decode_umc_error     ##-- >= 0x17, ZEN 1 +
## 根据node-id 获取mci - mem_ctl_info
=> mci = edac_mc_find(node_id);
=> pvt->ops->get_err_info(m, &err);
   => umc_get_err_info
      ## https://lore.kernel.org/all/20190226172532.12924-1-Yazen.Ghannam@amd.com/T/#u
      ##
      ## 通过ipid 和 synd 两个寄存器就可以获取到
      ## channel 和 csrow
      => err->channel = (m->ipid & GENMASK(31, 0)) >> 20;
      => err->csrow = m->synd & 0x7;
=> sys_addr = amd_convert_umc_mca_addr_to_sys_addr(&a_err);
=> error_address_to_page_and_offset(sys_addr, &err);
=> __log_ecc_error
   => edac_mc_handle_error()
      => foreach :: mci_for_each_dimm(mci, dimm)
         => find dimm
         => copy dimm->label to e->label
         => get row
         => get chain
      => edac_inc_csrow(e, row, chan)
         => mci->csrows[row]->channels[chan]->ce/ue_count + count
      => edac_raw_mc_handle_error()
         => 
```

