---
layout:     post
title:      "[PATCH 06/14] mm: remove use-once cache bias from LRU balancing"
author:     "fuqiang"
date:       "Wed, 3 Jun 2020 16:02:46 -0700"
categories: [lru_balancing]
tags:       [lru_balancing]
---

```diff
From 9682468747390c14962114f261cd76ba188ed987 Mon Sep 17 00:00:00 2001
From: Johannes Weiner <hannes@cmpxchg.org>
Date: Wed, 3 Jun 2020 16:02:46 -0700
Subject: [PATCH 06/14] mm: remove use-once cache bias from LRU balancing

When the splitlru patches divided page cache and swap-backed pages into
separate LRU lists, the pressure balance between the lists was biased to
account for the fact that streaming IO can cause memory pressure with a
flood of pages that are used only once.  New page cache additions would
tip the balance toward the file LRU, and repeat access would neutralize
that bias again.  This ensured that page reclaim would always go for
used-once cache first.

Since e9868505987a ("mm,vmscan: only evict file pages when we have
plenty"), page reclaim generally skips over swap-backed memory entirely as
long as there is used-once cache present, and will apply the LRU balancing
when only repeatedly accessed cache pages are left - at which point the
previous use-once bias will have been neutralized.  This makes the
use-once cache balancing bias unnecessary.

Signed-off-by: Johannes Weiner <hannes@cmpxchg.org>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Acked-by: Michal Hocko <mhocko@suse.com>
Acked-by: Minchan Kim <minchan@kernel.org>
Cc: Joonsoo Kim <iamjoonsoo.kim@lge.com>
Cc: Rik van Riel <riel@surriel.com>
Link: http://lkml.kernel.org/r/20200520232525.798933-7-hannes@cmpxchg.org
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 mm/swap.c | 5 -----
 1 file changed, 5 deletions(-)

diff --git a/mm/swap.c b/mm/swap.c
index 6196d792c952..116b609c25c1 100644
--- a/mm/swap.c
+++ b/mm/swap.c
@@ -293,7 +293,6 @@ static void __activate_page(struct page *page, struct lruvec *lruvec,
 			    void *arg)
 {
 	if (PageLRU(page) && !PageActive(page) && !PageUnevictable(page)) {
-		int file = page_is_file_lru(page);
 		int lru = page_lru_base_type(page);
 
 		del_page_from_lru_list(page, lruvec, lru);
@@ -303,7 +302,6 @@ static void __activate_page(struct page *page, struct lruvec *lruvec,
 		trace_mm_lru_activate(page);
 
 		__count_vm_event(PGACTIVATE);
-		update_page_reclaim_stat(lruvec, file, 1, hpage_nr_pages(page));
 	}
 }
 
@@ -975,9 +973,6 @@ static void __pagevec_lru_add_fn(struct page *page, struct lruvec *lruvec,
 
 	if (page_evictable(page)) {
 		lru = page_lru(page);
-		update_page_reclaim_stat(lruvec, is_file_lru(lru),
-					 PageActive(page),
-					 hpage_nr_pages(page));
 		if (was_unevictable)
 			count_vm_event(UNEVICTABLE_PGRESCUED);
 	} else {
-- 
2.42.0

```
