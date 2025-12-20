## double size dirty_bitmap

```
commit 60c34612b70711fb14a8dcbc6a79509902450d2e
Author: Takuya Yoshikawa <takuya.yoshikawa@gmail.com>
Date:   Sat Mar 3 14:21:48 2012 +0900

    KVM: Switch to srcu-less get_dirty_log()

    We have seen some problems of the current implementation of
    get_dirty_log() which uses synchronize_srcu_expedited() for updating
    dirty bitmaps; e.g. it is noticeable that this sometimes gives us ms
    order of latency when we use VGA displays.

    当前的get_dirty_log()实现中使用了synchronize_srcu_expedited()来更新脏
    页位图，我们已经注意到其中的一些问题。例如，当我们使用VGA显示器时，
    这有时会导致毫秒级的延迟。

    Furthermore the recent discussion on the following thread
        "srcu: Implement call_srcu()"
        http://lkml.org/lkml/2012/1/31/211
    also motivated us to implement get_dirty_log() without SRCU.

    此外，近期在以下讨论线程中：

    “srcu: Implement call_srcu()”
    http://lkml.org/lkml/2012/1/31/211

    也促使我们实现不使用SRCU的get_dirty_log()。


    This patch achieves this goal without sacrificing the performance of
    both VGA and live migration: in practice the new code is much faster
    than the old one unless we have too many dirty pages.

    这个补丁在不影响VGA和实时迁移性能的情况下实现了这一目标：实际上，新的代码
    比旧代码快得多，除非我们有太多的脏页。

    Implementation:

    The key part of the implementation is the use of xchg() operation for
    clearing dirty bits atomically.  Since this allows us to update only
    BITS_PER_LONG pages at once, we need to iterate over the dirty bitmap
    until every dirty bit is cleared again for the next call.

    实现的关键部分是使用xchg()操作来原子地清除脏位。由于这允许我们一次只更新
    BITS_PER_LONG页，因此我们需要遍历脏位图，直到每个脏位都被清除，以便为下
    一次调用做好准备。

    Although some people may worry about the problem of using the atomic
    memory instruction many times to the concurrently accessible bitmap,
    it is usually accessed with mmu_lock held and we rarely see concurrent
    accesses: so what we need to care about is the pure xchg() overheads.

    尽管有些人可能担心在同时可访问的位图上多次使用原子内存指令的问题，但
    通常这是在持有mmu_lock的情况下访问的，我们很少看到并发访问。因此，我
    们需要关注的只是xchg()的开销。

    Another point to note is that we do not use for_each_set_bit() to check
    which ones in each BITS_PER_LONG pages are actually dirty.  Instead we
    simply use __ffs() in a loop.  This is much faster than repeatedly call
    find_next_bit().

    另一个需要注意的点是，我们没有使用for_each_set_bit()来检查每个BITS_PER_LONG
    页中哪些位实际上是脏的。相反，我们在循环中简单地使用__ffs()。这比反复调用
    find_next_bit()要快得多。

    Performance:

    The dirty-log-perf unit test showed nice improvements, some times faster
    than before, except for some extreme cases; for such cases the speed of
    getting dirty page information is much faster than we process it in the
    userspace.

    dirty-log-perf单元测试显示了显著的改进，有时速度比以前更快，除了在某些极端
    情况下；在这些情况下，获取脏页信息的速度远快于在用户空间中处理它的速度。

    For real workloads, both VGA and live migration, we have observed pure
    improvements: when the guest was reading a file during live migration,
    we originally saw a few ms of latency, but with the new method the
    latency was less than 200us.

    对于实际的工作负载，包括VGA和实时迁移，我们观察到了纯粹的性能提升：
    当虚拟机在实时迁移期间读取文件时，最初我们观察到几毫秒的延迟，但使用新方
    法后，延迟减少到不到200微秒。
```


```
commit b050b015abbef8225826eecb6f6b4d4a6dea7b79
Author: Marcelo Tosatti <mtosatti@redhat.com>
Date:   Wed Dec 23 14:35:22 2009 -0200

    KVM: use SRCU for dirty log

commit 28a37544fb0223eb9805d2567b88f7360edec52a
Author: Xiao Guangrong <xiaoguangrong.eric@gmail.com>
Date:   Thu Nov 24 19:04:35 2011 +0800

    KVM: introduce id_to_memslot function

    Introduce id_to_memslot to get memslot by slot id

    https://lore.kernel.org/all/20091223113833.742662117@redhat.com/

commit 2a31b9db153530df4aa02dac8c32837bf5f47019
Author: Paolo Bonzini <pbonzini@redhat.com>
Date:   Tue Oct 23 02:36:47 2018 +0200

    kvm: introduce manual dirty log reprotect
```

# 参考链接
* https://blog.csdn.net/home19900111/article/details/128019257
* https://terenceli.github.io/%E6%8A%80%E6%9C%AF/2018/08/11/dirty-pages-tracking-in-migration

* https://www.youtube.com/watch?v=i25ojG2aknQ
* [扎心了老铁](https://docs.google.com/presentation/d/1rrpJxT03H1uE-_jG1qT2MnQiv3vsZxf1aJHBUWP6caQ/edit#slide=id.g207f77d4362_0_658)


* [\[YOUTUBE\] KVM dirty page tracking](https://www.youtube.com/watch?v=5FZPIJim_Us)
* [\[PDF\] KVM dirty page tracking](https://kvm-forum.qemu.org/2021/KVM%20Dirty%20Page%20Tracking.pdf)
* https://patchwork.kernel.org/project/linux-fsdevel/cover/20210225002658.2021807-1-axelrasmussen@google.com/

