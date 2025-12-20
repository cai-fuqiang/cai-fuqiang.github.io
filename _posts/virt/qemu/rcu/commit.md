
## 引入pthread atfork
commit 21b7cf9e07e5991c57b461181cfb5bbb6fe7a9d6
Author: Paolo Bonzini <pbonzini@redhat.com>
Date:   Thu Mar 5 16:53:48 2015 +0100

    rcu: handle forks safely

##  引入rcu_enable_atfork
commit a59629fcc6f603e19b516dc08f75334e5c480bd0
Author: Paolo Bonzini <pbonzini@redhat.com>
Date:   Tue Mar 31 13:01:05 2015 +0200

    rcu: do not create thread in pthread_atfork callback

commit 2a96a552f9502ac34c29da2f3a39788db5ee5692
Author: Paolo Bonzini <pbonzini@redhat.com>
Date:   Fri Mar 25 14:00:51 2016 +0100

    Revert "rcu: do not create thread in pthread_atfork callback"

    This reverts commit a59629fcc6f603e19b516dc08f75334e5c480bd0.
    This is not needed anymore because the IOThread mutex is not
    "magic" anymore (need not kick the CPU thread)and also because
    fork callbacks are only enabled at the very beginning of
    QEMU's execution.

commit 73c6e4013b4cd92d3d531bc22cc29e6036ef42e0
Author: Paolo Bonzini <pbonzini@redhat.com>
Date:   Wed Jan 27 08:49:21 2016 +0100

    rcu: completely disable pthread_atfork callbacks as soon as possible

## 其他
### 我尼玛移除了10年了
在 run rcu callbak 时，加大锁
commit a464982499b2f637f6699e3d03e0a9d2e0b5288b
Author: Paolo Bonzini <pbonzini@redhat.com>
Date:   Wed Feb 11 17:15:18 2015 +0100

    rcu: run RCU callbacks under the BQL


## 参考链接
1. [Hierarchical RCU](https://lwn.net/Articles/305782/#Review%20of%20RCU%20Fundamentals)
2. [Linux 核心設計: RCU 同步機制](https://hackmd.io/@sysprog/linux-rcu#%E5%B0%8D%E6%AF%94%E5%85%B6%E4%BB%96-lock-free-%E5%90%8C%E6%AD%A5%E6%A9%9F%E5%88%B6)
3. [QEMU RCU implementation ](https://terenceli.github.io/%E6%8A%80%E6%9C%AF/2021/03/14/qemu-rcu)
4. [Using RCU (Read-Copy-Update) for synchronization](https://www.qemu.org/docs/master/devel/rcu.html)
