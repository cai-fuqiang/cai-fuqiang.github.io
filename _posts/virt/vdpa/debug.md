## 打断点

### NOTIFY
qemu
```
b vhost_user_set_vring_call
b vhost_user_set_vring_kick
```

dpdk
```
b vhost_user_set_vring_call
b vhost_user_set_vring_kick
```
一. qemu
```
(gdb) bt
#0  vhost_user_set_vring_call (dev=0x5555564ef4d0, file=0x7fffffffb3f0) at ../hw/virtio/vhost-user.c:1300
#1  0x0000555555cb9541 in vhost_virtqueue_init (n=<optimized out>, vq=0x5555564ef750, dev=0x5555564ef4d0) at ../hw/virtio/vhost.c:1325
#2  vhost_dev_init (hdev=hdev@entry=0x5555564ef4d0, opaque=<optimized out>, backend_type=<optimized out>, busyloop_timeout=0, errp=errp@entry=0x7fffffffb460) at ../hw/virtio/vhost.c:1391
#3  0x0000555555abedcc in vhost_net_init (options=options@entry=0x7fffffffb500) at ../hw/net/vhost_net.c:259
#4  0x00005555559dfcf3 in vhost_user_start (be=0x55555670dc90, ncs=0x7fffffffb520, queues=1) at ../net/vhost-user.c:103
#5  net_vhost_user_event (opaque=0x555556710510, event=<optimized out>) at ../net/vhost-user.c:301
#6  0x0000555555e0f855 in qemu_chr_fe_set_handlers
    (b=b@entry=0x555556706658, fd_can_read=fd_can_read@entry=0x0, fd_read=fd_read@entry=0x0, fd_event=fd_event@entry=0x5555559dfad0 <net_vhost_user_event>, be_change=be_change@entry=0x0, opaque=<optimized out>, context=0x0, set_open=true)
    at ../chardev/char-fe.c:304
#7  0x00005555559e039a in net_vhost_user_init (device=0x555555ec2727 "vhost_user", queues=<optimized out>, chr=<optimized out>, name=0x55555672ed30 "net1", peer=0x0) at ../net/vhost-user.c:377
#8  net_init_vhost_user (netdev=<optimized out>, name=0x55555672ed30 "net1", peer=0x0, errp=<optimized out>) at ../net/vhost-user.c:453
#9  0x00005555559d787a in net_client_init1 (netdev=0x555556706320, is_netdev=is_netdev@entry=true, errp=errp@entry=0x555556451690 <error_fatal>) at ../net/net.c:1064
#10 0x00005555559d7b99 in net_client_init (opts=<optimized out>, is_netdev=<optimized out>, errp=0x555556451690 <error_fatal>) at ../net/net.c:1162
#11 0x0000555555e93fa1 in qemu_opts_foreach (list=<optimized out>, func=func@entry=0x5555559d9530 <net_init_netdev>, opaque=opaque@entry=0x0, errp=errp@entry=0x555556451690 <error_fatal>) at ../util/qemu-option.c:1135
#12 0x00005555559d9ff2 in net_init_clients (errp=errp@entry=0x555556451690 <error_fatal>) at ../net/net.c:1567
#13 0x0000555555c429dd in qemu_create_late_backends () at ../softmmu/vl.c:2000
#14 qemu_init (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>) at ../softmmu/vl.c:3763
#15 0x000055555593bfb9 in main (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>) at ../softmmu/main.c:50
```

二. dpdk
```
#0  vhost_user_set_vring_call (pdev=0x7f81e4f2bf30, ctx=0x7f81e4f2bc80, main_fd=78) at ../lib/vhost/vhost_user.c:1896
#1  0x00000000035737c2 in vhost_user_msg_handler (vid=0, fd=78) at ../lib/vhost/vhost_user.c:3210
#2  0x000000000351ebcf in vhost_user_read_cb (connfd=78, dat=0x7f8194002ff0, close=0x7f81e4f2f014) at ../lib/vhost/socket.c:312
#3  0x000000000351cd86 in fdset_event_dispatch (arg=0x22005aa680) at ../lib/vhost/fd_man.c:370
#4  0x0000000003833c44 in control_thread_start (arg=0x6725030) at ../lib/eal/common/eal_common_thread.c:282
```

三. qemu
```
(gdb) bt
#0  vhost_user_set_vring_kick (dev=0x5555564ef4d0, file=0x7ffee7dfe088) at ../hw/virtio/vhost-user.c:1294
#1  0x0000555555cbaffe in vhost_virtqueue_start (idx=0, vq=<optimized out>, vdev=0x55555745bc00, dev=0x5555564ef4d0) at ../hw/virtio/vhost.c:1181
#2  vhost_dev_start (hdev=hdev@entry=0x5555564ef4d0, vdev=vdev@entry=0x55555745bc00) at ../hw/virtio/vhost.c:1820
#3  0x0000555555abf511 in vhost_net_start_one (dev=0x55555745bc00, net=0x5555564ef4d0) at ../hw/net/vhost_net.c:320
#4  vhost_net_start (dev=dev@entry=0x55555745bc00, ncs=0x5555574a1270, data_queue_pairs=data_queue_pairs@entry=1, cvq=cvq@entry=0) at ../hw/net/vhost_net.c:442
#5  0x0000555555c7b35b in virtio_net_vhost_status (status=<optimized out>, n=0x55555745bc00) at ../hw/net/virtio-net.c:289
#6  virtio_net_set_status (vdev=0x55555745bc00, status=<optimized out>) at ../hw/net/virtio-net.c:370
#7  0x0000555555cb0f9b in virtio_set_status (vdev=vdev@entry=0x55555745bc00, val=val@entry=15 '\017') at ../hw/virtio/virtio.c:1956
#8  0x0000555555b79fef in virtio_pci_common_write (opaque=0x555557453970, addr=<optimized out>, val=<optimized out>, size=<optimized out>) at ../hw/virtio/virtio-pci.c:1385
#9  0x0000555555c35130 in memory_region_write_accessor (mr=0x5555574543e0, addr=20, value=<optimized out>, size=1, shift=<optimized out>, mask=<optimized out>, attrs=...) at ../softmmu/memory.c:492
#10 0x0000555555c30d0f in access_with_adjusted_size
    (addr=addr@entry=20, value=value@entry=0x7ffee7dfe428, size=size@entry=1, access_size_min=<optimized out>, access_size_max=<optimized out>, access_fn=0x555555c350b0 <memory_region_write_accessor>, mr=<optimized out>, attrs=...)
    at ../softmmu/memory.c:554
#11 0x0000555555c344e1 in memory_region_dispatch_write (mr=mr@entry=0x5555574543e0, addr=addr@entry=20, data=<optimized out>, op=<optimized out>, attrs=attrs@entry=...) at ../softmmu/memory.c:1511
#12 0x0000555555c23aac in flatview_write_continue (fv=fv@entry=0x7ffee06d90e0, addr=addr@entry=61607010910228, attrs=..., attrs@entry=..., ptr=ptr@entry=0x7ffff43c1028, len=len@entry=1, addr1=<optimized out>, l=<optimized out>, mr=0x5555574543e0)
    at ../softmmu/physmem.c:2832
#13 0x0000555555c23d23 in flatview_write (fv=0x7ffee06d90e0, addr=61607010910228, attrs=..., buf=0x7ffff43c1028, len=1) at ../softmmu/physmem.c:2874
#14 0x0000555555c27634 in address_space_write (len=<optimized out>, buf=0x7ffff43c1028, attrs=..., addr=<optimized out>, as=<optimized out>) at ../softmmu/physmem.c:2970
#15 address_space_rw (as=<optimized out>, addr=<optimized out>, attrs=..., attrs@entry=..., buf=buf@entry=0x7ffff43c1028, len=<optimized out>, is_write=<optimized out>) at ../softmmu/physmem.c:2980
#16 0x0000555555d35a66 in kvm_cpu_exec (cpu=cpu@entry=0x5555567401c0) at ../accel/kvm/kvm-all.c:2944
#17 0x0000555555d36e7d in kvm_vcpu_thread_fn (arg=arg@entry=0x5555567401c0) at ../accel/kvm/kvm-accel-ops.c:49
#18 0x0000555555e8b598 in qemu_thread_start (args=0x555556750a00) at ../util/qemu-thread-posix.c:556
```

四. dpdk
```
(gdb) bt
#0  vhost_user_set_vring_kick (pdev=0x7f81e4f2bf30, ctx=0x7f81e4f2bc80, main_fd=78) at ../lib/vhost/vhost_user.c:2148
#1  0x00000000035737c2 in vhost_user_msg_handler (vid=0, fd=78) at ../lib/vhost/vhost_user.c:3210
#2  0x000000000351ebcf in vhost_user_read_cb (connfd=78, dat=0x7f8194002ff0, close=0x7f81e4f2f014) at ../lib/vhost/socket.c:312
#3  0x000000000351cd86 in fdset_event_dispatch (arg=0x22005aa680) at ../lib/vhost/fd_man.c:370
#4  0x0000000003833c44 in control_thread_start (arg=0x6725030) at ../lib/eal/common/eal_common_thread.c:282
#5  0x00007f81ef0abeb6 in ?? () from /usr/lib64/libc.so.6
#6  0x00007f81ef12b02c in ?? () from /usr/lib64/libc.so.6
```

五. dpdk
```
#0  vhost_user_set_vring_call (dev=0x5555564ef4d0, file=0x7ffee7dfe010) at ../hw/virtio/vhost-user.c:1300
#1  0x0000555555cba1a6 in vhost_virtqueue_mask (hdev=hdev@entry=0x5555564ef4d0, vdev=vdev@entry=0x55555745bc00, n=n@entry=1, mask=mask@entry=false) at ../hw/virtio/vhost.c:1609
#2  0x0000555555cbb1ff in vhost_virtqueue_start (idx=1, vq=<optimized out>, vdev=0x55555745bc00, dev=0x5555564ef4d0) at ../hw/virtio/vhost.c:1196
#3  vhost_dev_start (hdev=hdev@entry=0x5555564ef4d0, vdev=vdev@entry=0x55555745bc00) at ../hw/virtio/vhost.c:1820
#4  0x0000555555abf511 in vhost_net_start_one (dev=0x55555745bc00, net=0x5555564ef4d0) at ../hw/net/vhost_net.c:320
#5  vhost_net_start (dev=dev@entry=0x55555745bc00, ncs=0x5555574a1270, data_queue_pairs=data_queue_pairs@entry=1, cvq=cvq@entry=0) at ../hw/net/vhost_net.c:442
#6  0x0000555555c7b35b in virtio_net_vhost_status (status=<optimized out>, n=0x55555745bc00) at ../hw/net/virtio-net.c:289
#7  virtio_net_set_status (vdev=0x55555745bc00, status=<optimized out>) at ../hw/net/virtio-net.c:370
#8  0x0000555555cb0f9b in virtio_set_status (vdev=vdev@entry=0x55555745bc00, val=val@entry=15 '\017') at ../hw/virtio/virtio.c:1956
#9  0x0000555555b79fef in virtio_pci_common_write (opaque=0x555557453970, addr=<optimized out>, val=<optimized out>, size=<optimized out>) at ../hw/virtio/virtio-pci.c:1385
#10 0x0000555555c35130 in memory_region_write_accessor (mr=0x5555574543e0, addr=20, value=<optimized out>, size=1, shift=<optimized out>, mask=<optimized out>, attrs=...) at ../softmmu/memory.c:492
#11 0x0000555555c30d0f in access_with_adjusted_size
    (addr=addr@entry=20, value=value@entry=0x7ffee7dfe428, size=size@entry=1, access_size_min=<optimized out>, access_size_max=<optimized out>, access_fn=0x555555c350b0 <memory_region_write_accessor>, mr=<optimized out>, attrs=...)
    at ../softmmu/memory.c:554
#12 0x0000555555c344e1 in memory_region_dispatch_write (mr=mr@entry=0x5555574543e0, addr=addr@entry=20, data=<optimized out>, op=<optimized out>, attrs=attrs@entry=...) at ../softmmu/memory.c:1511
#13 0x0000555555c23aac in flatview_write_continue (fv=fv@entry=0x7ffee06d90e0, addr=addr@entry=61607010910228, attrs=..., attrs@entry=..., ptr=ptr@entry=0x7ffff43c1028, len=len@entry=1, addr1=<optimized out>, l=<optimized out>, mr=0x5555574543e0)
    at ../softmmu/physmem.c:2832
#14 0x0000555555c23d23 in flatview_write (fv=0x7ffee06d90e0, addr=61607010910228, attrs=..., buf=0x7ffff43c1028, len=1) at ../softmmu/physmem.c:2874
#15 0x0000555555c27634 in address_space_write (len=<optimized out>, buf=0x7ffff43c1028, attrs=..., addr=<optimized out>, as=<optimized out>) at ../softmmu/physmem.c:2970
#16 address_space_rw (as=<optimized out>, addr=<optimized out>, attrs=..., attrs@entry=..., buf=buf@entry=0x7ffff43c1028, len=<optimized out>, is_write=<optimized out>) at ../softmmu/physmem.c:2980
#17 0x0000555555d35a66 in kvm_cpu_exec (cpu=cpu@entry=0x5555567401c0) at ../accel/kvm/kvm-all.c:2944
#18 0x0000555555d36e7d in kvm_vcpu_thread_fn (arg=arg@entry=0x5555567401c0) at ../accel/kvm/kvm-accel-ops.c:49
#19 0x0000555555e8b598 in qemu_thread_start (args=0x555556750a00) at ../util/qemu-thread-posix.c:556
```
