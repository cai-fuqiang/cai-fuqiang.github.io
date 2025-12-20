---
layout: post
title:  "live migration dst"
author: fuqiang
date:   2024-12-10 23:20:00 +0800
categories: [live_migration,dst]
tags: [mig_dst]
---

## src 代码路径
```
qmp_migrate
  socket_start_outgoing_migration
    socket_start_outgoing_migration_internal
      socket_outgoing_migration
        migration_channel_connect
          migrate_fd_connect
            qemu_thread_create(,,,migration_thread)

migrate_fd_connect
  => multifd_save_setup
     => foreach every_id
        => socket_send_channel_create(multifd_new_send_channel_async,)
           => QIOChannelSocket *sioc = qio_channel_socket_new();
              => sioc = QIO_CHANNEL_SOCKET(object_new(TYPE_QIO_CHANNEL_SOCKET));
              => ioc = QIO_CHANNEL(sioc);
              => trace_qio_channel_socket_new()
           => qio_channel_socket_connect_async()
              => trace_qio_channel_socket_connect_async()
              => qio_task_run_in_thread(qio_channel_socket_connect_worker)
                 => qio_channel_socket_connect_worker()
                    => qio_channel_socket_connect_sync()
                       => trace_qio_channel_socket_connect_sync()
                       => fd = socket_connect(addr, errp);
                       => trace_qio_channel_socket_connect_complete()
                       => qio_channel_socket_set_fd(ioc,fd,)
                          => sioc->fd = fd
     => foreach every_id
        => multifd_send_state->ops->send_setup()
           => nocomp_send_setup()  {none}

multifd_new_send_channel_async
  => trace_multifd_new_send_channel_async()
  => p->c = QIO_CHANNEL(sioc)
  => multifd_channel_connect()
     => trace_multifd_set_outgoing_channel()
        => if tls
           => 先忽略
        => qemu_thread_create(,,multifd_send_thread,,)
           => trace_multifd_send_thread_start()
           => while()
              => qio_channel_write_all()
           => trace_multifd_send_thread_end()
```

## dst 代码路径
```
qmp_migrate_incoming
  => qemu_start_incoming_migration
     => socket_start_incoming_migration
        => socket_start_incoming_migration_internal
           => qio_net_listener_open_sync
              => for_each_resaddrs
                 =>
                 => qio_channel_socket_listen_sync
                    => socket_listen
           => qio_net_listener_set_client_func_full(,
                socket_accept_incoming_migration,,,,)

socket_accept_incoming_migration
  => migration_channel_process_incoming
     => migration_ioc_process_incoming
        => multifd_recv_new_channel
           => qemu_thread_create(,,multifd_recv_thread,,)
```

```
(gdb) bt
socket_accept_incoming_migration
qio_net_listener_channel_func
qio_channel_fd_source_dispatch
g_main_context_dispatch
glib_pollfds_poll
os_host_main_loop_wait
main_loop_wait
qemu_main_loop
main

qio_net_listener_channel_func
  => qio_channel_socket_accept
     => cioc = qio_channel_socket_new()
     => cioc->fd = qemu_accept()
     => getsockname()
  => listener->io_func()

qio_channel_socket_listen_async
  => qio_task_run_in_thread(, qio_channel_socket_listen_worker,,)
     => qio_channel_socket_listen_sync()
        => socket_listen()
```
