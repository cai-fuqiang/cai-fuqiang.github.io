---
layout:     post
title:      "[PATCH 05/21] HWPOISON: Add basic support for poisoned pages in fault handler v3"
author:     "fuqiang"
date:       "Wed, 16 Sep 2009 11:50:06 +0200"
categories: [mm,hwpoison]
tags:       [hwpoison]
---

```diff
From d1737fdbec7f90edc52dd0c5c3767457f28e78d8 Mon Sep 17 00:00:00 2001
From: Andi Kleen <andi@firstfloor.org>
Date: Wed, 16 Sep 2009 11:50:06 +0200
Subject: [PATCH 05/21] HWPOISON: Add basic support for poisoned pages in fault
 handler v3

- Add a new VM_FAULT_HWPOISON error code to handle_mm_fault. Right now
architectures have to explicitely enable poison page support, so
this is forward compatible to all architectures. They only need
to add it when they enable poison page support.
- Add poison page handling in swap in fault code

v2: Add missing delayacct_clear_flag (Hidehiro Kawai)
v3: Really use delayacct_clear_flag (Hidehiro Kawai)

Signed-off-by: Andi Kleen <ak@linux.intel.com>
---
 include/linux/mm.h |  3 ++-
 mm/memory.c        | 18 +++++++++++++++---
 2 files changed, 17 insertions(+), 4 deletions(-)

diff --git a/include/linux/mm.h b/include/linux/mm.h
index 9a72cc78e6b8..082b68cb5ffe 100644
--- a/include/linux/mm.h
+++ b/include/linux/mm.h
@@ -685,11 +685,12 @@ static inline int page_mapped(struct page *page)
 #define VM_FAULT_SIGBUS	0x0002
 #define VM_FAULT_MAJOR	0x0004
 #define VM_FAULT_WRITE	0x0008	/* Special case for get_user_pages */
+#define VM_FAULT_HWPOISON 0x0010	/* Hit poisoned page */
 
 #define VM_FAULT_NOPAGE	0x0100	/* ->fault installed the pte, not return page */
 #define VM_FAULT_LOCKED	0x0200	/* ->fault locked the returned page */
 
-#define VM_FAULT_ERROR	(VM_FAULT_OOM | VM_FAULT_SIGBUS)
+#define VM_FAULT_ERROR	(VM_FAULT_OOM | VM_FAULT_SIGBUS | VM_FAULT_HWPOISON)
 
 /*
  * Can be called by the pagefault handler when it gets a VM_FAULT_OOM.
diff --git a/mm/memory.c b/mm/memory.c
index aede2ce3aba4..02bae2d540d4 100644
--- a/mm/memory.c
+++ b/mm/memory.c
@@ -1319,7 +1319,8 @@ int __get_user_pages(struct task_struct *tsk, struct mm_struct *mm,
 				if (ret & VM_FAULT_ERROR) {
 					if (ret & VM_FAULT_OOM)
 						return i ? i : -ENOMEM;
-					else if (ret & VM_FAULT_SIGBUS)
+					if (ret &
+					    (VM_FAULT_HWPOISON|VM_FAULT_SIGBUS))
 						return i ? i : -EFAULT;
 					BUG();
 				}
@@ -2511,8 +2512,15 @@ static int do_swap_page(struct mm_struct *mm, struct vm_area_struct *vma,
 		goto out;
 
 	entry = pte_to_swp_entry(orig_pte);
-	if (is_migration_entry(entry)) {
-		migration_entry_wait(mm, pmd, address);
+	if (unlikely(non_swap_entry(entry))) {
+		if (is_migration_entry(entry)) {
+			migration_entry_wait(mm, pmd, address);
+		} else if (is_hwpoison_entry(entry)) {
+			ret = VM_FAULT_HWPOISON;
+		} else {
+			print_bad_pte(vma, address, orig_pte, NULL);
+			ret = VM_FAULT_OOM;
+		}
 		goto out;
 	}
 	delayacct_set_flag(DELAYACCT_PF_SWAPIN);
@@ -2536,6 +2544,10 @@ static int do_swap_page(struct mm_struct *mm, struct vm_area_struct *vma,
 		/* Had to read the page from swap area: Major fault */
 		ret = VM_FAULT_MAJOR;
 		count_vm_event(PGMAJFAULT);
+	} else if (PageHWPoison(page)) {
+		ret = VM_FAULT_HWPOISON;
+		delayacct_clear_flag(DELAYACCT_PF_SWAPIN);
+		goto out;
 	}
 
 	lock_page(page);
-- 
2.39.3 (Apple Git-146)

```
