---
layout: post
title:  "host-bridge is pci device BUT NOT pci bridge"
author: fuqiang
date:   2025-01-23 21:37:00 +0800
categories: [pcie, host_bridge]
tags: [pcie,host_bridge]
---

## 查看host-bridge配置空间
```

[root@A06-R08-I134-73-919XB72 openEuler-2403]# lspci -xxx -s 00:00.0
00: [86 80]  [00 2f]  [40 05]   [10 00]     02        [00 00 06]    00 00 [00] 00
    [vendor] [device] [command] [status][revision id] [class_code]         |
                                                                           |
                                                                          header type  [ type 0]
10: [00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
20: 00 00 00 00 00 00 00 00](bar) [00 00 00 00]     [86 80]  [00 00]
                                  [cardbus CIS ptr] [subsys  [subsystem id]
                                                    vendor id]
30: 00 00 00 00 [90] 00 00 00 00 00 00 00 00 [01] 00 00
                 cap pointor                 interrupt pin
40: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
50: 01 e0 ff c7 00 00 00 00 00 00 00 00 00 00 00 00
60: 05 90 02 01 00 00 00 00 00 00 00 00 00 00 00 00
70: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
80: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
90: 10 e0 42 00 00 80 00 00 00 00 00 00 41 38 79 00
a0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
b0: 00 00 00 00 9e 13 00 00 00 00 00 00 06 00 00 00
c0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
d0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
e0: 01 00 03 00 08 00 00 00 00 00 00 00 00 00 00 00
f0: 04 00 00 00 00 00 00 00 09 00 00 00 00 00 00 00
```

## 传统方式读取pci配置空间

host bridge的提供了两个io端口`0xcf8`(config address), `0xcfc`(config_data)


相关代码:
```
pci_bus_read_config_##size
  pci_read
    raw_pci_read
      pci_conf1_read
```

```cpp
int raw_pci_read(unsigned int domain, unsigned int bus, unsigned int devfn,
                                                int reg, int len, u32 *val)
{
        if (domain == 0 && reg < 256 && raw_pci_ops)
                return raw_pci_ops->read(domain, bus, devfn, reg, len, val);
        if (raw_pci_ext_ops)
                return raw_pci_ext_ops->read(domain, bus, devfn, reg, len, val);
        return -EINVAL;
}

//对于pci type 0/1来说
static int pci_conf1_read(unsigned int seg, unsigned int bus,
                          unsigned int devfn, int reg, int len, u32 *value)
{
        unsigned long flags;

        if (seg || (bus > 255) || (devfn > 255) || (reg > 4095)) {
                *value = -1;
                return -EINVAL;
        }

        raw_spin_lock_irqsave(&pci_config_lock, flags);
        //将 config address写入 CF8
        outl(PCI_CONF1_ADDRESS(bus, devfn, reg), 0xCF8);
        //从CFC中读取
        switch (len) {
        case 1:
                *value = inb(0xCFC + (reg & 3));
                break;
        case 2:
                *value = inw(0xCFC + (reg & 2));
                break;
        case 4:
                *value = inl(0xCFC);
                break;
        }

        raw_spin_unlock_irqrestore(&pci_config_lock, flags);

        return 0;
}
```
通过下面`bpftrace`命令抓取`lspci -xxx -s 00:00.0`是否会调用该函数:
```
bpftrace -e 'kfunc:vmlinux:pci_conf1_read { printf("Device: %x:%x \n", args->bus, args->devfn); }'
```

输出如下:
```
Device: 0:0 0
Device: 0:0 4
Device: 0:0 8
Device: 0:0 c
...
Device: 0:0 f0
Device: 0:0 f4
Device: 0:0 f8
Device: 0:0 fc
```
可以看到其一共读取了256 byte

## 参考链接
1. [Intel® Platform Innovation Framework for EFI PCI Host Bridge Resource Allocation Protocol Specification](https://www.intel.com/content/dam/doc/reference-guide/efi-pci-host-bridge-allocation-protocol-specification.pdf)
