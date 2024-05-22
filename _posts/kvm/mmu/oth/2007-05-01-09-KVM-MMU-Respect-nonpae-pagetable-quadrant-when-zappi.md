---
layout: post
title:  "[PATCH] KVM: MMU: Respect nonpae pagetable quadrant when zapping ptes"
author: fuqiang
date:   2007-05-01 16:44:05 +0300
categories: [kvm, kvm_mmu_oth]
tags: [kvm_mmu_oth]
---

```diff
From fce0657ff9f14f6b1f147b5fcd6db2f54c06424e Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Tue, 1 May 2007 16:44:05 +0300
Subject: [PATCH] KVM: MMU: Respect nonpae pagetable quadrant when zapping ptes

When a guest writes to a page that has an mmu shadow, we have to clear
the shadow pte corresponding to the memory location touched by the guest.

> 当guest write一个有mmu shadow 的page,(也就是write了一个page table,该
> pgtable在KVM mmu中有对应的shadow pgtable), 我们必须clear guest touched 
> 内存位置相应的 shadow pte(也就是把上面描述的 shadow pgtable 中对应位置
> 的pte给clear).

Now, in nonpae mode, a single guest page may have two or four shadow
pages (because a nonpae page maps 4MB or 4GB, whereas the pae shadow maps
2MB or 1GB), so we when we look up the page we find up to three additional
aliases for the page.  Since we _clear_ the shadow pte, it doesn't matter
except for a slight performance penalty, but if we want to _update_ the
shadow pte instead of clearing it, it is vital that we don't modify the
aliases.

> whereas: 鉴于, 然而,尽管
> vital [ˈvaɪtl]: 至关重要的
> slight /slaɪt/: 轻微的；略微的；
> penalty /ˈpenəlti/: 处罚；惩罚；刑罚；
> 
> 现在, 在 nonpae mode中, 一个guest page 可能对应着两个, 或者四个 shadow
> pages, (因为 nonpae page 映射 4MB 或者 4GB, 然而 pae shadow 映射2MB或者
> 1GB), 因此，当我们查找页面时，我们最多会找到该页面的三个额外的别名。 
> 由于我们_clear_ shadow pte，所以除了轻微的性能损失外，这并不重要，
> 但是如果我们想要 _update_ shadow pte而不是clear它，那么我们不要修改别名是
> 至关重要的。

Fortunately, exactly which page is needed (the "quadrant") is easily
computed, and is accessible in the shadow page header.  All we need is
to ignore shadow pages from the wrong quadrants.

> 幸运的是，可以轻松计算出到底需要哪个页面（“象限”），并且可以在shadow page 
> header中访问。 我们需要的只是忽略来自错误象限的影子页面。

> mail list
> https://lore.kernel.org/all/11820734804054-git-send-email-avi@qumranet.com/#r

Signed-off-by: Avi Kivity <avi@qumranet.com>
---
 drivers/kvm/mmu.c | 4 ++++
 1 file changed, 4 insertions(+)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index b3a83ef2cf07..23dc4612026b 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -1150,6 +1150,7 @@ void kvm_mmu_pte_write(struct kvm_vcpu *vcpu, gpa_t gpa,
 	unsigned pte_size;
 	unsigned page_offset;
 	unsigned misaligned;
+	unsigned quadrant;
 	int level;
 	int flooded = 0;
 	int npte;
@@ -1202,7 +1203,10 @@ void kvm_mmu_pte_write(struct kvm_vcpu *vcpu, gpa_t gpa,
 				page_offset <<= 1;
 				npte = 2;
 			}
+			quadrant = page_offset >> PAGE_SHIFT;
 			page_offset &= ~PAGE_MASK;
+			if (quadrant != page->role.quadrant)
+				continue;
 		}
 		spte = __va(page->page_hpa);
 		spte += page_offset / sizeof(*spte);
-- 
2.42.0
```
