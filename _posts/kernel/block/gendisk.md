## struct gendisk

|name|type|details|
|----|----|----|
|part0|block_device|当前整个磁盘所对应的block_device|
|.|.|例如/dev/sda, 而不是/dev/sda1|

## interface

```sh
__alloc_disk_node
=> struct gendisk *disk;
=> disk = kzalloc_node()
=> bioset_init()
## 分配bdi
=> disk->bdi = bdi_alloc(node_id);
=> disk->queue = q
## 分配一个block_device
=> disk->part0 = bdev_alloc(disk, 0)
```
