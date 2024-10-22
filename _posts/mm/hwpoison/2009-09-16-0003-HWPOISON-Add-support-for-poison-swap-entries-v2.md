---
layout:     post
title:      "[PATCH 03/21] HWPOISON: Add support for poison swap entries v2"
author:     "fuqiang"
date:       "Wed, 16 Sep 2009 11:50:05 +0200"
categories: [mm,hwpoison]
tags:       [hwpoison]
---

```diff
From a7420aa54dbf699a5a05feba3c859b6baaa3938c Mon Sep 17 00:00:00 2001
From: Andi Kleen <andi@firstfloor.org>
Date: Wed, 16 Sep 2009 11:50:05 +0200
Subject: [PATCH 03/21] HWPOISON: Add support for poison swap entries v2

Memory migration uses special swap entry types to trigger special actions on
page faults. Extend this mechanism to also support poisoned swap entries, to
trigger poison handling on page faults. This allows follow-on patches to
prevent processes from faulting in poisoned pages again.

v2: Fix overflow in MAX_SWAPFILES (Fengguang Wu)
v3: Better overflow fix (Hidehiro Kawai)

Signed-off-by: Andi Kleen <ak@linux.intel.com>
---
 include/linux/swap.h    | 34 ++++++++++++++++++++++++++++------
 include/linux/swapops.h | 38 ++++++++++++++++++++++++++++++++++++++
 mm/swapfile.c           |  4 ++--
 3 files changed, 68 insertions(+), 8 deletions(-)

diff --git a/include/linux/swap.h b/include/linux/swap.h
index 7c15334f3ff2..f077e454c659 100644
--- a/include/linux/swap.h
+++ b/include/linux/swap.h
@@ -34,15 +34,37 @@ static inline int current_is_kswapd(void)
  * the type/offset into the pte as 5/27 as well.
  */
 #define MAX_SWAPFILES_SHIFT	5
-#ifndef CONFIG_MIGRATION
-#define MAX_SWAPFILES		(1 << MAX_SWAPFILES_SHIFT)
+
+/*
+ * Use some of the swap files numbers for other purposes. This
+ * is a convenient way to hook into the VM to trigger special
+ * actions on faults.
+ */
+
+/*
+ * NUMA node memory migration support
+ */
+#ifdef CONFIG_MIGRATION
+#define SWP_MIGRATION_NUM 2
+#define SWP_MIGRATION_READ	(MAX_SWAPFILES + SWP_HWPOISON_NUM)
+#define SWP_MIGRATION_WRITE	(MAX_SWAPFILES + SWP_HWPOISON_NUM + 1)
 #else
-/* Use last two entries for page migration swap entries */
-#define MAX_SWAPFILES		((1 << MAX_SWAPFILES_SHIFT)-2)
-#define SWP_MIGRATION_READ	MAX_SWAPFILES
-#define SWP_MIGRATION_WRITE	(MAX_SWAPFILES + 1)
+#define SWP_MIGRATION_NUM 0
 #endif
 
+/*
+ * Handling of hardware poisoned pages with memory corruption.
+ */
+#ifdef CONFIG_MEMORY_FAILURE
+#define SWP_HWPOISON_NUM 1
+#define SWP_HWPOISON		MAX_SWAPFILES
+#else
+#define SWP_HWPOISON_NUM 0
+#endif
+
+#define MAX_SWAPFILES \
+	((1 << MAX_SWAPFILES_SHIFT) - SWP_MIGRATION_NUM - SWP_HWPOISON_NUM)
+
 /*
  * Magic header for a swap area. The first part of the union is
  * what the swap magic looks like for the old (limited to 128MB)
diff --git a/include/linux/swapops.h b/include/linux/swapops.h
index 6ec39ab27b4b..cd42e30b7c6e 100644
--- a/include/linux/swapops.h
+++ b/include/linux/swapops.h
@@ -131,3 +131,41 @@ static inline int is_write_migration_entry(swp_entry_t entry)
 
 #endif
 
+#ifdef CONFIG_MEMORY_FAILURE
+/*
+ * Support for hardware poisoned pages
+ */
+static inline swp_entry_t make_hwpoison_entry(struct page *page)
+{
+	BUG_ON(!PageLocked(page));
+	return swp_entry(SWP_HWPOISON, page_to_pfn(page));
+}
+
+static inline int is_hwpoison_entry(swp_entry_t entry)
+{
+	return swp_type(entry) == SWP_HWPOISON;
+}
+#else
+
+static inline swp_entry_t make_hwpoison_entry(struct page *page)
+{
+	return swp_entry(0, 0);
+}
+
+static inline int is_hwpoison_entry(swp_entry_t swp)
+{
+	return 0;
+}
+#endif
+
+#if defined(CONFIG_MEMORY_FAILURE) || defined(CONFIG_MIGRATION)
+static inline int non_swap_entry(swp_entry_t entry)
+{
+	return swp_type(entry) >= MAX_SWAPFILES;
+}
+#else
+static inline int non_swap_entry(swp_entry_t entry)
+{
+	return 0;
+}
+#endif
diff --git a/mm/swapfile.c b/mm/swapfile.c
index 74f1102e8749..ce5dda6d604b 100644
--- a/mm/swapfile.c
+++ b/mm/swapfile.c
@@ -699,7 +699,7 @@ int free_swap_and_cache(swp_entry_t entry)
 	struct swap_info_struct *p;
 	struct page *page = NULL;
 
-	if (is_migration_entry(entry))
+	if (non_swap_entry(entry))
 		return 1;
 
 	p = swap_info_get(entry);
@@ -2085,7 +2085,7 @@ static int __swap_duplicate(swp_entry_t entry, bool cache)
 	int count;
 	bool has_cache;
 
-	if (is_migration_entry(entry))
+	if (non_swap_entry(entry))
 		return -EINVAL;
 
 	type = swp_type(entry);
-- 
2.39.3 (Apple Git-146)

```
