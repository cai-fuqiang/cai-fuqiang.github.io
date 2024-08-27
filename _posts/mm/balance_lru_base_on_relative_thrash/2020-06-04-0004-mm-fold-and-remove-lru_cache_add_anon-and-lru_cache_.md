---
layout:     post
title:      "[PATCH 04/14] mm: fold and remove lru_cache_add_anon() and lru_cache_add_file()"
author:     "fuqiang"
date:       "Wed, 3 Jun 2020 16:02:40 -0700"
categories: [lru_balancing]
tags:       [lru_balancing]
---

```diff
From 6058eaec816f29fbe33c9d35694614c9a4ed75ba Mon Sep 17 00:00:00 2001
From: Johannes Weiner <hannes@cmpxchg.org>
Date: Wed, 3 Jun 2020 16:02:40 -0700
Subject: [PATCH 04/14] mm: fold and remove lru_cache_add_anon() and
 lru_cache_add_file()

They're the same function, and for the purpose of all callers they are
equivalent to lru_cache_add().

[akpm@linux-foundation.org: fix it for local_lock changes]
Signed-off-by: Johannes Weiner <hannes@cmpxchg.org>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Reviewed-by: Rik van Riel <riel@surriel.com>
Acked-by: Michal Hocko <mhocko@suse.com>
Acked-by: Minchan Kim <minchan@kernel.org>
Cc: Joonsoo Kim <iamjoonsoo.kim@lge.com>
Link: http://lkml.kernel.org/r/20200520232525.798933-5-hannes@cmpxchg.org
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 fs/cifs/file.c       | 10 +++++-----
 fs/fuse/dev.c        |  2 +-
 include/linux/swap.h |  2 --
 mm/khugepaged.c      |  8 ++------
 mm/memory.c          |  2 +-
 mm/shmem.c           |  6 +++---
 mm/swap.c            | 42 ++++++++++--------------------------------
 mm/swap_state.c      |  2 +-
 8 files changed, 23 insertions(+), 51 deletions(-)

diff --git a/fs/cifs/file.c b/fs/cifs/file.c
index 75ddce8ef456..17a4f49c34f5 100644
--- a/fs/cifs/file.c
+++ b/fs/cifs/file.c
@@ -4162,7 +4162,7 @@ cifs_readv_complete(struct work_struct *work)
 	for (i = 0; i < rdata->nr_pages; i++) {
 		struct page *page = rdata->pages[i];
 
-		lru_cache_add_file(page);
+		lru_cache_add(page);
 
 		if (rdata->result == 0 ||
 		    (rdata->result == -EAGAIN && got_bytes)) {
@@ -4232,7 +4232,7 @@ readpages_fill_pages(struct TCP_Server_Info *server,
 			 * fill them until the writes are flushed.
 			 */
 			zero_user(page, 0, PAGE_SIZE);
-			lru_cache_add_file(page);
+			lru_cache_add(page);
 			flush_dcache_page(page);
 			SetPageUptodate(page);
 			unlock_page(page);
@@ -4242,7 +4242,7 @@ readpages_fill_pages(struct TCP_Server_Info *server,
 			continue;
 		} else {
 			/* no need to hold page hostage */
-			lru_cache_add_file(page);
+			lru_cache_add(page);
 			unlock_page(page);
 			put_page(page);
 			rdata->pages[i] = NULL;
@@ -4437,7 +4437,7 @@ static int cifs_readpages(struct file *file, struct address_space *mapping,
 			/* best to give up if we're out of mem */
 			list_for_each_entry_safe(page, tpage, &tmplist, lru) {
 				list_del(&page->lru);
-				lru_cache_add_file(page);
+				lru_cache_add(page);
 				unlock_page(page);
 				put_page(page);
 			}
@@ -4475,7 +4475,7 @@ static int cifs_readpages(struct file *file, struct address_space *mapping,
 			add_credits_and_wake_if(server, &rdata->credits, 0);
 			for (i = 0; i < rdata->nr_pages; i++) {
 				page = rdata->pages[i];
-				lru_cache_add_file(page);
+				lru_cache_add(page);
 				unlock_page(page);
 				put_page(page);
 			}
diff --git a/fs/fuse/dev.c b/fs/fuse/dev.c
index c7a65cf2bcca..a01540b22122 100644
--- a/fs/fuse/dev.c
+++ b/fs/fuse/dev.c
@@ -840,7 +840,7 @@ static int fuse_try_move_page(struct fuse_copy_state *cs, struct page **pagep)
 	get_page(newpage);
 
 	if (!(buf->flags & PIPE_BUF_FLAG_LRU))
-		lru_cache_add_file(newpage);
+		lru_cache_add(newpage);
 
 	err = 0;
 	spin_lock(&cs->req->waitq.lock);
diff --git a/include/linux/swap.h b/include/linux/swap.h
index 6cea1eb97d45..217bc8e13feb 100644
--- a/include/linux/swap.h
+++ b/include/linux/swap.h
@@ -335,8 +335,6 @@ extern unsigned long nr_free_pagecache_pages(void);
 
 /* linux/mm/swap.c */
 extern void lru_cache_add(struct page *);
-extern void lru_cache_add_anon(struct page *page);
-extern void lru_cache_add_file(struct page *page);
 extern void lru_add_page_tail(struct page *page, struct page *page_tail,
 			 struct lruvec *lruvec, struct list_head *head);
 extern void activate_page(struct page *);
diff --git a/mm/khugepaged.c b/mm/khugepaged.c
index f29038c485e0..3f032487825b 100644
--- a/mm/khugepaged.c
+++ b/mm/khugepaged.c
@@ -1879,13 +1879,9 @@ static void collapse_file(struct mm_struct *mm,
 
 		SetPageUptodate(new_page);
 		page_ref_add(new_page, HPAGE_PMD_NR - 1);
-
-		if (is_shmem) {
+		if (is_shmem)
 			set_page_dirty(new_page);
-			lru_cache_add_anon(new_page);
-		} else {
-			lru_cache_add_file(new_page);
-		}
+		lru_cache_add(new_page);
 
 		/*
 		 * Remove pte page tables, so we can re-fault the page as huge.
diff --git a/mm/memory.c b/mm/memory.c
index d50d8b498af5..3431e76d0e75 100644
--- a/mm/memory.c
+++ b/mm/memory.c
@@ -3139,7 +3139,7 @@ vm_fault_t do_swap_page(struct vm_fault *vmf)
 				if (err)
 					goto out_page;
 
-				lru_cache_add_anon(page);
+				lru_cache_add(page);
 				swap_readpage(page, true);
 			}
 		} else {
diff --git a/mm/shmem.c b/mm/shmem.c
index e83de27ce8f4..ea95a3e46fbb 100644
--- a/mm/shmem.c
+++ b/mm/shmem.c
@@ -1609,7 +1609,7 @@ static int shmem_replace_page(struct page **pagep, gfp_t gfp,
 		 */
 		oldpage = newpage;
 	} else {
-		lru_cache_add_anon(newpage);
+		lru_cache_add(newpage);
 		*pagep = newpage;
 	}
 
@@ -1860,7 +1860,7 @@ static int shmem_getpage_gfp(struct inode *inode, pgoff_t index,
 					charge_mm);
 	if (error)
 		goto unacct;
-	lru_cache_add_anon(page);
+	lru_cache_add(page);
 
 	spin_lock_irq(&info->lock);
 	info->alloced += compound_nr(page);
@@ -2376,7 +2376,7 @@ static int shmem_mfill_atomic_pte(struct mm_struct *dst_mm,
 	if (!pte_none(*dst_pte))
 		goto out_release_unlock;
 
-	lru_cache_add_anon(page);
+	lru_cache_add(page);
 
 	spin_lock_irq(&info->lock);
 	info->alloced++;
diff --git a/mm/swap.c b/mm/swap.c
index f7026f72aca9..6196d792c952 100644
--- a/mm/swap.c
+++ b/mm/swap.c
@@ -424,37 +424,6 @@ void mark_page_accessed(struct page *page)
 }
 EXPORT_SYMBOL(mark_page_accessed);
 
-static void __lru_cache_add(struct page *page)
-{
-	struct pagevec *pvec;
-
-	local_lock(&lru_pvecs.lock);
-	pvec = this_cpu_ptr(&lru_pvecs.lru_add);
-	get_page(page);
-	if (!pagevec_add(pvec, page) || PageCompound(page))
-		__pagevec_lru_add(pvec);
-	local_unlock(&lru_pvecs.lock);
-}
-
-/**
- * lru_cache_add_anon - add a page to the page lists
- * @page: the page to add
- */
-void lru_cache_add_anon(struct page *page)
-{
-	if (PageActive(page))
-		ClearPageActive(page);
-	__lru_cache_add(page);
-}
-
-void lru_cache_add_file(struct page *page)
-{
-	if (PageActive(page))
-		ClearPageActive(page);
-	__lru_cache_add(page);
-}
-EXPORT_SYMBOL(lru_cache_add_file);
-
 /**
  * lru_cache_add - add a page to a page list
  * @page: the page to be added to the LRU.
@@ -466,10 +435,19 @@ EXPORT_SYMBOL(lru_cache_add_file);
  */
 void lru_cache_add(struct page *page)
 {
+	struct pagevec *pvec;
+
 	VM_BUG_ON_PAGE(PageActive(page) && PageUnevictable(page), page);
 	VM_BUG_ON_PAGE(PageLRU(page), page);
-	__lru_cache_add(page);
+
+	get_page(page);
+	local_lock(&lru_pvecs.lock);
+	pvec = this_cpu_ptr(&lru_pvecs.lru_add);
+	if (!pagevec_add(pvec, page) || PageCompound(page))
+		__pagevec_lru_add(pvec);
+	local_unlock(&lru_pvecs.lock);
 }
+EXPORT_SYMBOL(lru_cache_add);
 
 /**
  * lru_cache_add_active_or_unevictable
diff --git a/mm/swap_state.c b/mm/swap_state.c
index ab0462819a5b..fa089002125f 100644
--- a/mm/swap_state.c
+++ b/mm/swap_state.c
@@ -442,7 +442,7 @@ struct page *__read_swap_cache_async(swp_entry_t entry, gfp_t gfp_mask,
 
 	/* Caller will initiate read into locked page */
 	SetPageWorkingset(page);
-	lru_cache_add_anon(page);
+	lru_cache_add(page);
 	*new_page_allocated = true;
 	return page;
 
-- 
2.42.0

```
