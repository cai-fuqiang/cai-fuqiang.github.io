## struct

### block_device

### bdev_inode

该数据结构用于将 `inode` 和 `block_device` 绑定

|name|type|details|
|----|----|----|
|bdev|block_device|.|
|vfs_inode|inode|.|

## interface

### bdev_alloc

```sh
bdev_alloc
## 首先在blockdev 中分配一个inode
=> inode = new_inode(blockdev_superblock);
=> inode 初始化 {
     inode->i_mode = S_IFBLK
     inode->i_rdev = 0;
     inode->i_data.a_ops = &def_blk_aops;
   }
=> mapping_set_gfp_mask(&inode->i_data, GFP_USER);
## 通过inode能获取 block_device 结构
=> bdev = I_BDEV(inode);
=> bdev->bd_mapping = &inode->i_data;
## 从这里也可以看到，所有分区的 bd_queue(request_queue)都是一个
=> bdev->bd_queue = disk->queue;
## 如果partno不为0，说明是其他分区, 保持和主分区一样的
## BD_HAS_SUBMIT_BIO flag
=> if partno && bdev_test_flag(disk->part0, BD_HAS_SUBMIT_BIO)
   => bdev_set_flag(bdev, BD_HAS_SUBMIT_BIO);
=> bdev->bd_stats = alloc_percpu(struct disk_stats);
=> bdev->bd_disk = disk
```

### blkdev_get_no_open

```sh
blkdev_get_no_open
## ilookup() 中会调用iget()
=> inode = ilookup(blockdev_superblock, dev);
## 如果没有找到，通过module autoload，load 该blockdev major 对应的
## module
=> if !inode && autoload && IS_ENABLED(CONFIG_BLOCK_LEGACY_AUTOLOAD):
   => blk_request_module(dev);
   => inode = ilookup(blockdev_superblock, dev);
=> bdev = &BDEV_I(inode)->bdev
## 这里为什么会 get bdev->bd_device.kobj呢? 这个其实是面向对象的机制,
## block_device 其实是device 的一个父类，所以其可以使用device中的方法。
## 这里使用的是引用计数(device 其实是使用的父类 kobject 方法)
=> if !kobject_get_unless_zero(&bdev->bd_device.kobj)
   => bdev = NULL
=> iput(inode);
=> return bdev
```

## OTHER NOTE

* `blkdev_get_by_dev()` 函数已经不存在但还是有一些注释在引用
