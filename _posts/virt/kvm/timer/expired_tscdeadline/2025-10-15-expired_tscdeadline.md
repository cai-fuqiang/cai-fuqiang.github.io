---
layout: post
title:  ""
author: fuqiang
date:   2024-11-29 21:17:00 +0800
categories: [live_migration,kvm stats]
tags: [kvm-stats]
---

## 前言

## 参考commit
1. Marcelo 首次引入advance tscdeadline hrtimer expiration 
   + KVM: x86: add option to advance tscdeadline hrtimer expiration
   + d0659d946be05e098883b6955d2764595997f6a4
   + Marcelo Tosatti <mtosatti@redhat.com>
   + Tue Dec 16 09:08:15 2014 -0500
   + [MAIL v6](https://lore.kernel.org/all/20141223205841.410988818@redhat.com/)
2. 李万鹏将该功能引入至hv timer
   + KVM: VMX: Optimize tscdeadline timer latency
   + c5ce8235cffa00c207e24210329094d7634bb467
   + Wanpeng Li <wanpengli@tencent.com>
   + Tue May 29 14:53:17 2018 +0800
   + [MAIL](https://lore.kernel.org/all/1527576797-5738-1-git-send-email-wanpengli@tencent.com/#t)
3. 李万鹏提出自动调整`lapic_timer_advance_ns`的功能
   + KVM: LAPIC: Tune lapic_timer_advance_ns automatically
   + 3b8a5df6c4dc6df2ab17d099fb157032f80bdca2
   + Wanpeng Li <wanpengli@tencent.com>
   + Tue Oct 9 09:02:08 2018 +0800
   + [mail v2](https://lore.kernel.org/all/1539046928-18600-1-git-send-email-wanpengli@tencent.com/)

   但是该patch引入后，引入了各种各样的BUG, 后续一直在修...

*  [PATCH v4 0/4] KVM: lapic: Fix a variety of timer adv issues
   + Wed, 17 Apr 2019 10:15:30 -0700
   + https://lore.kernel.org/all/20190417171534.10385-1-sean.j.christopherson@intel.com/ 
* KVM: lapic: Busy wait for timer to expire when using hv_timer
   + commit ee66e453db13d4837a0dcf9d43efa7a88603161b
   + Author: Sean Christopherson <seanjc@google.com>
   + Date:   Tue Apr 16 13:32:44 2019 -0700
   + [MAIL v3](https://lore.kernel.org/all/20190416203248.29429-6-sean.j.christopherson@intel.com/)

