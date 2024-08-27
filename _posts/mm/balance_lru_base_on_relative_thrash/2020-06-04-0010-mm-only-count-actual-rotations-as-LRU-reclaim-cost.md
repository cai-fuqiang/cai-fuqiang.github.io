---
layout:     post
title:      "[PATCH 10/14] mm: only count actual rotations as LRU reclaim cost"
author:     "fuqiang"
date:       "Wed, 3 Jun 2020 16:03:00 -0700"
categories: [lru_balancing]
tags:       [lru_balancing]
---

```diff
From 264e90cc07f177adec17ee7cc154ddaa132f0b2d Mon Sep 17 00:00:00 2001
From: Johannes Weiner <hannes@cmpxchg.org>
Date: Wed, 3 Jun 2020 16:03:00 -0700
Subject: [PATCH 10/14] mm: only count actual rotations as LRU reclaim cost

When shrinking the active file list we rotate referenced pages only when
they're in an executable mapping.  The others get deactivated.  When it
comes to balancing scan pressure, though, we count all referenced pages as
rotated, even the deactivated ones.  Yet they do not carry the same cost
to the system: the deactivated page *might* refault later on, but the
deactivation is tangible progress toward freeing pages; rotations on the
other hand cost time and effort without getting any closer to freeing
memory.

Don't treat both events as equal.  The following patch will hook up LRU
balancing to cache and anon refaults, which are a much more concrete cost
signal for reclaiming one list over the other.  Thus, remove the maybe-IO
cost bias from page references, and only note the CPU cost for actual
rotations that prevent the pages from getting reclaimed.

Signed-off-by: Johannes Weiner <hannes@cmpxchg.org>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Acked-by: Minchan Kim <minchan@kernel.org>
Acked-by: Michal Hocko <mhocko@suse.com>
Cc: Joonsoo Kim <iamjoonsoo.kim@lge.com>
Cc: Rik van Riel <riel@surriel.com>
Link: http://lkml.kernel.org/r/20200520232525.798933-11-hannes@cmpxchg.org
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 mm/vmscan.c | 8 +++-----
 1 file changed, 3 insertions(+), 5 deletions(-)

diff --git a/mm/vmscan.c b/mm/vmscan.c
index c5b2a68f4ef6..3c89eac629f3 100644
--- a/mm/vmscan.c
+++ b/mm/vmscan.c
@@ -2054,7 +2054,6 @@ static void shrink_active_list(unsigned long nr_to_scan,
 
 		if (page_referenced(page, 0, sc->target_mem_cgroup,
 				    &vm_flags)) {
-			nr_rotated += hpage_nr_pages(page);
 			/*
 			 * Identify referenced, file-backed active pages and
 			 * give them one more trip around the active list. So
@@ -2065,6 +2064,7 @@ static void shrink_active_list(unsigned long nr_to_scan,
 			 * so we ignore them here.
 			 */
 			if ((vm_flags & VM_EXEC) && page_is_file_lru(page)) {
+				nr_rotated += hpage_nr_pages(page);
 				list_add(&page->lru, &l_active);
 				continue;
 			}
@@ -2080,10 +2080,8 @@ static void shrink_active_list(unsigned long nr_to_scan,
 	 */
 	spin_lock_irq(&pgdat->lru_lock);
 	/*
-	 * Count referenced pages from currently used mappings as rotated,
-	 * even though only some of them are actually re-activated.  This
-	 * helps balance scan pressure between file and anonymous pages in
-	 * get_scan_count.
+	 * Rotating pages costs CPU without actually
+	 * progressing toward the reclaim goal.
 	 */
 	lru_note_cost(lruvec, file, nr_rotated);
 
-- 
2.42.0

```
