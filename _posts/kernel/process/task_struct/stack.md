

## 相关链接
* vmap kernel stack
  + https://lwn.net/Articles/694348/
  + https://docs.kernel.org/mm/vmalloced-kernel-stacks.html
  + https://lore.kernel.org/all/cover.1468270393.git.luto@kernel.org/
* lkdtm: Test VMAP_STACK allocates leading/trailing guard pages
  + commit 7b25a85c9d9f796c5be7ad3fb8b9553d3e2ed958
  + Author: Kees Cook <kees@kernel.org>
  + Date:   Fri Aug 4 13:04:21 2017 -0700


## 参考链接
1. [中断上下文中调度会怎样？](http://www.wowotech.net/process_management/schedule-in-interrupt.html)
2. [再思linux内核在中断路径内不能睡眠/调度的原因（2010）](https://blog.csdn.net/maray/article/details/5770889)
