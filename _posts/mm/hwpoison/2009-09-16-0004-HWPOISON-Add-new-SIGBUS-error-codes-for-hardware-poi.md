---
layout:     post
title:      "[PATCH 04/21] HWPOISON: Add new SIGBUS error codes for hardware poison signals"
author:     "fuqiang"
date:       "Wed, 16 Sep 2009 11:50:06 +0200"
categories: [mm,hwpoison]
tags:       [hwpoison]
---

```diff
From ad5fa913991e9e0f122b021e882b0d50051fbdbc Mon Sep 17 00:00:00 2001
From: Andi Kleen <andi@firstfloor.org>
Date: Wed, 16 Sep 2009 11:50:06 +0200
Subject: [PATCH 04/21] HWPOISON: Add new SIGBUS error codes for hardware
 poison signals

Add new SIGBUS codes for reporting machine checks as signals. When
the hardware detects an uncorrected ECC error it can trigger these
signals.

> 添加新的SIGBUS代码以报告机器检查作为信号。当硬件检测到未更正的ECC
> 错误时，它可以触发这些信号。




This is needed for telling KVM's qemu about machine checks that happen to
guests, so that it can inject them, but might be also useful for other programs.
I find it useful in my test programs.

> 这对于向KVM的QEMU报告发生在客户机上的机器检查是必要的，以便它可以注入这些信号，
> 但对其他程序也可能有用。我在我的测试程序中发现它很有用。

This patch merely defines the new types.

> 该补丁仅定义了新类型。

- Define two new si_codes for SIGBUS.  BUS_MCEERR_AO and BUS_MCEERR_AR
> 为SIGBUS定义两个新的si_codes：BUS_MCEERR_AO和BUS_MCEERR_AR。

* BUS_MCEERR_AO is for "Action Optional" machine checks, which means that some
corruption has been detected in the background, but nothing has been consumed
so far. The program can ignore those if it wants (but most programs would
already get killed)

> BUS_MCEERR_AO用于“可选操作”机器检查，这意味着在后台检测到了一些损坏，
> 但到目前为止没有任何数据被消耗。程序可以选择忽略这些（但大多数程序可能会
> 被杀死）。

* BUS_MCEERR_AR is for "Action Required" machine checks. This happens
when corrupted data is consumed or the application ran into an area
which has been known to be corrupted earlier. These require immediate
action and cannot just returned to. Most programs would kill themselves.

> BUS_MCEERR_AR用于“需要操作”机器检查。这发生在消耗了损坏数据或应用程序进
> 入了已知损坏的区域。这些情况需要立即处理，不能简单返回。大多数程序会自杀。

- They report the address of the corruption in the user address space
in si_addr.

> 它们在用户地址空间中报告损坏的地址到si_addr。

- Define a new si_addr_lsb field that reports the extent of the corruption
to user space. That's currently always a (small) page. The user application
cannot tell where in this page the corruption happened.

> 定义一个新的si_addr_lsb字段，以向用户空间报告损坏的范围。目前，这始终是一个
> （小）页面。用户应用程序无法判断损坏发生在该页面的哪个位置。

AK: I plan to write a man page update before anyone asks.

> AK：我打算在有人询问之前更新手册页。

Signed-off-by: Andi Kleen <ak@linux.intel.com>
---
 include/asm-generic/siginfo.h | 8 +++++++-
 1 file changed, 7 insertions(+), 1 deletion(-)

diff --git a/include/asm-generic/siginfo.h b/include/asm-generic/siginfo.h
index c840719a8c59..942d30b5aab1 100644
--- a/include/asm-generic/siginfo.h
+++ b/include/asm-generic/siginfo.h
@@ -82,6 +82,7 @@ typedef struct siginfo {
 #ifdef __ARCH_SI_TRAPNO
 			int _trapno;	/* TRAP # which caused the signal */
 #endif
+			short _addr_lsb; /* LSB of the reported address */
 		} _sigfault;
 
 		/* SIGPOLL */
@@ -112,6 +113,7 @@ typedef struct siginfo {
 #ifdef __ARCH_SI_TRAPNO
 #define si_trapno	_sifields._sigfault._trapno
 #endif
+#define si_addr_lsb	_sifields._sigfault._addr_lsb
 #define si_band		_sifields._sigpoll._band
 #define si_fd		_sifields._sigpoll._fd
 
@@ -192,7 +194,11 @@ typedef struct siginfo {
 #define BUS_ADRALN	(__SI_FAULT|1)	/* invalid address alignment */
 #define BUS_ADRERR	(__SI_FAULT|2)	/* non-existant physical address */
 #define BUS_OBJERR	(__SI_FAULT|3)	/* object specific hardware error */
-#define NSIGBUS		3
+/* hardware memory error consumed on a machine check: action required */
+#define BUS_MCEERR_AR	(__SI_FAULT|4)
+/* hardware memory error detected in process but not consumed: action optional*/
+#define BUS_MCEERR_AO	(__SI_FAULT|5)
+#define NSIGBUS		5
 
 /*
  * SIGTRAP si_codes
-- 
2.39.3 (Apple Git-146)

```
