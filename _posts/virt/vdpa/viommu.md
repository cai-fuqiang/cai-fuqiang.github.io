
## note
1. viommu产生的原因
   + 需要pin所有的VM page, 影响内存超配
   + 使虚拟机内存暴露于有缺陷的设备驱动程序(安全，
      这个是最终要的)
2. 

## link

1. ![vIOMMU: Efficient IOMMU Emulation](https://www.usenix.org/legacy/event/atc11/tech/final_files/Amit.pdf)
2. [QEMU-wiki-viommu: Features/VT-d](https://wiki.qemu.org/Features/VT-d)
