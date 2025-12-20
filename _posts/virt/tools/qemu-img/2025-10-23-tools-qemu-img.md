## 命令
* 查看虚拟磁盘信息
  ```
  qemu-img info xxx.qcow2
  ```

  示例:
  ```
  image: Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
  file format: qcow2
  virtual size: 10 GiB (10737418240 bytes)
  disk size: 3.29 GiB
  cluster_size: 65536
  Format specific information:
      compat: 1.1
      compression type: zlib
      lazy refcounts: false
      refcount bits: 16
      corrupt: false
      extended l2: false
  Child node '/file':
      filename: Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
      protocol type: file
      file length: 3.29 GiB (3535536128 bytes)
      disk size: 3.29 GiB
  ```

* 修改磁盘大小
  ```
  qemu-img resize $qcow2_path $size
  ```
  e.g.:
  ```
  qemu-img resize Rocky-9-GenericCloud-Base.latest.x86_64.qcow2 40G
  Image resized.
  ```
* 创建盘
  e.g.
  ```
  qemu-img create -f qcow2 disk1.qcow2 40G
  ```
