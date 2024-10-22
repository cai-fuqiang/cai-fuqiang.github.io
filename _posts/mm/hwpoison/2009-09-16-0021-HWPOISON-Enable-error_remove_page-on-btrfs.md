---
layout:     post
title:      "[PATCH 21/21] HWPOISON: Enable error_remove_page on btrfs"
author:     "fuqiang"
date:       "Wed, 16 Sep 2009 11:50:18 +0200"
categories: [mm,hwpoison]
tags:       [hwpoison]
---

```diff
From 465fdd97cbe16ef8727221857e96ef62dd352017 Mon Sep 17 00:00:00 2001
From: Andi Kleen <andi@firstfloor.org>
Date: Wed, 16 Sep 2009 11:50:18 +0200
Subject: [PATCH 21/21] HWPOISON: Enable error_remove_page on btrfs

Cc: chris.mason@oracle.com

Signed-off-by: Andi Kleen <ak@linux.intel.com>
---
 fs/btrfs/inode.c | 1 +
 1 file changed, 1 insertion(+)

diff --git a/fs/btrfs/inode.c b/fs/btrfs/inode.c
index 59cba180fe83..dd86050190fc 100644
--- a/fs/btrfs/inode.c
+++ b/fs/btrfs/inode.c
@@ -5269,6 +5269,7 @@ static struct address_space_operations btrfs_aops = {
 	.invalidatepage = btrfs_invalidatepage,
 	.releasepage	= btrfs_releasepage,
 	.set_page_dirty	= btrfs_set_page_dirty,
+	.error_remove_page = generic_error_remove_page,
 };
 
 static struct address_space_operations btrfs_symlink_aops = {
-- 
2.39.3 (Apple Git-146)

```
