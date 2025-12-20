## vhost message types front-end <sup>1<sup>

* FEATURE
  + VHOST_USER_GET_FEATURES

    从底层 vhost 实现中获取特性位掩码。特性位 VHOST_USER_F_PROTOCOL_FEATURES 表示后
    端支持 VHOST_USER_GET_PROTOCOL_FEATURES 和 VHOST_USER_SET_PROTOCOL_FEATURES。

  * VHOST_USER_SET_FEATURES

    使能底层实现的一些feature.(例如vhost_log_global_start()会使能
    VHOST_F_LOG_ALL feature )

  * VHOST_USER_GET_PROTOCOL_FEATURES

    获取protocol feature, 这相当于一个子feature，仅和协议扩展相关。

  * VHOST_USER_SET_PROTOCOL_FEATURES

    使能某些 protocol features.
* OWNER
  * VHOST_USER_SET_OWNER

    在新建立链接的时候，前端向后端发送，表示发送方已经标记为
    拥有该会话的前端，此时，后端可以认为会话已经开始。

    很类似于tcp三次握手中的(seq->ack->ack)中的第二次ack, server
    端在收到client端发送的ack后，认为该连接已经建立，为其该连接
    分配相关资源(新版本kernel是这样做的)
  * VHOST_USER_RESET_OWNER

    目前已经弃用，之前用其来disabling all ring(仍想保持会话建立), 但是后端会将其解
    释 为还要 discard connect state(类似于close), 建议后端直接忽略次消息，要么仅用
    其来disable all rings.
* MEMORY REGION
  + VHOST_USER_SET_MEM_TABLE

    将虚拟机内存信息传递到后端, 让后端可以访问这片内存，同时，需要给vhost 这片内存
    和GPA的映射关系.

    主要传递的信息有:
    + fds[]
    + VhostUserMemoryRegion[]
      + guest_phys_addr
      + memory_size
      + userspace_addr
      + mmap_offset

    这里有两个数组, 两个数组中相同index的数组成员表示一个内存区域, 其中fds[]
    存放的是文件描述符, vhost front-end 通过其建立好的socket通道，通过socket的
    `Ancillary messages`机制<sup>2</sup>将文件描述符传递到back-end(). 

    另外, `VhostUserMemoryRegion`会增加一些描述信息, 其主要的目的是将guest
    memory region(`[guest_phy_addr(gpa), gpa + memory_size]`)和该文件的region 
    (`[mmap_offset, mmap_offset + memory_size]`)的绑定关系get到, 然后调用vfio
    相关接口配置iommu.

    ![vhost_user_client_and_guest_mr](./pic/vhost_user_client_and_guest_mr.svg)
  + VHOST_USER_GET_MAX_MEM_SLOTS
  + VHOST_USER_ADD_MEM_REG
  + VHOST_USER_REM_MEM_REG

* LOG
  * VHOST_USER_SET_LOG_BASE
  * VHOST_USER_SET_LOG_FD
* VRING
  + set
    * VHOST_USER_SET_VRING_NUM
    * VHOST_USER_SET_VRING_ADDR
    * VHOST_USER_SET_VRING_BASE
    * VHOST_USER_SET_VRING_KICK
    * VHOST_USER_SET_VRING_ERR
    * VHOST_USER_SET_VRING_ENABLE
    * VHOST_USER_SET_VRING_CALL
    * VHOST_USER_SET_VRING_ENDIAN

    这些一般会在guest modify common_cap.dev_status为<sup>3.1</sup>
    ```
    DRIVER_OK (4) Indicates that the driver is set up and ready to drive 
    the device.
    ```
    表示guest driver 已经最好准备驱动设备了，设备可以工作了.
  + get
    * VHOST_USER_GET_VRING_BASE
    * VHOST_USER_GET_QUEUE_NUM
* migration postcopy
  + VHOST_USER_POSTCOPY_ADVISE
  + VHOST_USER_POSTCOPY_LISTEN
  + VHOST_USER_POSTCOPY_END
* RESET
  + VHOST_USER_RESET_DEVICE
* OTHER
  + VHOST_USER_SEND_RARP
  + VHOST_USER_NET_SET_MTU
  + VHOST_USER_SET_BACKEND_REQ_FD
  + VHOST_USER_IOTLB_MSG
  + VHOST_USER_GET_CONFIG
  + VHOST_USER_SET_CONFIG
  + VHOST_USER_CLOSE_CRYPTO_SESSION
  + VHOST_USER_SET_INFLIGHT_FD
  + VHOST_USER_GPU_SET_SOCKET
  + VHOST_USER_SET_STATUS
  + VHOST_USER_GET_STATUS
  + VHOST_USER_GET_SHARED_OBJECT
  + VHOST_USER_SET_DEVICE_STATE_FD
  + VHOST_USER_CHECK_DEVICE_STATE


## 堆栈
```sh
|=> net_vhost_user_event
    |=> vhost_user_start


|=> vhost_user_backend_init
    ## VHOST_USER_GET_FEATURES
    |=> vhost_user_get_features()
    ## VHOST_USER_GET_PROTOCOL_FEATURES
    |=> err = vhost_user_get_u64(dev,
         VHOST_USER_GET_PROTOCOL_FEATURES,
         &protocol_features);
    ## VHOST_USER_SET_PROTOCOL_FEATURES
    |=> vhost_user_set_protocol_features()

    ## VHOST_USER_GET_QUEUE_NUM
    |=> err = vhost_user_get_u64(dev,
            VHOST_USER_GET_QUEUE_NUM,
            &dev->max_queues);

    ## VHOST_USER_SET_BACKEND_REQ_FD
    |=> vhost_setup_backend_channel

|=> vhost_dev_start()
    ## LOG
    |=> vhost_dev_set_features()
|=> vhost_commit()
    |=> dev->vhost_ops->vhost_set_mem_table()


vhost_virtqueue_start
|=> vhost_set_vring_num()
|=> vhost_set_vring_base()
|=> vhost_virtqueue_set_addr()
|=> vhost_set_vring_kick()
|=> if !vdev->use_guest_notifier_mask
    ==> vhost_virtqueue_mask()

## 这个感觉不太对, 感觉像是把notify取消了, 回头主要研究下
## guest_notify
|=> if k->query_guest_notifiers &&
         k->query_guest_notifiers(qbus->parent) &&
         virtio_queue_vector(vdev, idx) == VIRTIO_NO_VECTOR
    ==> file.fd = -1
    ==> vhost_set_vring_call()
```

## 附录

### vhost_virtqueue_start() stack
```
#0  vhost_virtqueue_start (idx=0, vq=<optimized out>, vdev=0x55555745bc20, dev=0x5555564ef4d0) at ../hw/virtio/vhost.c:1136
#1  vhost_dev_start (hdev=hdev@entry=0x5555564ef4d0, vdev=vdev@entry=0x55555745bc20) at ../hw/virtio/vhost.c:1820
#2  0x0000555555abf511 in vhost_net_start_one (dev=0x55555745bc20, net=0x5555564ef4d0) at ../hw/net/vhost_net.c:320
#3  vhost_net_start (dev=dev@entry=0x55555745bc20, ncs=0x5555574a1290, data_queue_pairs=data_queue_pairs@entry=1, cvq=cvq@entry=0)
    at ../hw/net/vhost_net.c:442
#4  0x0000555555c7b35b in virtio_net_vhost_status (status=<optimized out>, n=0x55555745bc20) at ../hw/net/virtio-net.c:289
#5  virtio_net_set_status (vdev=0x55555745bc20, status=<optimized out>) at ../hw/net/virtio-net.c:370
#6  0x0000555555cb0f9b in virtio_set_status (vdev=vdev@entry=0x55555745bc20, val=val@entry=15 '\017') at ../hw/virtio/virtio.c:1956
#7  0x0000555555b79fef in virtio_pci_common_write (opaque=0x555557453990, addr=<optimized out>, val=<optimized out>, size=<optimized out>)
    at ../hw/virtio/virtio-pci.c:1385
#8  0x0000555555c35130 in memory_region_write_accessor
    (mr=0x555557454400, addr=20, value=<optimized out>, size=1, shift=<optimized out>, mask=<optimized out>, attrs=...)
    at ../softmmu/memory.c:492
#9  0x0000555555c30d0f in access_with_adjusted_size
    (addr=addr@entry=20, value=value@entry=0x7ffee73fd428, size=size@entry=1, access_size_min=<optimized out>, access_size_max=<optimized out>
, access_fn=0x555555c350b0 <memory_region_write_accessor>, mr=<optimized out>, attrs=...) at ../softmmu/memory.c:554
#10 0x0000555555c344e1 in memory_region_dispatch_write
    (mr=mr@entry=0x555557454400, addr=addr@entry=20, data=<optimized out>, op=<optimized out>, attrs=attrs@entry=...)
    at ../softmmu/memory.c:1511
#11 0x0000555555c23aac in flatview_write_continue (fv=fv@entry=0x7ffed8587d90, addr=addr@entry=61607010910228, attrs=...,
    attrs@entry=..., ptr=ptr@entry=0x7ffff43c1028, len=len@entry=1, addr1=<optimized out>, l=<optimized out>, mr=0x555557454400)
    at ../softmmu/physmem.c:2832
#12 0x0000555555c23d23 in flatview_write (fv=0x7ffed8587d90, addr=61607010910228, attrs=..., buf=0x7ffff43c1028, len=1)
    at ../softmmu/physmem.c:2874
#13 0x0000555555c27634 in address_space_write (len=<optimized out>, buf=0x7ffff43c1028, attrs=..., addr=<optimized out>, as=<optimized out>)
    at ../softmmu/physmem.c:2970
#14 address_space_rw (as=<optimized out>, addr=<optimized out>, attrs=...,
    attrs@entry=..., buf=buf@entry=0x7ffff43c1028, len=<optimized out>, is_write=<optimized out>) at ../softmmu/physmem.c:2980
#15 0x0000555555d35a66 in kvm_cpu_exec (cpu=cpu@entry=0x5555567403f0) at ../accel/kvm/kvm-all.c:2944
#16 0x0000555555d36e7d in kvm_vcpu_thread_fn (arg=arg@entry=0x5555567403f0) at ../accel/kvm/kvm-accel-ops.c:49
#17 0x0000555555e8b598 in qemu_thread_start (args=0x555556750c30) at ../util/qemu-thread-posix.c:556
```

### vhost_user_set_vring_call stack
```
(gdb)
#0  vhost_user_set_vring_call (dev=0x5555564ef4d0, file=0x7fffffffb3f0) at ../hw/virtio/vhost-user.c:1300
#1  0x0000555555cb9541 in vhost_virtqueue_init (n=<optimized out>, vq=0x5555564ef750, dev=0x5555564ef4d0) at ../hw/virtio/vhost.c:1325
#2  vhost_dev_init (hdev=hdev@entry=0x5555564ef4d0, opaque=<optimized out>, backend_type=<optimized out>, busyloop_timeout=0, errp=errp@entry=0x7fffffffb460) at ../hw/virtio/vhost.c:1391
#3  0x0000555555abedcc in vhost_net_init (options=options@entry=0x7fffffffb500) at ../hw/net/vhost_net.c:259
#4  0x00005555559dfcf3 in vhost_user_start (be=0x55555670dc90, ncs=0x7fffffffb520, queues=1) at ../net/vhost-user.c:103
#5  net_vhost_user_event (opaque=0x555556710510, event=<optimized out>) at ../net/vhost-user.c:301
#6  0x0000555555e0f855 in qemu_chr_fe_set_handlers
    (b=b@entry=0x555556706658, fd_can_read=fd_can_read@entry=0x0, fd_read=fd_read@entry=0x0, fd_event=fd_event@entry=0x5555559dfad0 <net_vhost_user_event>, be_change=be_change@entry=0x0, opaque=<optimized out>, context=0x0, set_open=true) at ../chardev/char-fe.c:304
#7  0x00005555559e039a in net_vhost_user_init (device=0x555555ec2727 "vhost_user", queues=<optimized out>, chr=<optimized out>, name=0x55555672ed30 "net1", peer=0x0) at ../net/vhost-user.c:377
#8  net_init_vhost_user (netdev=<optimized out>, name=0x55555672ed30 "net1", peer=0x0, errp=<optimized out>) at ../net/vhost-user.c:453
#9  0x00005555559d787a in net_client_init1 (netdev=0x555556706320, is_netdev=is_netdev@entry=true, errp=errp@entry=0x555556451690 <error_fatal>) at ../net/net.c:1064
#10 0x00005555559d7b99 in net_client_init (opts=<optimized out>, is_netdev=<optimized out>, errp=0x555556451690 <error_fatal>) at ../net/net.c:1162
#11 0x0000555555e93fa1 in qemu_opts_foreach (list=<optimized out>, func=func@entry=0x5555559d9530 <net_init_netdev>, opaque=opaque@entry=0x0, errp=errp@entry=0x555556451690 <error_fatal>)
    at ../util/qemu-option.c:1135
#12 0x00005555559d9ff2 in net_init_clients (errp=errp@entry=0x555556451690 <error_fatal>) at ../net/net.c:1567
#13 0x0000555555c429dd in qemu_create_late_backends () at ../softmmu/vl.c:2000
#14 qemu_init (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>) at ../softmmu/vl.c:3763
#15 0x000055555593bfb9 in main (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>) at ../softmmu/main.c:50
```
### vhost_set_vring_enable 
```
#0  vhost_set_vring_enable (nc=0x5555567064e0, enable=1) at ../hw/net/vhost_net.c:566
#1  0x0000555555c796d2 in peer_attach (index=0, n=<optimized out>) at ../hw/net/virtio-net.c:674
#2  virtio_net_set_queue_pairs (n=<optimized out>) at ../hw/net/virtio-net.c:718
#3  virtio_net_set_queue_pairs (n=0x55555745bc20) at ../hw/net/virtio-net.c:707
#4  0x0000555555c7c227 in virtio_net_set_multiqueue (multiqueue=<optimized out>, n=<optimized out>) at ../hw/net/virtio-net.c:2841
#5  virtio_net_set_features (vdev=<optimized out>, features=32) at ../hw/net/virtio-net.c:907
#6  0x0000555555caf3f9 in virtio_set_features_nocheck (vdev=vdev@entry=0x55555745bc20, val=32) at ../hw/virtio/virtio.c:3002
#7  0x0000555555cb3939 in virtio_set_features (vdev=0x55555745bc20, val=<optimized out>) at ../hw/virtio/virtio.c:3018
#8  0x0000555555c35130 in memory_region_write_accessor (mr=0x555557454400, addr=12, value=<optimized out>, size=4, shift=<optimized out>, mask=<optimized out>, attrs=...) at ../softmmu/memory.c:492
#9  0x0000555555c30d0f in access_with_adjusted_size (addr=addr@entry=12, value=value@entry=0x7ffee73fd428, size=size@entry=4, access_size_min=<optimized out>, access_size_max=<optimized out>, access_fn=0x555555c350b0 <memory_region_write_accessor>, mr=<optimized out>, attrs=...)
    at ../softmmu/memory.c:554
#10 0x0000555555c344e1 in memory_region_dispatch_write (mr=mr@entry=0x555557454400, addr=addr@entry=12, data=<optimized out>, op=<optimized out>, attrs=attrs@entry=...) at ../softmmu/memory.c:1511
#11 0x0000555555c23aac in flatview_write_continue (fv=fv@entry=0x7ffed8b3cab0, addr=addr@entry=61607010910220, attrs=..., attrs@entry=..., ptr=ptr@entry=0x7ffff43c1028, len=len@entry=4, addr1=<optimized out>, l=<optimized out>, mr=0x555557454400) at ../softmmu/physmem.c:2832
#12 0x0000555555c23d23 in flatview_write (fv=0x7ffed8b3cab0, addr=61607010910220, attrs=..., buf=0x7ffff43c1028, len=4) at ../softmmu/physmem.c:2874
#13 0x0000555555c27634 in address_space_write (len=<optimized out>, buf=0x7ffff43c1028, attrs=..., addr=<optimized out>, as=<optimized out>) at ../softmmu/physmem.c:2970
#14 address_space_rw (as=<optimized out>, addr=<optimized out>, attrs=..., attrs@entry=..., buf=buf@entry=0x7ffff43c1028, len=<optimized out>, is_write=<optimized out>) at ../softmmu/physmem.c:2980
#15 0x0000555555d35a66 in kvm_cpu_exec (cpu=cpu@entry=0x5555567403f0) at ../accel/kvm/kvm-all.c:2944
#16 0x0000555555d36e7d in kvm_vcpu_thread_fn (arg=arg@entry=0x5555567403f0) at ../accel/kvm/kvm-accel-ops.c:49
#17 0x0000555555e8b598 in qemu_thread_start (args=0x555556750c30) at ../util/qemu-thread-posix.c:556
#18 0x00007ffff73aeeb6 in ??? () at /usr/lib64/libc.so.6
#19 0x00007ffff742e02c in ??? () at /usr/lib64/libc.so.6
```

### TODO
1. virtio_pci_set_guest_notifiers
   + msix mask/unmask notify
   + vhost_set_vring_call

## 参考链接
1. [QEMU DOC - Vhost-user Protocol](https://qemu-project.gitlab.io/qemu/interop/vhost-user.html#)
2. [unix(7) — Linux manual page(主要讲socket)](https://man7.org/linux/man-pages/man7/unix.7.html)
3. virtio spec status field
   + 3.1 `section 2.1 Device Status Field`
   + 3.2 `section 4.3 Common configuration structure layout`
