---
layout:     post
title:      "[PATCH 20/21] HWPOISON: Add simple debugfs interface to inject hwpoison on arbitary PFNs"
author:     "fuqiang"
date:       "Wed, 16 Sep 2009 11:50:17 +0200"
categories: [mm,hwpoison]
tags:       [hwpoison]
---

```diff
From cae681fc12a824631337906d6ba1dbd498e751a5 Mon Sep 17 00:00:00 2001
From: Andi Kleen <andi@firstfloor.org>
Date: Wed, 16 Sep 2009 11:50:17 +0200
Subject: [PATCH 20/21] HWPOISON: Add simple debugfs interface to inject
 hwpoison on arbitary PFNs

Useful for some testing scenarios, although specific testing is often
done better through MADV_POISON

This can be done with the x86 level MCE injector too, but this interface
allows it to do independently from low level x86 changes.

v2: Add module license (Haicheng Li)

Signed-off-by: Andi Kleen <ak@linux.intel.com>
---
 mm/Kconfig           |  4 ++++
 mm/Makefile          |  1 +
 mm/hwpoison-inject.c | 41 +++++++++++++++++++++++++++++++++++++++++
 3 files changed, 46 insertions(+)
 create mode 100644 mm/hwpoison-inject.c

diff --git a/mm/Kconfig b/mm/Kconfig
index ea2d8b61c631..4b4e57a9643e 100644
--- a/mm/Kconfig
+++ b/mm/Kconfig
@@ -243,6 +243,10 @@ config MEMORY_FAILURE
 	  even when some of its memory has uncorrected errors. This requires
 	  special hardware support and typically ECC memory.
 
+config HWPOISON_INJECT
+	tristate "Poison pages injector"
+	depends on MEMORY_FAILURE && DEBUG_KERNEL
+
 config NOMMU_INITIAL_TRIM_EXCESS
 	int "Turn on mmap() excess space trimming before booting"
 	depends on !MMU
diff --git a/mm/Makefile b/mm/Makefile
index dc2551e7d006..713c9f82d5ab 100644
--- a/mm/Makefile
+++ b/mm/Makefile
@@ -41,5 +41,6 @@ endif
 obj-$(CONFIG_QUICKLIST) += quicklist.o
 obj-$(CONFIG_CGROUP_MEM_RES_CTLR) += memcontrol.o page_cgroup.o
 obj-$(CONFIG_MEMORY_FAILURE) += memory-failure.o
+obj-$(CONFIG_HWPOISON_INJECT) += hwpoison-inject.o
 obj-$(CONFIG_DEBUG_KMEMLEAK) += kmemleak.o
 obj-$(CONFIG_DEBUG_KMEMLEAK_TEST) += kmemleak-test.o
diff --git a/mm/hwpoison-inject.c b/mm/hwpoison-inject.c
new file mode 100644
index 000000000000..e1d85137f086
--- /dev/null
+++ b/mm/hwpoison-inject.c
@@ -0,0 +1,41 @@
+/* Inject a hwpoison memory failure on a arbitary pfn */
+#include <linux/module.h>
+#include <linux/debugfs.h>
+#include <linux/kernel.h>
+#include <linux/mm.h>
+
+static struct dentry *hwpoison_dir, *corrupt_pfn;
+
+static int hwpoison_inject(void *data, u64 val)
+{
+	if (!capable(CAP_SYS_ADMIN))
+		return -EPERM;
+	printk(KERN_INFO "Injecting memory failure at pfn %Lx\n", val);
+	return __memory_failure(val, 18, 0);
+}
+
+DEFINE_SIMPLE_ATTRIBUTE(hwpoison_fops, NULL, hwpoison_inject, "%lli\n");
+
+static void pfn_inject_exit(void)
+{
+	if (hwpoison_dir)
+		debugfs_remove_recursive(hwpoison_dir);
+}
+
+static int pfn_inject_init(void)
+{
+	hwpoison_dir = debugfs_create_dir("hwpoison", NULL);
+	if (hwpoison_dir == NULL)
+		return -ENOMEM;
+	corrupt_pfn = debugfs_create_file("corrupt-pfn", 0600, hwpoison_dir,
+					  NULL, &hwpoison_fops);
+	if (corrupt_pfn == NULL) {
+		pfn_inject_exit();
+		return -ENOMEM;
+	}
+	return 0;
+}
+
+module_init(pfn_inject_init);
+module_exit(pfn_inject_exit);
+MODULE_LICENSE("GPL");
-- 
2.39.3 (Apple Git-146)

```
