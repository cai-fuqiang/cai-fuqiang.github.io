# 透传本地网卡
1. 查看网卡pci 相关信息
   ```sh
   [root@fedora]~#  lspci |grep Eth
   04:00.0 Ethernet controller: Realtek Semiconductor Co., Ltd. RTL8111/8168/8411 PCI Express Gigabit Ethernet Controller (rev 15)
   [root@fedora]~# lspci -nn -s 04:00.0
   04:00.0 Ethernet controller [0200]: Realtek Semiconductor Co., Ltd. RTL8111/8168/8411 PCI Express Gigabit Ethernet Controller [10ec:8168] (rev 15)
   ```
2. 解绑当前驱动
   ```sh
   [root@fedora]~# echo 0000:04:00.0 >  /sys/bus/pci/devices/0000:04:00.0/driver/unbind
   ```
3. 加载`vfio-pci` 驱动
   ```
   [root@fedora]~# modprobe vfio-pci
   ```
4. 将设备绑定`vfio-pci` driver
   ```
   [root@fedora]~# echo 10ec 8168 > /sys/bus/pci/drivers/vfio-pci/new_id
   ```
5. 验证是否绑定成功
   ```
   [root@fedora]~# lspci -vvv -s 04:00.0 |grep driver
            Kernel driver in use: vfio-pci
   [root@fedora]~# ls -l /sys/bus/pci/devices/0000:04:00.0/ |grep  "driver"
   lrwxrwxrwx 1 root root     0 Oct  9 09:46 driver -> ../../../../bus/pci/drivers/vfio-pci
   ```

> NOTE 
>
> 假如说只透传这一个设备，需要验证下，该设备所在的group是否只有这一个设备，
> 否则，需要将整个group的设备透传
>
> ```
> [root@fedora]~# dmesg |grep 04:00.0|grep iommu
> [    0.485099] pci 0000:04:00.0: Adding to iommu group 16
> [root@fedora]~# dmesg |grep 'iommu group 16'
> [    0.485099] pci 0000:04:00.0: Adding to iommu group 16
> ```

# 在虚拟机中使用透传设备
在qemu中添加如下设备
```
-device vfio-pci,host=0000:04:00.0
```

启动虚拟机，查看该设备:
```
[root@localhost ~]# lspci |grep Eth |grep RTL
00:03.0 Ethernet controller: Realtek Semiconductor Co., Ltd. RTL8111/8168/8411 PCI Express Gigabit Ethernet Controller (rev 15)
```

可以看到，该设备已经透传到虚拟机

# 嵌套透传
为了方便调试kernel，我们嵌套透传下该网卡

1. 在qemu cmdline 中，我们添加如下命令行
   ```
   -device intel-iommu,caching-mode=on 
   ```
   > NOTE
   >
   > 1. 一定要添加`caching-mode=on`参数，否则透传设备时会出错。
   > 2. kernel cmdline 中同样要添加`intel_iommu=on`参数

2. 同在host上，在l1 guest中，也执行类似的命令(不再展开)
   ```
   echo 0000:00:03.0 > /sys/bus/pci/devices/0000\:00\:03.0/driver/unbind
   modprobe vfio-pci
   echo 10ec 8168 > /sys/bus/pci/drivers/vfio-pci/new_id
   ```
