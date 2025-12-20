# org patch

# use interrupt #VE instead #PF

[v1](https://lore.kernel.org/all/20200525144125.143875-1-vkuznets@redhat.com/)

[v2](https://lore.kernel.org/kvm/20200511164752.2158645-1-vkuznets@redhat.com/)


commit message:
```
commit 84b09f33a5de528d05c007d9847403a364dfe35e
Author: Vitaly Kuznetsov <vkuznets@redhat.com>
Date:   Mon May 25 16:41:16 2020 +0200

    Revert "KVM: async_pf: Fix #DF due to inject "Page not Present" and "Page Ready" exceptions simultaneously"

...


commit 72de5fa4c16195827252b961ba44028a39dfeaff
Author: Vitaly Kuznetsov <vkuznets@redhat.com>
Date:   Mon May 25 16:41:22 2020 +0200

    KVM: x86: announce KVM_FEATURE_ASYNC_PF_INT
```

# KVM: Drop FOLL_GET in GUP when doing async page fault

```
commit f2e106692d5189303997ad7b96de8d8123aa5613
Author: chai wen <chaiw.fnst@cn.fujitsu.com>
Date:   Mon Oct 14 22:22:33 2013 +0800

    KVM: Drop FOLL_GET in GUP when doing async page fault
```

[\[RFC/query\] kvm async_pf anon pined pages migration](https://lore.kernel.org/all/1380535387-26237-1-git-send-email-chaiw.fnst@cn.fujitsu.com/)

[\[RFC\]\[PATCH\] Drop FOLL_GET in GUP when doing async_pf in kvm](https://lore.kernel.org/all/1381411215-23830-1-git-send-email-chaiw.fnst@cn.fujitsu.com/)


# 
