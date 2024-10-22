---
layout:     post
title:      "[PATCH 12/21] HWPOISON: Add invalidate_inode_page"
author:     "fuqiang"
date:       "Wed, 16 Sep 2009 11:50:13 +0200"
categories: [mm,hwpoison]
tags:       [hwpoison]
---

```diff
From 83f786680aec8d030184f7ced1a0a3dd8ac81764 Mon Sep 17 00:00:00 2001
From: Wu Fengguang <fengguang.wu@intel.com>
Date: Wed, 16 Sep 2009 11:50:13 +0200
Subject: [PATCH 12/21] HWPOISON: Add invalidate_inode_page

Add a simple way to invalidate a single page
This is just a refactoring of the truncate.c code.
Originally from Fengguang, modified by Andi Kleen.

Signed-off-by: Andi Kleen <ak@linux.intel.com>
---
 include/linux/mm.h |  2 ++
 mm/truncate.c      | 26 ++++++++++++++++++++------
 2 files changed, 22 insertions(+), 6 deletions(-)

diff --git a/include/linux/mm.h b/include/linux/mm.h
index 8cbc0aafd5bd..b05bbde0296d 100644
--- a/include/linux/mm.h
+++ b/include/linux/mm.h
@@ -796,6 +796,8 @@ extern int vmtruncate_range(struct inode * inode, loff_t offset, loff_t end);
 
 int truncate_inode_page(struct address_space *mapping, struct page *page);
 
+int invalidate_inode_page(struct page *page);
+
 #ifdef CONFIG_MMU
 extern int handle_mm_fault(struct mm_struct *mm, struct vm_area_struct *vma,
 			unsigned long address, unsigned int flags);
diff --git a/mm/truncate.c b/mm/truncate.c
index 2519a7c92873..ea132f7ea2d2 100644
--- a/mm/truncate.c
+++ b/mm/truncate.c
@@ -146,6 +146,24 @@ int truncate_inode_page(struct address_space *mapping, struct page *page)
 	return truncate_complete_page(mapping, page);
 }
 
+/*
+ * Safely invalidate one page from its pagecache mapping.
+ * It only drops clean, unused pages. The page must be locked.
+ *
+ * Returns 1 if the page is successfully invalidated, otherwise 0.
+ */
+int invalidate_inode_page(struct page *page)
+{
+	struct address_space *mapping = page_mapping(page);
+	if (!mapping)
+		return 0;
+	if (PageDirty(page) || PageWriteback(page))
+		return 0;
+	if (page_mapped(page))
+		return 0;
+	return invalidate_complete_page(mapping, page);
+}
+
 /**
  * truncate_inode_pages - truncate range of pages specified by start & end byte offsets
  * @mapping: mapping to truncate
@@ -312,12 +330,8 @@ unsigned long invalidate_mapping_pages(struct address_space *mapping,
 			if (lock_failed)
 				continue;
 
-			if (PageDirty(page) || PageWriteback(page))
-				goto unlock;
-			if (page_mapped(page))
-				goto unlock;
-			ret += invalidate_complete_page(mapping, page);
-unlock:
+			ret += invalidate_inode_page(page);
+
 			unlock_page(page);
 			if (next > end)
 				break;
-- 
2.39.3 (Apple Git-146)

```
