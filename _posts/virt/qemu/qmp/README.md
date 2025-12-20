### INIT

```sh
main
=> qemu_init
   => qemu_init_subsystems
      => monitor_init_globals
         => qmp_dispatcher_co = qemu_coroutine_create(monitor_qmp_dispatcher_co, NULL);
         => aio_co_schedule(iohandler_get_aio_context(), qmp_dispatcher_co);
      => qemu_init_main_loop
         => qemu_aio_context = aio_context_new(errp);
         => qemu_set_current_aio_context(qemu_aio_context);
            => set_my_aiocontext(ctx);
         -- ATTACH qemu_aio_context {
            => src = aio_get_g_source(qemu_aio_context);
            => g_source_set_name(src, "aio-context");
            => g_source_attach(src, NULL);
         }
         -- ATTACH iohandler_ctx {
            => src = iohandler_get_g_source();
            => g_source_set_name(src, "io-handler");
            => g_source_attach(src, NULL);
         }
```
`handle_qmp_command` stack
```sh
(gdb) bt
#0  handle_qmp_command (opaque=0x5576fe1c3640, req=0x7f6a5c002590, err=0x0) at ../monitor/qmp.c:330
#1  0x00005576fc51e7f6 in json_message_process_token (lexer=0x5576fe1c3708, input=0x5576fe1b6f50, type=JSON_RCURLY, x=47, y=0)
    at ../qobject/json-streamer.c:99
#2  0x00005576fc56810c in json_lexer_feed_char (lexer=0x5576fe1c3708, ch=125 '}', flush=false) at ../qobject/json-lexer.c:313
#3  0x00005576fc5682fc in json_lexer_feed (lexer=0x5576fe1c3708, buffer=0x7f6a43ffd4b0 "}", size=1) at ../qobject/json-lexer.c:350
#4  0x00005576fc51e8ce in json_message_parser_feed (parser=0x5576fe1c36f0, buffer=0x7f6a43ffd4b0 "}", size=1) at ../qobject/json-streamer.c:121
#5  0x00005576fc49c0eb in monitor_qmp_read (opaque=0x5576fe1c3640, buf=0x7f6a43ffd4b0 "}", size=1) at ../monitor/qmp.c:404
#6  0x00005576fc492e53 in qemu_chr_be_write_impl (s=0x5576fd980e40, buf=0x7f6a43ffd4b0 "}", len=1) at ../chardev/char.c:201
#7  0x00005576fc492eb7 in qemu_chr_be_write (s=0x5576fd980e40, buf=0x7f6a43ffd4b0 "}", len=1) at ../chardev/char.c:213
#8  0x00005576fc48e8fc in tcp_chr_read (chan=0x7f6a5c000d30, cond=G_IO_IN, opaque=0x5576fd980e40) at ../chardev/char-socket.c:586
#9  0x00005576fc3a6679 in qio_channel_fd_source_dispatch (source=0x7f6a5c0047e0, callback=0x5576fc48e781 <tcp_chr_read>,
    user_data=0x5576fd980e40) at ../io/channel-watch.c:84
#10 0x00007f71406432f9 in ?? () from target:/usr/lib64/libglib-2.0.so.0
#11 0x00007f7140644ea0 in ?? () from target:/usr/lib64/libglib-2.0.so.0
#12 0x00007f714064574f in g_main_loop_run () from target:/usr/lib64/libglib-2.0.so.0
#13 0x00005576fc3d6b2a in iothread_run (opaque=0x5576fdd0a6d0) at ../iothread.c:73
#14 0x00005576fc52d5e1 in qemu_thread_start (args=0x5576fe1c2b20) at ../util/qemu-thread-posix.c:556
#15 0x00007f7140219eb6 in ?? () from target:/usr/lib64/libc.so.6
#16 0x00007f714029902c in ?? () from target:/usr/lib64/libc.so.6
```


## usefull trace_event
```
trace_monitor_qmp_in_band_enqueue
trace_monitor_qmp_in_band_dequeue
qemu_coroutine_yield
```
