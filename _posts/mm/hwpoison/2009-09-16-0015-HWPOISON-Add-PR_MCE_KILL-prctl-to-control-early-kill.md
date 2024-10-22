---
layout:     post
title:      "[PATCH 15/21] HWPOISON: Add PR_MCE_KILL prctl to control early kill behaviour per process"
author:     "fuqiang"
date:       "Wed, 16 Sep 2009 11:50:14 +0200"
categories: [mm,hwpoison]
tags:       [hwpoison]
---

```diff
From 4db96cf077aa938b11fe7ac79ecc9b29ec00fbab Mon Sep 17 00:00:00 2001
From: Andi Kleen <andi@firstfloor.org>
Date: Wed, 16 Sep 2009 11:50:14 +0200
Subject: [PATCH 15/21] HWPOISON: Add PR_MCE_KILL prctl to control early kill
 behaviour per process

This allows processes to override their early/late kill
behaviour on hardware memory errors.

Typically applications which are memory error aware is
better of with early kill (see the error as soon
as possible), all others with late kill (only
see the error when the error is really impacting execution)

There's a global sysctl, but this way an application
can set its specific policy.

We're using two bits, one to signify that the process
stated its intention and that

I also made the prctl future proof by enforcing
the unused arguments are 0.

The state is inherited to children.

Note this makes us officially run out of process flags
on 32bit, but the next patch can easily add another field.

Manpage patch will be supplied separately.

Signed-off-by: Andi Kleen <ak@linux.intel.com>
---
 include/linux/prctl.h |  2 ++
 include/linux/sched.h |  2 ++
 kernel/sys.c          | 22 ++++++++++++++++++++++
 3 files changed, 26 insertions(+)

diff --git a/include/linux/prctl.h b/include/linux/prctl.h
index b00df4c79c63..3dc303197e67 100644
--- a/include/linux/prctl.h
+++ b/include/linux/prctl.h
@@ -88,4 +88,6 @@
 #define PR_TASK_PERF_COUNTERS_DISABLE		31
 #define PR_TASK_PERF_COUNTERS_ENABLE		32
 
+#define PR_MCE_KILL	33
+
 #endif /* _LINUX_PRCTL_H */
diff --git a/include/linux/sched.h b/include/linux/sched.h
index f3d74bd04d18..29eae73c951d 100644
--- a/include/linux/sched.h
+++ b/include/linux/sched.h
@@ -1687,6 +1687,7 @@ extern cputime_t task_gtime(struct task_struct *p);
 #define PF_EXITPIDONE	0x00000008	/* pi exit done on shut down */
 #define PF_VCPU		0x00000010	/* I'm a virtual CPU */
 #define PF_FORKNOEXEC	0x00000040	/* forked but didn't exec */
+#define PF_MCE_PROCESS  0x00000080      /* process policy on mce errors */
 #define PF_SUPERPRIV	0x00000100	/* used super-user privileges */
 #define PF_DUMPCORE	0x00000200	/* dumped core */
 #define PF_SIGNALED	0x00000400	/* killed by a signal */
@@ -1706,6 +1707,7 @@ extern cputime_t task_gtime(struct task_struct *p);
 #define PF_SPREAD_PAGE	0x01000000	/* Spread page cache over cpuset */
 #define PF_SPREAD_SLAB	0x02000000	/* Spread some slab caches over cpuset */
 #define PF_THREAD_BOUND	0x04000000	/* Thread bound to specific cpu */
+#define PF_MCE_EARLY    0x08000000      /* Early kill for mce process policy */
 #define PF_MEMPOLICY	0x10000000	/* Non-default NUMA mempolicy */
 #define PF_MUTEX_TESTER	0x20000000	/* Thread belongs to the rt mutex tester */
 #define PF_FREEZER_SKIP	0x40000000	/* Freezer should not count it as freezeable */
diff --git a/kernel/sys.c b/kernel/sys.c
index b3f1097c76fa..41e02eff3398 100644
--- a/kernel/sys.c
+++ b/kernel/sys.c
@@ -1528,6 +1528,28 @@ SYSCALL_DEFINE5(prctl, int, option, unsigned long, arg2, unsigned long, arg3,
 				current->timer_slack_ns = arg2;
 			error = 0;
 			break;
+		case PR_MCE_KILL:
+			if (arg4 | arg5)
+				return -EINVAL;
+			switch (arg2) {
+			case 0:
+				if (arg3 != 0)
+					return -EINVAL;
+				current->flags &= ~PF_MCE_PROCESS;
+				break;
+			case 1:
+				current->flags |= PF_MCE_PROCESS;
+				if (arg3 != 0)
+					current->flags |= PF_MCE_EARLY;
+				else
+					current->flags &= ~PF_MCE_EARLY;
+				break;
+			default:
+				return -EINVAL;
+			}
+			error = 0;
+			break;
+
 		default:
 			error = -EINVAL;
 			break;
-- 
2.39.3 (Apple Git-146)

```
