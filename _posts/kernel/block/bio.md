## struct

### bio

### bioset

* bio_slab:

  用来存储当前bioset所使用的bio slab

  > NOTE
  >
  > 那为什么这些disk 不能共用一个bio slab呢？
  > 原因各个disk使用的bio大小是不同的？
  > 大小由 `bs_bio_slab_size()` 函数计算:
  >
  > ```
  > bs->front_pad + sizeof(struct bio) + bs->back_pad
  > ```

* bio_pool:
* bvec_pool:

## global vars

* DEFINE_XARRAY(bio_slabs): 用来存储各个size的bio slab

## bioset_init
