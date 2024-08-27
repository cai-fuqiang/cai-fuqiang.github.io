---
layout:     post
title:      "[PATCH 09/14] mm: deactivations shouldn't bias the LRU balance"
author:     "fuqiang"
date:       "Wed, 3 Jun 2020 16:02:57 -0700"
categories: [lru_balancing]
tags:       [lru_balancing]
---

```diff
From fbbb602e40c270e884bc545161b238074b20aaae Mon Sep 17 00:00:00 2001
From: Johannes Weiner <hannes@cmpxchg.org>
Date: Wed, 3 Jun 2020 16:02:57 -0700
Subject: [PATCH 09/14] mm: deactivations shouldn't bias the LRU balance
```

Operations like MADV_FREE, FADV_DONTNEED etc.  currently move any affected
active pages to the inactive list to accelerate their reclaim (good) but
also steer page reclaim toward that LRU type, or away from the other
(bad).

> 操作如 MADV_FREE 和 FADV_DONTNEED 等当前会将任何受影响的活动页移到不活跃列
> 表中，以加速它们的回收（这是好的），但也会将页面回收引导向该 LRU 类型，
> 或者远离其他类型（这是不好的）。

The reason why this is undesirable is that such operations are not part of
the regular page aging cycle, and rather a fluke that doesn't say much
about the remaining pages on that list; they might all be in heavy use,
and once the chunk of easy victims has been purged, the VM continues to
apply elevated pressure on those remaining hot pages.  The other LRU,
meanwhile, might have easily reclaimable pages, and there was never a need
to steer away from it in the first place.

> 

As the previous patch outlined, we should focus on recording actually
observed cost to steer the balance rather than speculating about the
potential value of one LRU list over the other.  In that spirit, leave
explicitely deactivated pages to the LRU algorithm to pick up, and let
rotations decide which list is the easiest to reclaim.

```diff
[cai@lca.pw: fix set-but-not-used warning]
  Link: http://lkml.kernel.org/r/20200522133335.GA624@Qians-MacBook-Air.local
Signed-off-by: Johannes Weiner <hannes@cmpxchg.org>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Acked-by: Minchan Kim <minchan@kernel.org>
Acked-by: Michal Hocko <mhocko@suse.com>
Cc: Joonsoo Kim <iamjoonsoo.kim@lge.com>
Cc: Rik van Riel <riel@surriel.com>
Cc: Qian Cai <cai@lca.pw>
Link: http://lkml.kernel.org/r/20200520232525.798933-10-hannes@cmpxchg.org
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 mm/swap.c | 7 +------
 1 file changed, 1 insertion(+), 6 deletions(-)

diff --git a/mm/swap.c b/mm/swap.c
index fedeb925dbfe..7d552af25797 100644
--- a/mm/swap.c
+++ b/mm/swap.c
@@ -498,7 +498,7 @@ void lru_cache_add_active_or_unevictable(struct page *page,
 static void lru_deactivate_file_fn(struct page *page, struct lruvec *lruvec,
 			      void *arg)
 {
-	int lru, file;
+	int lru;
 	bool active;
 
 	if (!PageLRU(page))
@@ -512,7 +512,6 @@ static void lru_deactivate_file_fn(struct page *page, struct lruvec *lruvec,
 		return;
 
 	active = PageActive(page);
-	file = page_is_file_lru(page);
 	lru = page_lru_base_type(page);
 
 	del_page_from_lru_list(page, lruvec, lru + active);
@@ -538,14 +537,12 @@ static void lru_deactivate_file_fn(struct page *page, struct lruvec *lruvec,
 
 	if (active)
 		__count_vm_event(PGDEACTIVATE);
-	lru_note_cost(lruvec, !file, hpage_nr_pages(page));
 }
 
 static void lru_deactivate_fn(struct page *page, struct lruvec *lruvec,
 			    void *arg)
 {
 	if (PageLRU(page) && PageActive(page) && !PageUnevictable(page)) {
-		int file = page_is_file_lru(page);
 		int lru = page_lru_base_type(page);
 
 		del_page_from_lru_list(page, lruvec, lru + LRU_ACTIVE);
@@ -554,7 +551,6 @@ static void lru_deactivate_fn(struct page *page, struct lruvec *lruvec,
 		add_page_to_lru_list(page, lruvec, lru);
 
 		__count_vm_events(PGDEACTIVATE, hpage_nr_pages(page));
-		lru_note_cost(lruvec, !file, hpage_nr_pages(page));
 	}
 }
 
@@ -579,7 +575,6 @@ static void lru_lazyfree_fn(struct page *page, struct lruvec *lruvec,
 
 		__count_vm_events(PGLAZYFREE, hpage_nr_pages(page));
 		count_memcg_page_event(page, PGLAZYFREE);
-		lru_note_cost(lruvec, 0, hpage_nr_pages(page));
 	}
 }
 
-- 
2.42.0

```
