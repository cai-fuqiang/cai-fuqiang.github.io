---
layout:     post
title:      "[PATCH 07/14] mm: vmscan: drop unnecessary div0 avoidance rounding in get_scan_count()"
author:     "fuqiang"
date:       "Wed, 3 Jun 2020 16:02:50 -0700"
categories: [lru_balancing]
tags:       [lru_balancing]
---

```diff
From a4fe1631f313f75c7dced10d9e7eda816bf0937f Mon Sep 17 00:00:00 2001
From: Johannes Weiner <hannes@cmpxchg.org>
Date: Wed, 3 Jun 2020 16:02:50 -0700
Subject: [PATCH 07/14] mm: vmscan: drop unnecessary div0 avoidance rounding in
 get_scan_count()

When we calculate the relative scan pressure between the anon and file LRU
lists, we have to assume that reclaim_stat can contain zeroes.  To avoid
div0 crashes, we add 1 to all denominators like so:

        anon_prio = swappiness;
        file_prio = 200 - anon_prio;

	[...]

        /*
         * The amount of pressure on anon vs file pages is inversely
         * proportional to the fraction of recently scanned pages on
         * each list that were recently referenced and in active use.
         */
        ap = anon_prio * (reclaim_stat->recent_scanned[0] + 1);
        ap /= reclaim_stat->recent_rotated[0] + 1;

        fp = file_prio * (reclaim_stat->recent_scanned[1] + 1);
        fp /= reclaim_stat->recent_rotated[1] + 1;
        spin_unlock_irq(&pgdat->lru_lock);

        fraction[0] = ap;
        fraction[1] = fp;
        denominator = ap + fp + 1;

While reclaim_stat can contain 0, it's not actually possible for ap + fp
to be 0.  One of anon_prio or file_prio could be zero, but they must still
add up to 200.  And the reclaim_stat fraction, due to the +1 in there, is
always at least 1.  So if one of the two numerators is 0, the other one
can't be.  ap + fp is always at least 1.  Drop the + 1.

Signed-off-by: Johannes Weiner <hannes@cmpxchg.org>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Cc: Joonsoo Kim <iamjoonsoo.kim@lge.com>
Cc: Michal Hocko <mhocko@suse.com>
Cc: Minchan Kim <minchan@kernel.org>
Cc: Rik van Riel <riel@surriel.com>
Link: http://lkml.kernel.org/r/20200520232525.798933-8-hannes@cmpxchg.org
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 mm/vmscan.c | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)

diff --git a/mm/vmscan.c b/mm/vmscan.c
index c711efc42cfc..a5a7a8d0764c 100644
--- a/mm/vmscan.c
+++ b/mm/vmscan.c
@@ -2348,7 +2348,7 @@ static void get_scan_count(struct lruvec *lruvec, struct scan_control *sc,
 
 	fraction[0] = ap;
 	fraction[1] = fp;
-	denominator = ap + fp + 1;
+	denominator = ap + fp;
 out:
 	for_each_evictable_lru(lru) {
 		int file = is_file_lru(lru);
-- 
2.42.0

```
