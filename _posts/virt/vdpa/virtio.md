## cap 初始化
```
#0  0x0000555555b7afff in virtio_pci_modern_regions_init (vdev_name=<optimized out>, proxy=<optimized out>) at ../hw/virtio/virtio-pci.c:1636
#1  virtio_pci_device_plugged (d=<optimized out>, errp=0x7fffffffd0d0) at ../hw/virtio/virtio-pci.c:1804
#2  0x0000555555b77b96 in virtio_bus_device_plugged (vdev=vdev@entry=0x55555727a860, errp=errp@entry=0x7fffffffd120) at ../hw/virtio/virtio-bus.c:78
#3  0x0000555555caf66e in virtio_device_realize (dev=0x55555727a860, errp=0x7fffffffd180) at ../hw/virtio/virtio.c:3719
#4  0x0000555555d5bb3b in device_set_realized (obj=<optimized out>, value=<optimized out>, errp=0x7fffffffd320) at ../hw/core/qdev.c:531
#5  0x0000555555d607e8 in property_set_bool (obj=0x55555727a860, v=<optimized out>, name=<optimized out>, opaque=0x5555564f34e0, errp=0x7fffffffd320) at ../qom/object.c:2272
#6  0x0000555555d63943 in object_property_set (obj=obj@entry=0x55555727a860, name=name@entry=0x555555ebddf8 "realized", v=v@entry=0x555557284df0, errp=errp@entry=0x7fffffffd320) at ../qom/object.c:1407
#7  0x0000555555d66c6f in object_property_set_qobject (obj=obj@entry=0x55555727a860, name=name@entry=0x555555ebddf8 "realized", value=value@entry=0x555557284d30, errp=errp@entry=0x7fffffffd320) at ../qom/qom-qobject.c:28
#8  0x0000555555d63f44 in object_property_set_bool (obj=0x55555727a860, name=0x555555ebddf8 "realized", value=<optimized out>, errp=0x7fffffffd320) at ../qom/object.c:1476
#9  0x0000555555aee122 in pci_qdev_realize (qdev=<optimized out>, errp=<optimized out>) at ../hw/pci/pci.c:2146
#10 0x0000555555d5bb3b in device_set_realized (obj=<optimized out>, value=<optimized out>, errp=0x7fffffffd560) at ../hw/core/qdev.c:531
```


## ioeventfd_add
```
#0  kvm_mem_ioeventfd_add (listener=0x555556731180, section=0x7ffee73fcf00, match_data=false, data=0, e=0x7ffff40a10a4) at ../accel/kvm/kvm-all.c:1603
#1  0x0000555555c3328f in address_space_add_del_ioeventfds (fds_old_nb=8, fds_old=0x7ffed837e5f0, fds_new_nb=<optimized out>, fds_new=0x7ffed85647f0, as=0x5555564327a0 <address_space_memory>) at ../softmmu/memory.c:793
#2  address_space_update_ioeventfds (as=0x5555564327a0 <address_space_memory>) at ../softmmu/memory.c:854
#3  0x0000555555c36808 in memory_region_transaction_commit () at ../softmmu/memory.c:1111
#4  memory_region_transaction_commit () at ../softmmu/memory.c:1088
#5  0x0000555555b78a84 in virtio_pci_ioeventfd_assign (d=0x555557453a90, notifier=0x7ffff40a10a4, n=0, assign=<optimized out>) at ../hw/virtio/virtio-pci.c:344
#6  0x0000555555b78411 in virtio_bus_set_host_notifier (bus=0x55555745bca0, n=n@entry=0, assign=assign@entry=true) at ../hw/virtio/virtio-bus.c:287
#7  0x0000555555cb9c67 in vhost_dev_enable_notifiers (hdev=hdev@entry=0x5555564ef4d0, vdev=vdev@entry=0x55555745bd20) at ../hw/virtio/vhost.c:1532
#8  0x0000555555abf4fe in vhost_net_start_one (dev=0x55555745bd20, net=0x5555564ef4d0) at ../hw/net/vhost_net.c:315
#9  vhost_net_start (dev=dev@entry=0x55555745bd20, ncs=0x5555574a1580, data_queue_pairs=data_queue_pairs@entry=1, cvq=cvq@entry=0) at ../hw/net/vhost_net.c:442
#10 0x0000555555c7b35b in virtio_net_vhost_status (status=<optimized out>, n=0x55555745bd20) at ../hw/net/virtio-net.c:289
#11 virtio_net_set_status (vdev=0x55555745bd20, status=<optimized out>) at ../hw/net/virtio-net.c:370
#12 0x0000555555cb0f9b in virtio_set_status (vdev=vdev@entry=0x55555745bd20, val=val@entry=15 '\017') at ../hw/virtio/virtio.c:1956
#13 0x0000555555b79fef in virtio_pci_common_write (opaque=0x555557453a90, addr=<optimized out>, val=<optimized out>, size=<optimized out>) at ../hw/virtio/virtio-pci.c:1385
#14 0x0000555555c35130 in memory_region_write_accessor (mr=0x555557454500, addr=20, value=<optimized out>, size=1, shift=<optimized out>, mask=<optimized out>, attrs=...) at ../softmmu/memory.c:492
#15 0x0000555555c30d0f in access_with_adjusted_size
    (addr=addr@entry=20, value=value@entry=0x7ffee73fd428, size=size@entry=1, access_size_min=<optimized out>, access_size_max=<optimized out>, access_fn=0x555555c350b0 <memory_region_write_accessor>, mr=<optimized out>, attrs=...) at ../softmmu/memory.c:554
#16 0x0000555555c344e1 in memory_region_dispatch_write (mr=mr@entry=0x555557454500, addr=addr@entry=20, data=<optimized out>, op=<optimized out>, attrs=attrs@entry=...) at ../softmmu/memory.c:1511
#17 0x0000555555c23aac in flatview_write_continue (fv=fv@entry=0x7ffed8678680, addr=addr@entry=61607010910228, attrs=..., attrs@entry=..., ptr=ptr@entry=0x7ffff43c1028, len=len@entry=1, addr1=<optimized out>, l=<optimized out>, mr=0x555557454500)
    at ../softmmu/physmem.c:2832
#18 0x0000555555c23d23 in flatview_write (fv=0x7ffed8678680, addr=61607010910228, attrs=..., buf=0x7ffff43c1028, len=1) at ../softmmu/physmem.c:2874
#19 0x0000555555c27634 in address_space_write (len=<optimized out>, buf=0x7ffff43c1028, attrs=..., addr=<optimized out>, as=<optimized out>) at ../softmmu/physmem.c:2970
#20 address_space_rw (as=<optimized out>, addr=<optimized out>, attrs=..., attrs@entry=..., buf=buf@entry=0x7ffff43c1028, len=<optimized out>, is_write=<optimized out>) at ../softmmu/physmem.c:2980
#21 0x0000555555d35a66 in kvm_cpu_exec (cpu=cpu@entry=0x5555567404f0) at ../accel/kvm/kvm-all.c:2944
#22 0x0000555555d36e7d in kvm_vcpu_thread_fn (arg=arg@entry=0x5555567404f0) at ../accel/kvm/kvm-accel-ops.c:49
#23 0x0000555555e8b598 in qemu_thread_start (args=0x555556750d30) at ../util/qemu-thread-posix.c:556
```
