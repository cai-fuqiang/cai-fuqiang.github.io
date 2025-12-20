## 调试

## qemu启动参数中增加vfio 设备

```sh
-device vfio-pci,host=0000:01:00.1
```

## 调试vfio_realize
```cpp
vfio_realize
/*
## 此时未初始化vbasedev
(gdb) x/10xg &vdev->vbasedev
0x562babed7130: 0x0000000000000000      0x0000000000000000
0x562babed7140: 0x0000000000000000      0x0000000000000000
0x562babed7150: 0x0000000000000000      0x0000000000000000
0x562babed7160: 0x0000000000000000      0x0000000000000000
0x562babed7170: 0x0000000000000000      0x0000000000000000
*/
|-> vdev->vbasedev.sysfsdev =
     g_strdup_printf("/sys/bus/pci/devices/%04x:%02x:%02x.%01x",
     ...)
/*
 * (gdb) p vdev->vbasedev.sysfsdev
 * $4 = 0x562babd47490 "/sys/bus/pci/devices/0000:01:00.1"
 */

// 初始化其他成员
|-> vdev->vbasedev.name = g_path_get_basename(vdev->vbasedev.sysfsdev);
/* 
 * (gdb) p vdev->vbasedev.name
 * $5 = 0x562babed8890 "0000:01:00.1"
 */

|-> vdev->vbasedev.ops = &vfio_pci_ops;
|-> vdev->vbasedev.type = VFIO_DEVICE_TYPE_PCI;
|-> vdev->vbasedev.dev = DEVICE(vdev);

//下面流程获取group id
|-> tmp = g_strdup_printf("%s/iommu_group", vdev->vbasedev.sysfsdev);
|-> len = readlink(tmp, group_path, sizeof(group_path));
|-> group_name = basename(group_path);
|-> sscanf(group_name, "%d", &groupid)
```
