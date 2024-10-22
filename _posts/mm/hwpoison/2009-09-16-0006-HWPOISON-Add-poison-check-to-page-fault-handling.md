---
layout:     post
title:      "[PATCH 06/21] HWPOISON: Add poison check to page fault handling"
author:     "fuqiang"
date:       "Wed, 16 Sep 2009 11:50:08 +0200"
categories: [mm,hwpoison]
tags:       [hwpoison]
---

```diff
From a3b947eacfe783df4ca0fe53ef8a764eebc2d0d6 Mon Sep 17 00:00:00 2001
From: Andi Kleen <andi@firstfloor.org>
Date: Wed, 16 Sep 2009 11:50:08 +0200
Subject: [PATCH 06/21] HWPOISON: Add poison check to page fault handling

Bail out early when hardware poisoned pages are found in page fault handling.
Since they are poisoned they should not be mapped freshly into processes,
because that would cause another (potentially deadly) machine check

This is generally handled in the same way as OOM, just a different
error code is returned to the architecture code.

v2: Do a page unlock if needed (Fengguang Wu)

Signed-off-by: Andi Kleen <ak@linux.intel.com>
---
 mm/memory.c | 6 ++++++
 1 file changed, 6 insertions(+)

diff --git a/mm/memory.c b/mm/memory.c
index 02bae2d540d4..44ea41196c13 100644
--- a/mm/memory.c
+++ b/mm/memory.c
@@ -2711,6 +2711,12 @@ static int __do_fault(struct mm_struct *mm, struct vm_area_struct *vma,
 	if (unlikely(ret & (VM_FAULT_ERROR | VM_FAULT_NOPAGE)))
 		return ret;
 
+	if (unlikely(PageHWPoison(vmf.page))) {
+		if (ret & VM_FAULT_LOCKED)
+			unlock_page(vmf.page);
+		return VM_FAULT_HWPOISON;
+	}
+
 	/*
 	 * For consistency in subsequent calls, make the faulted page always
 	 * locked.
-- 
2.39.3 (Apple Git-146)

```
