--- 
layout: post
title:  "qemu brige migration"
author: fuqiang
date:   2025-01-21 23:02:00 +0800
categories: [qemu,pci_bridge]
tags: [qemu_pci_bridge]
---

## PCI bridge dev vmstate

```cpp
static const VMStateDescription pci_bridge_dev_vmstate = {
    .name = "pci_bridge",
    .priority = MIG_PRI_PCI_BUS,
    .fields = (VMStateField[]) {
        VMSTATE_PCI_DEVICE(parent_obj, PCIBridge),
        SHPC_VMSTATE(shpc, PCIDevice, pci_device_shpc_present),
        VMSTATE_END_OF_LIST()
    }
};
```

而`pci_bridge` type为:
```cpp

static const TypeInfo pci_bridge_type_info = {
    .name = TYPE_PCI_BRIDGE,
    .parent = TYPE_PCI_DEVICE,
    .instance_size = sizeof(PCIBridge),
    .abstract = true,
};

#define TYPE_PCI_BRIDGE "base-pci-bridge"
OBJECT_DECLARE_SIMPLE_TYPE(PCIBridge, PCI_BRIDGE)

struct PCIBridge {
    /*< private >*/
    PCIDevice parent_obj;
    /*< public >*/

    /* private member */
    PCIBus sec_bus;
    /*
     * Memory regions for the bridge's address spaces.  These regions are not
     * directly added to system_memory/system_io or its descendants.
     * Bridge's secondary bus points to these, so that devices
     * under the bridge see these regions as its address spaces.
     * The regions are as large as the entire address space -
     * they don't take into account any windows.
     */
    MemoryRegion address_space_mem;
    MemoryRegion address_space_io;

    PCIBridgeWindows *windows;

    pci_map_irq_fn map_irq;
    const char *bus_name;
};
```
其`pci_bridge` type的 instance_type为`PCIBridge`, 而 `pci_bridge_dev_vmstate`中，并
没有保存太多信息，例如`address_space_io`, `address_space_mem`相关信息. 但是这些
信息又必须迁移到目的端。那是怎么传递的呢?

## PCI bridge migrate data

像`PCIBridge`中的信息，其实在PCI device的配置空间中都有相应的配置空间，所以
只需要将PCI device配置空间传过去就可以了。

`pci_bridge_type_info.fields`中有对parent obj的引用。通过pci bridge
的`TypeInfo`，可以看到，其parent obj instance为 `PCIDevice`, 我们直接看对这个
instance的VMSD:
```cpp
const VMStateDescription vmstate_pci_device = {
    .name = "PCIDevice",
    .version_id = 2,
    .minimum_version_id = 1,
    .fields = (VMStateField[]) {
        VMSTATE_INT32_POSITIVE_LE(version_id, PCIDevice),
        VMSTATE_BUFFER_UNSAFE_INFO_TEST(config, PCIDevice,
                                   migrate_is_not_pcie,
                                   0, vmstate_info_pci_config,
                                   PCI_CONFIG_SPACE_SIZE),
        VMSTATE_BUFFER_UNSAFE_INFO_TEST(config, PCIDevice,
                                   migrate_is_pcie,
                                   0, vmstate_info_pci_config,
                                   PCIE_CONFIG_SPACE_SIZE),
        VMSTATE_BUFFER_UNSAFE_INFO(irq_state, PCIDevice, 2,
                                   vmstate_info_pci_irq_state,
                                   PCI_NUM_PINS * sizeof(int32_t)),
        VMSTATE_END_OF_LIST()
    }
};
```
我们这里只关心PCI bridge, 来看下其`VMStateInfo`
```cpp
static VMStateInfo vmstate_info_pci_config = {
    .name = "pci config",
    .get  = get_pci_config_device,
    .put  = put_pci_config_device,
};
```
其会在`vmstate_save_state`相关流程中调用`put`, 将`[PCIDevice.config,
PCIDevice.confgi + PCI_CONFIG_SPACE_SIZE]` 传到目的端。

然后在`vmstate_load_state`流程中 调用`get`接口。

我们分别来看下:

**put**

```cpp
static int put_pci_config_device(QEMUFile *f, void *pv, size_t size,
                                 const VMStateField *field, JSONWriter *vmdesc)
{
    const uint8_t **v = pv;
    assert(size == pci_config_size(container_of(pv, PCIDevice, config)));
    qemu_put_buffer(f, *v, size);

    return 0;
}
```
比较简单，只是做了下size的校验, 然后将整个配置空间传过去


我们来详细看下get:

```cpp
static int get_pci_config_device(QEMUFile *f, void *pv, size_t size,
                                 const VMStateField *field)
{
    PCIDevice *s = container_of(pv, PCIDevice, config);
    PCIDeviceClass *pc = PCI_DEVICE_GET_CLASS(s);
    uint8_t *config;
    int i;

    assert(size == pci_config_size(s));
    config = g_malloc(size);

    qemu_get_buffer(f, config, size);
    //==(1)==
    for (i = 0; i < size; ++i) {
        if ((config[i] ^ s->config[i]) &
            s->cmask[i] & ~s->wmask[i] & ~s->w1cmask[i]) {
            error_report("%s: Bad config data: i=0x%x read: %x device: %x "
                         "cmask: %x wmask: %x w1cmask:%x", __func__,
                         i, config[i], s->config[i],
                         s->cmask[i], s->wmask[i], s->w1cmask[i]);
            g_free(config);
            return -EINVAL;
        }
    }
    //==(2)==
    memcpy(s->config, config, size);

    //==(3)==
    pci_update_mappings(s);
    if (pc->is_bridge) {
        PCIBridge *b = PCI_BRIDGE(s);
        pci_bridge_update_mappings(b);
    }

    memory_region_set_enabled(&s->bus_master_enable_region,
                              pci_get_word(s->config + PCI_COMMAND)
                              & PCI_COMMAND_MASTER);

    g_free(config);
    return 0;
}
```

这里面主要有几个工作:
1. 比较配置空间（这里不是比较所有的，而是根据cmask, wmask, w1cmask 来选择比较哪些字段)
2. 如果发现上面的比较没有问题，将整个的配置空间`s->config`copy到目的端的`PCIDevice->config`
   中
3. mr相关操作
   + 释放old mr
   + 注册新的mr

## 比较配置空间

解释下几个mask含义:

* cmask: 表示要哪些配置空间是需要在load时，做compare check
* wmask: 表示这些地址在配置空间中的是 R/W 的
* w1cmask: 表示这些地址在配置空间中是 `Write 1 to Clear`

后面两个都表示该配置空间地址可写那么就意味着，这些是OS 可以配置的，所以这些信息不用compare.

以bridge的io空间为例, 首先io window是R/W的，所以需要置位wmask
```cpp
static void pci_init_mask_bridge(PCIDevice *d)
{
    ...
    d->wmask[PCI_IO_BASE] = PCI_IO_RANGE_MASK & 0xff;
    d->wmask[PCI_IO_LIMIT] = PCI_IO_RANGE_MASK & 0xff;
    ...
    d->cmask[PCI_IO_BASE] |= PCI_IO_RANGE_TYPE_MASK;
    d->cmask[PCI_IO_LIMIT] |= PCI_IO_RANGE_TYPE_MASK;
}
```
但是其又置位cmask, 不知道原因。

## mr相关操作

这个主要分为两部分:
1. PCI Device 的bar空间
2. PCI Bridge 的 io / memory /pref memory window

但是两者本质是相同的，都需要在 parent mr 上 overlap.
