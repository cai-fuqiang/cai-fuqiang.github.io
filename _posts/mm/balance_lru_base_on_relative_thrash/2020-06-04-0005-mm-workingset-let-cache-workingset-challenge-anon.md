---
layout:     post
title:      "[PATCH 05/14] mm: workingset: let cache workingset challenge anon"
author:     "fuqiang"
date:       "Wed, 3 Jun 2020 16:02:43 -0700"
categories: [lru_balancing]
tags:       [lru_balancing]
---

```diff
From 34e58cac6d8f2a76b609b3510ff0c4468a220e61 Mon Sep 17 00:00:00 2001
From: Johannes Weiner <hannes@cmpxchg.org>
Date: Wed, 3 Jun 2020 16:02:43 -0700
Subject: [PATCH 05/14] mm: workingset: let cache workingset challenge anon

We activate cache refaults with reuse distances in pages smaller than the
size of the total cache.  This allows new pages with competitive access
frequencies to establish themselves, as well as challenge and potentially
displace pages on the active list that have gone cold.

However, that assumes that active cache can only replace other active
cache in a competition for the hottest memory.  This is not a great
default assumption.  The page cache might be thrashing while there are
enough completely cold and unused anonymous pages sitting around that we'd
only have to write to swap once to stop all IO from the cache.

Activate cache refaults when their reuse distance in pages is smaller than
the total userspace workingset, including anonymous pages.

Reclaim can still decide how to balance pressure among the two LRUs
depending on the IO situation.  Rotational drives will prefer avoiding
random IO from swap and go harder after cache.  But fundamentally, hot
cache should be able to compete with anon pages for a place in RAM.

Signed-off-by: Johannes Weiner <hannes@cmpxchg.org>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
Cc: Joonsoo Kim <iamjoonsoo.kim@lge.com>
Cc: Michal Hocko <mhocko@suse.com>
Cc: Minchan Kim <minchan@kernel.org>
Cc: Rik van Riel <riel@surriel.com>
Link: http://lkml.kernel.org/r/20200520232525.798933-6-hannes@cmpxchg.org
Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>
---
 mm/workingset.c | 17 ++++++++++++-----
 1 file changed, 12 insertions(+), 5 deletions(-)

diff --git a/mm/workingset.c b/mm/workingset.c
index 474186b76ced..e69865739539 100644
--- a/mm/workingset.c
+++ b/mm/workingset.c
@@ -277,8 +277,8 @@ void workingset_refault(struct page *page, void *shadow)
 	struct mem_cgroup *eviction_memcg;
 	struct lruvec *eviction_lruvec;
 	unsigned long refault_distance;
+	unsigned long workingset_size;
 	struct pglist_data *pgdat;
-	unsigned long active_file;
 	struct mem_cgroup *memcg;
 	unsigned long eviction;
 	struct lruvec *lruvec;
@@ -310,7 +310,6 @@ void workingset_refault(struct page *page, void *shadow)
 		goto out;
 	eviction_lruvec = mem_cgroup_lruvec(eviction_memcg, pgdat);
 	refault = atomic_long_read(&eviction_lruvec->inactive_age);
-	active_file = lruvec_page_state(eviction_lruvec, NR_ACTIVE_FILE);
 
 	/*
 	 * Calculate the refault distance
@@ -345,10 +344,18 @@ void workingset_refault(struct page *page, void *shadow)
 
 	/*
 	 * Compare the distance to the existing workingset size. We
-	 * don't act on pages that couldn't stay resident even if all
-	 * the memory was available to the page cache.
+	 * don't activate pages that couldn't stay resident even if
+	 * all the memory was available to the page cache. Whether
+	 * cache can compete with anon or not depends on having swap.
 	 */
-	if (refault_distance > active_file)
+	workingset_size = lruvec_page_state(eviction_lruvec, NR_ACTIVE_FILE);
+	if (mem_cgroup_get_nr_swap_pages(memcg) > 0) {
+		workingset_size += lruvec_page_state(eviction_lruvec,
+						     NR_INACTIVE_ANON);
+		workingset_size += lruvec_page_state(eviction_lruvec,
+						     NR_ACTIVE_ANON);
+	}
+	if (refault_distance > workingset_size)
 		goto out;
 
 	SetPageActive(page);
-- 
2.42.0

```
