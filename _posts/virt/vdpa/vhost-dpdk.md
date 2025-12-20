## VFIO 初始化流程

调试堆栈
```
rte_vfio_setup_device+0
pci_vfio_map_resource+33
rte_pci_map_device+70
ifcvf_vfio_setup+328
ifcvf_pci_probe+406
rte_pci_probe_one_driver+845
pci_probe_all_drivers+80
pci_probe+80
rte_bus_probe+79
rte_eal_init+3100
```
### ifcvf_vfio_setup
```sh
ifcvf_vfio_setup
|=> rte_pci_device_name
|=> rte_vfio_get_group_num(,, &iommu_group_num)
    ==> 通过 /sys/bus/pci/devices/$BDF/iommu_group软链接
        找到该device的 iommu_group id
## 创建container fd
|=> rte_vfio_container_create
    |=> rte_vfio_get_container_fd
        |=> open("/dev/vfio/vfio")
        |=> ioctl(vfio_container_fd, VFIO_GET_API_VERSION)
        |=> vfio_has_supported_extensions
            |=> foreach_iommu_type()
                |=> ioctl(vfio_container_fd, VFIO_CHECK_EXTENSION, t->type_id);
## 绑定group和 container
|=> internal->vfio_group_fd = rte_vfio_container_group_bind(
                internal->vfio_container_fd, iommu_group_num);
|=> rte_pci_map_device
    |=> switch(dev->kdrv)
        |=> case RTE_PCI_KDRV_VFIO:
            |=> pci_vfio_map_resource
        |=> case RTE_PCI_KDRV_IGB_UIO/RTE_PCI_KDRV_UIO_GENERIC:
            |=> pci_uio_map_resource
```

### pci_vfio_map_resource
初始化设备的主要函数, 作用是map resource, 并进行一些配置, 并且将irq enable,
并绑定eventfd
```sh
pci_vfio_map_resource
|=> if rte_eal_process_type() == RTE_PROC_PRIMARY:
    |=> pci_vfio_map_resource_primary()
        |=> 
        |=> rte_vfio_setup_device()
            |=> get vfio_group_id 同 ifcvf_vfio_setup
            |=> ioctl(vfio_group_fd, VFIO_GROUP_GET_STATUS, &group_status)
            |=> if !(group_status.flags & VFIO_GROUP_FLAGS_CONTAINER_SET)
                |=> 没有设置container, 在该分支中分配container, 并将该group绑定
                    分配的container, 剩下的代码先不关心
            ## 通过 BDF 获取 vfio_dev_fd
            |=> *vfio_dev_fd = ioctl(vfio_group_fd, VFIO_GROUP_GET_DEVICE_FD, dev_addr);
            ## get device_info
            ## 主要 包括 irq, regions, caps相关信息
            |=> ioctl(*vfio_dev_fd, VFIO_DEVICE_GET_INFO, device_info);
        |=> rte_intr_dev_fd_set(dev->intr_handle, vfio_dev_fd)
        |=> pci_vfio_get_region_info(vfio_dev_fd, &reg,
              VFIO_PCI_CONFIG_REGION_INDEX);
            |=> ioctl(vfio_dev_fd, VFIO_DEVICE_GET_REGION_INFO, ri);
        |=> pci_vfio_get_msix_bar(dev, &vfio_res->msix_table)
            ## 不展开，通过cap link 一直查询到 PTE_PCI_CAP_ID_MSIX cap, 
            ## 返回其在config space中的offset
            |=> cap_offset = rte_pci_find_capability(dev, RTE_PCI_CAP_ID_MSIX);
            ## 获取 bar base
            |=> rte_pci_read_config(dev, &reg, sizeof(reg), cap_offset +
                   RTE_PCI_MSIX_TABLE)
            ## 获取flag
            |=> rte_pci_read_config(dev, &flags, sizeof(flags), cap_offset +
                 RTE_PCI_MSIX_FLAGS)
            ## 赋值给本地变量中的成员
            ## !!!!!!!!!!!!!
            ## 这里有疑惑 : MSIx BAR 需要暴露给用户态么, 理论上来说不需要
            ## 中断无非通过几种方式
            ## + eventfd 传递给用户态
            ## + eventfd 传递给irqfd
            ## + irqfd 绑定 中断路由表，从而[eventfd, irqfd]作为生产消费的抽象层,
            ##   直接配置为posted interrupt, 所以都不需要用户态来配置MSIx
            ## !!!!!!!!!!!!!
            |=> msix_table->bar_index, offset, size
        ## nb_maps == region number
        |=> for (i = 0; i < vfio_res->nb_maps; i++) 
            |=> pci_vfio_get_region_info(vfio_dev_fd, &reg, i);
            ## 判断该bar是否是ioport bar，判断过程比较直接，读取config space,
            ## 获取bar base address的flag bit，看其是 ioport, 还是mmio
            |=> ret = pci_vfio_is_ioport_bar(dev, vfio_dev_fd, i)
            |=> if ret == true:
                ==> continue
            ## 如果bar region 是mmio, 并且不支持mmap, 则continue(不能访问)
            |=> if ((reg->flags & VFIO_REGION_INFO_FLAG_MMAP) == 0)
                => continue
            ## 准备mmap这个region
            ### 查看是否有SPARSE_MMAP这个feature
            ### 也就是可以将某个region 分割，映射一部分
            |=> hdr = pci_vfio_info_cap(reg, VFIO_REGION_INFO_CAP_SPARSE_MMAP)
            |=> if true:
                |=> pci_vfio_sparse_mmap_bar
            --> else
                ## 映射整个region
                |=> pci_vfio_mmap_bar
            |=> pci_rte_vfio_setup_device
                |=> pci_vfio_setup_interrupts
                    ## 获取中断类型
                    ## !!!!!!
                    ## 需要看在哪里赋
                    ## 值的
                    ## !!!!!!
                    |=> intr_mode = rte_eal_vfio_intr_mode();
                    |=> switch(intr_mode)
                        |-> case case RTE_INTR_MODE_MSIX:
                            |-> intr_idx = VFIO_PCI_MSIX_IRQ_INDEX;
                        |-> other
                            |-> xxx
                    |=> for (i = VFIO_PCI_MSIX_IRQ_INDEX; i >= 0; i--)
                        ## 这里不考虑intr_mode 是 RTE_INTR_MODE_NONE的情况, 这里挑选出
                        ## 想要的intr_mode
                        |=> if (intr_mode != RTE_INTR_MODE_NONE && i != intr_idx)
                            |=> continue
                        ## 调取ioctl获取irq_info
                        |=> ret = ioctl(vfio_dev_fd, VFIO_DEVICE_GET_IRQ_INFO, &irq);
                        |=> if (irq.flags & VFIO_IRQ_INFO_EVENTFD) == 0
                               && if intr_mode != RTE_INTR_MODE_NONE:
                            ## 也就是说，必须支持VFIO_IRQ_INFO_EVENTFD
                            |=> return -1
                        |=> fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
                        |=> if (rte_intr_fd_set(dev->intr_handle, fd))
                        ## 设置dev->intr_handle->type 为相应的type
                        |=> rte_intr_type_set()
                |=> pci_vfio_enable_bus_memory
                ## 这里先enable req
                |=> rte_pci_set_bus_master
                ## reset device
                |=> ioctl(vfio_dev_fd, VFIO_DEVICE_RESET)
            |=> pci_vfio_enable_notifier  ## 待展开
                ## 和 dev->intr_handle 逻辑一样
                |=> fd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
                |=> rte_intr_fd_set(dev->vfio_req_intr_handle, fd)
                |=> rte_intr_type_set(dev->vfio_req_intr_handle,
                         RTE_INTR_HANDLE_VFIO_REQ)
                |=> rte_intr_dev_fd_set(dev->vfio_req_intr_handle,
                         vfio_dev_fd)
                ## 不展开, 将callback和notify绑定
                |=> rte_intr_callback_register(dev->vfio_req_intr_handle,
                         pci_vfio_req_handler,
                         (void *)&dev->device);
                |=> rte_intr_enable(dev->vfio_req_intr_handle)
                    |=> vfio_enable_req(intr_handle)
                        |=> 赋值相关irq_set成员
                            ## 赋值
                            --> irq_set->flags = VFIO_IRQ_SET_DATA_EVENTFD |
                                                  VFIO_IRQ_SET_ACTION_TRIGGER;
                            --> irq_set->index = VFIO_PCI_REQ_IRQ_INDEX;
                            --> irq_set->start = 0;
                            --> fd_ptr = (int *) &irq_set->data;
                            --> *fd_ptr = rte_intr_fd_get(intr_handle);
                        |=> ret = ioctl(vfio_dev_fd, VFIO_DEVICE_SET_IRQS, irq_set);
--> else:
    |=> pci_vfio_map_resource_secondary()
```

## vhost_user_set_vring_call
```

```
