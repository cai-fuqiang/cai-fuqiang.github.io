---
layout:     post
title:      "[PATCH 01/33] [PATCH] KVM: MMU: Implement simple reverse mapping"
author:     "fuqiang"
date:       "Fri, 5 Jan 2007 16:36:38 -0800"
categories: [kvm,cache_shadow_pgtable]
tags:       [cache_shadow_pgtable]
---

```
From cd4a4e5374110444dc38831af517e51ff5a053c3 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Fri, 5 Jan 2007 16:36:38 -0800
```

Subject: [PATCH 01/33] [PATCH] KVM: MMU: Implement simple reverse mapping

Keep in each host page frame's page->private a pointer to the shadow pte which
maps it.  If there are multiple shadow ptes mapping the page, set bit 0 of
page->private, and use the rest as a pointer to a linked list of all such
mappings.

> 在每个host page frame 的 page->private 中保留一个指向映射它的shadow pte 的指针。
> 如果有多个映射该页的shadow ptes，则设置 page->private 的bit 0，并将其余部分用
> 作指向所有此类映射的链表的指针。

Reverse mappings are needed because we when we cache shadow page tables, we
must protect the guest page tables from being modified by the guest, as that
would invalidate the cached ptes.

> ```
> reverse /rɪˈvɜːs/ : 使反转；撤销，废除; 交换
> ```
>
> 需要反向映射是因为当我们缓存影子页表时，我们必须保护来guest page table不被guest修改，
> 因为这会使缓存的 ptes invalidate。

```diff
Signed-off-by: Avi Kivity <avi@qumranet.com>
Acked-by: Ingo Molnar <mingo@elte.hu>
Signed-off-by: Andrew Morton <akpm@osdl.org>
Signed-off-by: Linus Torvalds <torvalds@osdl.org>
---
 drivers/kvm/kvm.h         |   1 +
 drivers/kvm/kvm_main.c    |   1 +
 drivers/kvm/mmu.c         | 152 ++++++++++++++++++++++++++++++++++----
 drivers/kvm/paging_tmpl.h |   1 +
 4 files changed, 142 insertions(+), 13 deletions(-)

diff --git a/drivers/kvm/kvm.h b/drivers/kvm/kvm.h
index e8fe1039e3b5..b65511ed4388 100644
--- a/drivers/kvm/kvm.h
+++ b/drivers/kvm/kvm.h
@@ -236,6 +236,7 @@ struct kvm {
 	struct kvm_vcpu vcpus[KVM_MAX_VCPUS];
 	int memory_config_version;
 	int busy;
+	unsigned long rmap_overflow;
 };
 
 struct kvm_stat {
diff --git a/drivers/kvm/kvm_main.c b/drivers/kvm/kvm_main.c
index bc88c334664b..f2a6b6f0e929 100644
--- a/drivers/kvm/kvm_main.c
+++ b/drivers/kvm/kvm_main.c
@@ -638,6 +638,7 @@ raced:
 						     | __GFP_ZERO);
 			if (!new.phys_mem[i])
 				goto out_free;
+ 			new.phys_mem[i]->private = 0;
 		}
 	}
 
diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 790423c5f23d..0f27beb6c5df 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -27,6 +27,7 @@
 #include "kvm.h"
 
 #define pgprintk(x...) do { } while (0)
+#define rmap_printk(x...) do { } while (0)
 
 #define ASSERT(x)							\
 	if (!(x)) {							\
@@ -125,6 +126,13 @@
 #define PT_DIRECTORY_LEVEL 2
 #define PT_PAGE_TABLE_LEVEL 1
 
+#define RMAP_EXT 4
+
+struct kvm_rmap_desc {
+	u64 *shadow_ptes[RMAP_EXT];
+	struct kvm_rmap_desc *more;
+};
+
 static int is_write_protection(struct kvm_vcpu *vcpu)
 {
 	return vcpu->cr0 & CR0_WP_MASK;
@@ -150,6 +158,120 @@ static int is_io_pte(unsigned long pte)
 	return pte & PT_SHADOW_IO_MARK;
 }

/*
 * 该函数表明, 可以建立 ramp, 这里需要判断spte的值, 必须是
 *   + present: 如果不是present, 则spte 没有map的 page
 *   + writeable: 如果不是writeable, 说明该spte 本身就是 wp的,
 *                而rmap的作用就是, 当某个page变为了pgtable, 需要
 *                反向映射, 找到其所有相关的spte, 将其修改为 wp.
 *                用来使modify this guest pgtable 可以notify到
 *                host. 所以如果本身是wp的. 那就没有必要在做rmap了.
 */
+static int is_rmap_pte(u64 pte)
+{
+	return (pte & (PT_WRITABLE_MASK | PT_PRESENT_MASK))
+		== (PT_WRITABLE_MASK | PT_PRESENT_MASK);
+}
+
+/*
+ * Reverse mapping data structures:
+ *
+ * If page->private bit zero is zero, then page->private points to the
+ * shadow page table entry that points to page_address(page).
+ *
+ * If page->private bit zero is one, (then page->private & ~1) points
+ * to a struct kvm_rmap_desc containing more mappings.
+ */
+static void rmap_add(struct kvm *kvm, u64 *spte)
+{
+	struct page *page;
+	struct kvm_rmap_desc *desc;
+	int i;
+
+	if (!is_rmap_pte(*spte))
+		return;
+	page = pfn_to_page((*spte & PT64_BASE_ADDR_MASK) >> PAGE_SHIFT);
+	if (!page->private) {
+		rmap_printk("rmap_add: %p %llx 0->1\n", spte, *spte);
+		page->private = (unsigned long)spte;
+	} else if (!(page->private & 1)) {
+		rmap_printk("rmap_add: %p %llx 1->many\n", spte, *spte);
+		desc = kzalloc(sizeof *desc, GFP_NOWAIT);
+		if (!desc)
+			BUG(); /* FIXME: return error */
+		desc->shadow_ptes[0] = (u64 *)page->private;
+		desc->shadow_ptes[1] = spte;
+		page->private = (unsigned long)desc | 1;
+	} else {
+		rmap_printk("rmap_add: %p %llx many->many\n", spte, *spte);
+		desc = (struct kvm_rmap_desc *)(page->private & ~1ul);
+		while (desc->shadow_ptes[RMAP_EXT-1] && desc->more)
+			desc = desc->more;
+		if (desc->shadow_ptes[RMAP_EXT-1]) {
+			desc->more = kzalloc(sizeof *desc->more, GFP_NOWAIT);
+			if (!desc->more)
+				BUG(); /* FIXME: return error */
+			desc = desc->more;
+		}
+		for (i = 0; desc->shadow_ptes[i]; ++i)
+			;
+		desc->shadow_ptes[i] = spte;
+	}
+}
+
+static void rmap_desc_remove_entry(struct page *page,
+				   struct kvm_rmap_desc *desc,
+				   int i,
+				   struct kvm_rmap_desc *prev_desc)
+{
+	int j;
+
+	for (j = RMAP_EXT - 1; !desc->shadow_ptes[j] && j > i; --j)
+		;
+	desc->shadow_ptes[i] = desc->shadow_ptes[j];
+	desc->shadow_ptes[j] = 0;
+	if (j != 0)
+		return;
+	if (!prev_desc && !desc->more)
+		page->private = (unsigned long)desc->shadow_ptes[0];
+	else
+		if (prev_desc)
+			prev_desc->more = desc->more;
+		else
+			page->private = (unsigned long)desc->more | 1;
+	kfree(desc);
+}
+
+static void rmap_remove(struct kvm *kvm, u64 *spte)
+{
+	struct page *page;
+	struct kvm_rmap_desc *desc;
+	struct kvm_rmap_desc *prev_desc;
+	int i;
+
+	if (!is_rmap_pte(*spte))
+		return;
+	page = pfn_to_page((*spte & PT64_BASE_ADDR_MASK) >> PAGE_SHIFT);
+	if (!page->private) {
+		printk(KERN_ERR "rmap_remove: %p %llx 0->BUG\n", spte, *spte);
+		BUG();
+	} else if (!(page->private & 1)) {
+		rmap_printk("rmap_remove:  %p %llx 1->0\n", spte, *spte);
+		if ((u64 *)page->private != spte) {
+			printk(KERN_ERR "rmap_remove:  %p %llx 1->BUG\n",
+			       spte, *spte);
+			BUG();
+		}
+		page->private = 0;
+	} else {
+		rmap_printk("rmap_remove:  %p %llx many->many\n", spte, *spte);
+		desc = (struct kvm_rmap_desc *)(page->private & ~1ul);
+		prev_desc = NULL;
+		while (desc) {
+			for (i = 0; i < RMAP_EXT && desc->shadow_ptes[i]; ++i)
+				if (desc->shadow_ptes[i] == spte) {
+					rmap_desc_remove_entry(page, desc, i,
+							       prev_desc);
+					return;
+				}
+			prev_desc = desc;
+			desc = desc->more;
+		}
+		BUG();
+	}
+}
+
 static void kvm_mmu_free_page(struct kvm_vcpu *vcpu, hpa_t page_hpa)
 {
 	struct kvm_mmu_page *page_head = page_header(page_hpa);
@@ -229,27 +351,27 @@ hpa_t gva_to_hpa(struct kvm_vcpu *vcpu, gva_t gva)
 static void release_pt_page_64(struct kvm_vcpu *vcpu, hpa_t page_hpa,
 			       int level)
 {
+	u64 *pos;
+	u64 *end;
+
 	ASSERT(vcpu);
 	ASSERT(VALID_PAGE(page_hpa));
 	ASSERT(level <= PT64_ROOT_LEVEL && level > 0);
 
-	if (level == 1)
-		memset(__va(page_hpa), 0, PAGE_SIZE);
-	else {
-		u64 *pos;
-		u64 *end;
+	for (pos = __va(page_hpa), end = pos + PT64_ENT_PER_PAGE;
+	     pos != end; pos++) {
+		u64 current_ent = *pos;
 
-		for (pos = __va(page_hpa), end = pos + PT64_ENT_PER_PAGE;
-		     pos != end; pos++) {
-			u64 current_ent = *pos;
-
-			*pos = 0;
-			if (is_present_pte(current_ent))
+		if (is_present_pte(current_ent)) {
+			if (level != 1)
 				release_pt_page_64(vcpu,
 						  current_ent &
 						  PT64_BASE_ADDR_MASK,
 						  level - 1);
+			else
+				rmap_remove(vcpu->kvm, pos);
 		}
+		*pos = 0;
 	}
 	kvm_mmu_free_page(vcpu, page_hpa);
 }
@@ -275,6 +397,7 @@ static int nonpaging_map(struct kvm_vcpu *vcpu, gva_t v, hpa_t p)
 			page_header_update_slot(vcpu->kvm, table, v);
 			table[index] = p | PT_PRESENT_MASK | PT_WRITABLE_MASK |
 								PT_USER_MASK;
+			rmap_add(vcpu->kvm, &table[index]);
 			return 0;
 		}
 
@@ -437,6 +560,7 @@ static inline void set_pte_common(struct kvm_vcpu *vcpu,
 	} else {
 		*shadow_pte |= paddr;
 		page_header_update_slot(vcpu->kvm, shadow_pte, gaddr);
+		rmap_add(vcpu->kvm, shadow_pte);
 	}
 }
 
@@ -489,6 +613,7 @@ static void paging_inval_page(struct kvm_vcpu *vcpu, gva_t addr)
 		u64 *table = __va(page_addr);
 
 		if (level == PT_PAGE_TABLE_LEVEL ) {
+			rmap_remove(vcpu->kvm, &table[index]);
 			table[index] = 0;
 			return;
 		}
@@ -679,8 +804,9 @@ void kvm_mmu_slot_remove_write_access(struct kvm *kvm, int slot)
 		pt = __va(page->page_hpa);
 		for (i = 0; i < PT64_ENT_PER_PAGE; ++i)
 			/* avoid RMW */
-			if (pt[i] & PT_WRITABLE_MASK)
+			if (pt[i] & PT_WRITABLE_MASK) {
+				rmap_remove(kvm, &pt[i]);
 				pt[i] &= ~PT_WRITABLE_MASK;
-
+			}
 	}
 }
diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index 09bb9b4ed12d..8c48528a6e89 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -261,6 +261,7 @@ static int FNAME(fix_write_pf)(struct kvm_vcpu *vcpu,
 	mark_page_dirty(vcpu->kvm, gfn);
 	*shadow_ent |= PT_WRITABLE_MASK;
 	*guest_ent |= PT_DIRTY_MASK;
 	/*
 	 * is_rmap_pte() 提到过, 如果是wp的则不需要创建rmap, 在fix_write_pf()中
 	 * 会将pte有wp 变为 writeable, 所以在这里需要执行rmap_add()
 	 */
 	rmap_add(vcpu->kvm, shadow_ent);
 
 	return 1;
 }
-- 
2.42.0

```