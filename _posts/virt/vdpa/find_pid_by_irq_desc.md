## 尝试通过irq_desc 推出pir

找到最后一个队列:
```
crash> irq
 ...
 331  ff1100bac72b8600  ff1100bfdd10da80  "vfio-msix[64](0000:35:0b.6)"
```

查找相关结构体:
1. 先查看下`irq_domain`链:
   ```sh
   ## this
   crash> struct irq_desc.irq_data.domain ff1100bac72b8600
     irq_data.domain = 0xff1100bd8a66d380,
   crash> struct irq_domain.name 0xff1100bd8a66d380
     name = 0xff1100bf3227e6e0 "IR-PCI-MSIX-0000:35:0b.6-12",
   
   ## parent
   crash> struct irq_desc.irq_data.parent_data ff1100bac72b8600
     irq_data.parent_data = 0xff1100be76026700,
   crash> struct irq_data.domain 0xff1100be76026700
     domain = 0xff11000101300000,
   crash> struct irq_domain.name 0xff11000101300000
     name = 0xff110001000331d0 "INTEL-IR-11-13",
   
   ## parent->parenet
   crash> struct irq_data.parent_data 0xff1100be76026700
     parent_data = 0xff1100be760268c0,
   crash> struct irq_data.domain 0xff1100be760268c0
     domain = 0xff110001002a6a80,
   crash> struct irq_domain.name 0xff110001002a6a80
     name = 0xff110001000438c8 "VECTOR",
   ```

   整个链条是 `MSIX -> dmar -> Vector`

2. 查找其中断模式
   ```sh
   ## 找到其parent
   crash> struct irq_data 0xff1100be76026700
   struct irq_data {
     mask = 0,
     irq = 331,
     hwirq = 5636096,
     common = 0xff1100bac72b8600,
     chip = 0xffffffff8aed8580 <intel_ir_chip>,
     domain = 0xff11000101300000,
     parent_data = 0xff1100be760268c0,
     chip_data = 0xff1100be760265c0
   }
   ## 其模式和irte index
   crash> struct intel_ir_data.irq_2_iommu.mode 0xff1100be760265c0
     irq_2_iommu.mode = IRQ_POSTING
   crash> struct intel_ir_data.irq_2_iommu.irte_index 0xff1100be760265c0
     irq_2_iommu.irte_index = 86,

   ```
3. 找到其irte
   ```sh
   crash> struct intel_ir_data.irq_2_iommu.iommu 0xff1100be760265c0
     irq_2_iommu.iommu = 0xff1100c0800a6400,

   crash> struct intel_iommu.name 0xff1100c0800a6400
     name = "dmar11\000\000\000\000\000\000",

   crash> p (((struct intel_iommu *)0xff1100c0800a6400)->ir_table->base[86])
   $59 = {
     {
       {
         {
           ...
           {
             p_present = 1,
             p_fpd = 0,
             p_res0 = 0,
             p_avail = 0,
             p_res1 = 0,
             p_urgent = 0,
             p_pst = 1,      ## 表明是posted ，而非remapping
             p_vector = 34,  ## notify
             p_res2 = 0,
             pda_l = 48598799
           },
           low = 13358736149114421249
         },
         {
           ...
           {
             p_sid = 13662,
             p_sq = 0,
             p_svt = 1,
             p_res3 = 0,
             pda_h = 183
           },
           high = 785979290974
         }
       },
       irte = 14498758827846428509304250335233
     }
   }
   ```
4. 通过irte找到其pid
   ```sh
   ## 此时pid地址为pda_l << 6 + pda_h << 32
   ##    183 << 32 + 48598799 << 6 = 789089338304
   
   ## 找到pid所在地址
   crash> eval 789089338304
   hexadecimal: b7b963c3c0
       decimal: 789089338304
         octal: 13367130741700
        binary: 0000000000000000000000001011011110111001011000111100001111000000
   crash> ptov b7b963c3c0
   VIRTUAL           PHYSICAL
   ff1100b7b963c3c0  b7b963c3c0
   
   crash> struct pi_desc ff1100b7b963c3c0
   struct pi_desc {
     pir = {0, 0, 0, 0, 0, 0, 0, 0},
     {
       {
         on = 0,
         sn = 0,
         rsvd_1 = 0,
         nv = 241 '\361',
         rsvd_2 = 0 '\000',
         ndst = 13     ## 这个注意是physical apicid，而不是cpuid
       },
       control = 55850369024
     },
     rsvd = {0, 0, 0, 0, 0, 0}
   }
   ```

5. 验证(从host和vm中)
   ```sh
   ## 也可以找到vcpu_vmx 结构体
   crash> vcpu_vmx.vcpu.cpu ff1100b7b963a440
     vcpu.cpu = 118,
   crash> vcpu_vmx.vcpu.vcpu_idx ff1100b7b963a440
     vcpu.vcpu_idx = 72,

   ## 通过外部也可以找到这个关系
   [root@A01-R15-I242-88-1222442 ~]# ps -o comm,pid,ppid,psr -p `pidof qemu-system-x86_64` -T  |grep 118
   CPU 72/KVM      1644752       1 118

   ## 通过/proc/cpuinfo 查找其apicid:
   [root@A01-R15-I242-88-1222442 ~]# cat /proc/cpuinfo |grep -E  "processor|apicid"
   processor       : 118
   apicid          : 13
   initial apicid  : 13
   ## 虚拟机中找到该irq, 可以发现确实是72 cpu
   crash> irq -a
    92 virtio0-output.31    72
   ```
