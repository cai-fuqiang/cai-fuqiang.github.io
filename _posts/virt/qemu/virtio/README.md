# host notify
```sh
virtio_pci_common_write
=> case VIRTIO_PCI_COMMON_STATUS
    => if val & VIRTIO_CONFIG_S_DRIVER_OK
       => virtio_pci_start_ioeventfd
          => virtio_bus_start_ioeventfd
             => vdc->start_ioeventfd(vdev)
                == virtio_blk_start_ioeventfd



```

* virtio_blk_start_ioeventfd
```sh
virtio_blk_start_ioeventfd
=> k->set_guest_notifiers()
=> memory_region_transaction_begin()
=> foreach vq
   => virtio_bus_set_host_notifier
      => event_notifier_init()
      => k->ioeventfd_assign()
         == virtio_pci_ioeventfd_assign()
            => MemoryRegion *modern_mr = &proxy->notify.mr;
            => hwaddr modern_addr = virtio_pci_queue_mem_mult(proxy) *
                                    virtio_get_queue_index(vq);
            => memory_region_add_eventfd()
               => memory_region_transaction_begin();
               => realloc mr->ioeventfds[]  and insert new
               => memory_region_transaction_commit()
      => virtio_queue_set_host_notifier_enabled()
         => vq->host_notifier_enabled = enabled
=> memory_region_transaction_commit()
=> blk_set_aio_context()
=> virtio_blk_ioeventfd_attach()
   => foreach vq
      => virtio_queue_aio_attach_host_notifier()
         => aio_set_event_notifier()
            => callbak {
                 virtio_queue_host_notifier_read
                 virtio_queue_host_notifier_aio_poll
                 virtio_queue_host_notifier_aio_poll_ready
               }
         => aio_set_event_notifier_poll()
            => callbak {
                 virtio_queue_host_notifier_aio_poll_begin
                 virtio_queue_host_notifier_aio_poll_end
               }
         # kick
         => event_notifier_set(&vq->host_notifier)
```

## 在cpu 0 上触发IO

CPU 0 堆栈 -- write host notify
```
comm(CPU 0/KVM)
kstack
 (
        ioeventfd_write+1
        __kvm_io_bus_write+136
        kvm_io_bus_write+83
        handle_ept_misconfig+77
        vcpu_enter_guest+1885
        vcpu_run+74
        kvm_arch_vcpu_ioctl_run+139
        kvm_vcpu_ioctl+596
        __se_sys_ioctl+133
        do_syscall_64+64
        entry_SYSCALL_64_after_hwframe+97
)
```
`IO iothread0` write guest notify

```
comm (IO iothread0)
ustack
 (
        __write+79
        virtio_notify_irqfd+189
        virtio_blk_data_plane_notify+104
        virtio_blk_req_complete+224
        virtio_blk_rw_complete+324
        blk_aio_complete+54
        blk_aio_read_entry+169
        coroutine_trampoline+212
        0x7faf90973050
        0x7fab435fd130
)
```

## 传统老掉牙方式
```
pci_host_data_le_ops.write
pci_host_data_write
pci_data_write
pci_host_config_write_common
virtio_write_config
virtio_address_space_write
memory_region_dispatch_write
memory_region_dispatch_write_eventfds
```
