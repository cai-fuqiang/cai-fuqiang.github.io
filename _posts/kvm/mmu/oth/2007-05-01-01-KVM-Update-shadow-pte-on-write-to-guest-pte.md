---
layout: post
title:  "[PATCH] KVM: Update shadow pte on write to guest pte"
author: fuqiang
date:   2007-05-01 16:53:31 +0300
categories: [kvm]
tags: [kvm]
---

```diff
From 0028425f647b6b78a0de8810d6b782fc3ce6c272 Mon Sep 17 00:00:00 2001
From: Avi Kivity <avi@qumranet.com>
Date: Tue, 1 May 2007 16:53:31 +0300
Subject: [PATCH] KVM: Update shadow pte on write to guest pte

A typical demand page/copy on write pattern is:

> demand /dɪˈmænd/: 需要,需求
> pattern [ˈpætərn]: 模式, 方式
>
> 典型的按需 page/copy on write 模式是：

- page fault on vaddr
- kvm propagates fault to guest
- guest handles fault, updates pte
- kvm traps write, clears shadow pte, resumes guest
- guest returns to userspace, re-faults on same vaddr
- kvm installs shadow pte, resumes guest
- guest continues

> propagates /ˈprɑːpəɡeɪts/: 传播, 传递

So, three vmexits for a single guest page fault.  But if instead of clearing
the page table entry, we update to correspond to the value that the guest
has just written, we eliminate the third vmexit.

> eliminate  [ɪˈlɪmɪneɪt]: 消除; 排除; 消灭，
>
> 因此，对于一个guest页面错误，有三个vmexits。但是，如果我们不清除page table entry，
> 而是更新以对应guest刚刚写入的值，那么我们将消除第三个vmexit。

This patch does exactly that, reducing kbuild time by about 10%.

> exactly  [ɪɡˈzæktli] 确切地; 准确地; 精确地;
> 这个补丁正好做到了这一点，将kbuild时间减少了约10%。

> mail list
>
> https://lore.kernel.org/all/1182073480795-git-send-email-avi@qumranet.com/

Signed-off-by: Avi Kivity <avi@qumranet.com>
---
 drivers/kvm/mmu.c         | 15 +++++++++++++++
 drivers/kvm/paging_tmpl.h | 15 +++++++++++++++
 2 files changed, 30 insertions(+)

diff --git a/drivers/kvm/mmu.c b/drivers/kvm/mmu.c
index 23dc4612026b..9ec3df90dbb8 100644
--- a/drivers/kvm/mmu.c
+++ b/drivers/kvm/mmu.c
@@ -1137,6 +1137,20 @@ static void mmu_pte_write_zap_pte(struct kvm_vcpu *vcpu,
 	*spte = 0;
 }

+static void mmu_pte_write_new_pte(struct kvm_vcpu *vcpu,
+				  struct kvm_mmu_page *page,
+				  u64 *spte,
+				  const void *new, int bytes)
+{
+	if (page->role.level != PT_PAGE_TABLE_LEVEL)
+		return;
+
+	if (page->role.glevels == PT32_ROOT_LEVEL)
+		paging32_update_pte(vcpu, page, spte, new, bytes);
+	else
+		paging64_update_pte(vcpu, page, spte, new, bytes);
+}
+
 void kvm_mmu_pte_write(struct kvm_vcpu *vcpu, gpa_t gpa,
 		       const u8 *old, const u8 *new, int bytes)
 {
@@ -1212,6 +1226,7 @@ void kvm_mmu_pte_write(struct kvm_vcpu *vcpu, gpa_t gpa,
 		spte += page_offset / sizeof(*spte);
 		while (npte--) {
 			mmu_pte_write_zap_pte(vcpu, page, spte);
+			mmu_pte_write_new_pte(vcpu, page, spte, new, bytes);
 			++spte;
 		}
 	}
diff --git a/drivers/kvm/paging_tmpl.h b/drivers/kvm/paging_tmpl.h
index bc64cceec039..10ba0a80ce59 100644
--- a/drivers/kvm/paging_tmpl.h
+++ b/drivers/kvm/paging_tmpl.h
@@ -202,6 +202,21 @@ static void FNAME(set_pte)(struct kvm_vcpu *vcpu, u64 guest_pte,
 		       guest_pte & PT_DIRTY_MASK, access_bits, gfn);
 }

+static void FNAME(update_pte)(struct kvm_vcpu *vcpu, struct kvm_mmu_page *page,
+			      u64 *spte, const void *pte, int bytes)
+{
+	pt_element_t gpte;
+
+	if (bytes < sizeof(pt_element_t))
+		return;
+	gpte = *(const pt_element_t *)pte;
+	if (~gpte & (PT_PRESENT_MASK | PT_ACCESSED_MASK))
+		return;
+	pgprintk("%s: gpte %llx spte %p\n", __FUNCTION__, (u64)gpte, spte);
+	FNAME(set_pte)(vcpu, gpte, spte, 6,
+		       (gpte & PT_BASE_ADDR_MASK) >> PAGE_SHIFT);
+}
+
 static void FNAME(set_pde)(struct kvm_vcpu *vcpu, u64 guest_pde,
 			   u64 *shadow_pte, u64 access_bits, gfn_t gfn)
 {
--
2.42.0
```
