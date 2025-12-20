## softoffline
soft_offline_page

flags 参数:
* MF_COUNT_INCREASED: 表示在进入该函数之前，page refcount已经自增，在之后的流程中，
  无需在自增refcount来pin 该page

```sh
soft_offline_page(pfn, flags)
## 和 hotplug相关先不看
=> page = pfn_to_online_page()
=> ret  = get_hwpoison_page(page, flags | MF_SOFT_OFFLINE)
   ## online operation
   => if flags & MF_UNPOISON
      => ret = __get_unpoison_page(p)
   -> else:
      => ret = get_any_page(p, flags);
         => if flags & MF_COUNT_INCREASED:
            => count_increased = true
         ## 如果没有该flag， 需要在里面get page
         => if !count_increased
            => ret = __get_hwpoison_page(p, flags)
               ## 该函数只对大页进行get
               => ret = get_hwpoison_hugetlb_folio(folio, &hugetlb, false)
                  => if folio_test_hugetlb(folio):
                     => *hugetlb = true
                     ## 该page 是free page, 什么都不做??? 难道不怕这个
                     ## page 被分配出去么
                     => if folio_test_hugetlb_freed(folio)
                        => ret = 0
                     ## 如果发现该page是 hugetlb migratable, 或者是 unpoison, 
                     ## 则try get
                     -> else if folio_test_hugetlb_migratable(folio) || unpoison:
                        => ret = flio_try_get(folio)
                     -> else
                        => ret = -EBUSY
                  => return ret   ## end : get_hwpoison_hugetlb_folio()
               ## in __get_hwpoison_page
               ## 用来确保该大页没有被降级
               => if hugetlb:
                  => if folio = page_folio(page)
                     => return ret
                  ## 如果走到这里，说明大页被降级了，当作normal size page来处理
                  => if (ret > 0)
                     => folio_put(folio)
                     => folio = page_folio(page)
               ## normal page size page 处理


               ### !!!!!
               ### 下面代码没有看懂，先略过
               => if !HWPoisonHandlable(&folio->page, flags):
                  => return -EBUSY
               => if folio_try_get(folio):
                  => if folio == page_folio(page):
                     => return 1
                  ## 出问题路径
                  => folio_put(folio);
               ## 没有get 成功，或者出错了
               => return 0
               ## END: __get_hwpoison_page
            ## IN get_any_page
            => if !ret:  ## 上面流程返回0
            ## 先略
            ## 先略
            ## 先略
            => else if ret == -EBUSY
            ## 先略
            ## 先略
            ## 先略
         # if ! count_increased
         ## 下面细节也比较多，先略
         => return ret
      ## get_any_page end
      => return ret
   ## get_hwpoison_page end
   => return ret

## 总之，经过上面处理流程，已经get page

## 查看该page是否可以被 hwpoison
=> if hwpoison_filter(page):
   => if ret > 0:
      => put_page()
   => return -EOPNOTSUPP
=> if ret > 0:
   ## 如果ret > 0, 则说明该page有人在使用，需要做两部分动作
   ## 1. migrate_pages
   ## 2. 标 poison
   => ret = soft_offline_in_use_page(page);
-> else:
   ## 如果没有人使用，直接标 posion
   => page_handle_poison(page, true, false)

=> return ret
```

## soft_offline_in_use_page
```cpp

```
