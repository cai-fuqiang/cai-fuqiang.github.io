## irq_domain
```sh
vfio_pci_ioctl_set_irqs
|=> vfio_pci_set_irqs_ioctl
    |=> case VFIO_PCI_MSIX_IRQ_INDEX
        |=> vfio_pci_set_msi_trigger
            |=> vfio_msi_enable
                |=> vfio_pci_memory_lock_and_enable
                    |=> pci_alloc_irq_vectors
                |=> vfio_pci_memory_lock_and_restore
            |=> vfio_msi_set_block

pci_alloc_irq_vectors
|=> pci_alloc_irq_vectors_affinity
    |=> __pci_enable_msix_range
        ## 获取 当前设备的msix的最大条目
        |=> hwsize = pci_msix_vec_count(dev)
        |=> pci_setup_msi_context
            |=> msi_setup_device_data()
                |=> struct msi_device_data * md = devres_alloc()
                ## ${sys_device_path}/msi_irqs
                |=> msi_sysfs_create_group()
                ## 初始化xarray tree
                |=> for (i = 0; i < MSI_MAX_DEVICE_IRQDOMAINS; i++)
                    --> xa_init_flags(&md->__domains[i].store, 
                              XA_FLAGS_ALLOC);
                |=> dev->msi.data = md
                |=> devres_add(dev,md)  ## 先忽略
            |=> pcim_setup_msi_release() ## 先不看
        |=> pci_setup_msix_device_domain
            |=> pci_create_device_domain(pdev, &pci_msix_template, hwsize);
                ## 给该device创建irq_domain
                ##
                ## 也就是每个pci_device
                |=> msi_create_device_irq_domain(&pdev->dev, MSI_DEFAULT_DOMAIN, tmpl,
                                                hwsize, NULL, NULL);
                    |=> pops->init_dev_msi_info(dev, parent, parent, &bundle->info)
                    |=> __msi_create_irq_domain(fwnode, &bundle->info,
                           IRQ_DOMAIN_FLAG_MSI_DEVICE, parent);
                        |=> msi_domain_update_dom_ops(info)
                        |=> irq_domain_create_hierarchy(parent, 
                               flags | IRQ_DOMAIN_FLAG_MSI, 0,
                               fwnode, &msi_domain_ops, info)
        ## in __pci_enable_msix_range
        |=> msix_capability_init()
            ## 设置ctrl，打开msix，并且设置MASKALL
            |=> pci_msix_clear_and_set_ctrl(dev, 0, PCI_MSIX_FLAGS_MASKALL |
                  PCI_MSIX_FLAGS_ENABLE)
            ## 获取table_size
            |=> tsize = msix_table_size(control);
            ## 获取msix_base
            |=> dev->msix_base = msix_map_region(dev, tsize);
            |=> ret = msix_setup_interrupts(dev, entries, nvec, affd);
            |=> pci_intx_for_msi(dev, 0);
            |=> if !pci_msi_domain_supports(dev, MSI_FLAG_NO_MASK, DENY_LEGACY)
                --> msix_mask_all(dev->msix_base, tsize);
            ## 移除 MASKALL
            |=> pci_msix_clear_and_set_ctrl(dev, PCI_MSIX_FLAGS_MASKALL, 0);

irq_domain_create_hierarchy
|=> irq_domain_instantiate(&info);
    |=> __irq_domain_instantiate(info, false, false);
        |=> __irq_domain_create()
            |=> domain = kzalloc()
            |=> irq_domain_set_name()
            |=> INIT_RADIX_TREE(&domain->revmap_tree, GFP_KERNEL)
            |=> domain->name, ops,host_data,bus_token,
                      hwirq_max, revmap_size,
            #现将root赋值为domain
            |=> domain->root = domain
        ## 赋值层级相关成员
        |=> domain->root = info->parent->root
        |=> domain->parent = info->parent
        |=> info->init(domain) ## MSIx没有
        |=> __irq_domain_publish()
            |=> debugfs_add_domain_dir()
            |=> list_add(&domain->link, 
                      &irq_domain_list);
```


```sh
msix_setup_interrupts
|=> if affd:
    --> masks = irq_create_affinity_masks(nvec, affd)
|=> msix_setup_msi_descs(dev, entries, nvec, masks)
|=> pci_msi_setup_msi_irqs(dev, nvec, PCI_CAP_ID_MSIX)
|=> msi_verify_entries(dev)
|=> msix_update_entries(dev, entries)
```
