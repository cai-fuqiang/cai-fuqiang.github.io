## open /dev/iommu
```cpp
static struct miscdevice iommu_misc_dev = {
        .minor = MISC_DYNAMIC_MINOR,
        .name = "iommu",
        .fops = &iommufd_fops,
        .nodename = "iommu",
        .mode = 0660,
};


static struct miscdevice vfio_misc_dev = {
        .minor = VFIO_MINOR,
        .name = "vfio",
        .fops = &iommufd_fops,
        .nodename = "vfio/vfio",
        .mode = 0666,
};
static const struct file_operations iommufd_fops = {
        .owner = THIS_MODULE,
        .open = iommufd_fops_open,
        .release = iommufd_fops_release,
        .unlocked_ioctl = iommufd_fops_ioctl,
};
```
iommufd_fops_open
```sh
iommufd_fops_open
|=> ictx = kzalloc(sizeof(*ictx), GFP_KERNEL_ACCOUNT)
|=> xa_init_flags(&ictx->objects, XA_FLAGS_ALLOC1 | XA_FLAGS_ACCOUNT)
|=> xa_init(&ictx->groups)
|=> ictx->file = filp
|=> filp->private_data = ictx;
```


## open /dev/vfio/devices/vfio0
```sh
const struct file_operations vfio_device_fops = {
        .owner          = THIS_MODULE,
        .open           = vfio_device_fops_cdev_open,
        .release        = vfio_device_fops_release,
        .read           = vfio_device_fops_read,
        .write          = vfio_device_fops_write,
        .unlocked_ioctl = vfio_device_fops_unl_ioctl,
        .compat_ioctl   = compat_ptr_ioctl,
        .mmap           = vfio_device_fops_mmap,
};
```

vfio_device_fops_cdev_open
```sh
vfio_device_fops_cdev_open
## 通过inode找到vfio_device
|=> vfio_device *device = container_of(inode->i_cdev,
                            struct vfio_device, cdev);
## 分配vfio_device_file
|=> df = vfio_allocate_device_file(device)
    |=> struct vfio_device_file *df = kzalloc()
    |=> df->device = device
|=> filep->private_data = df
|=> filep->f_mapping = device->inode->i_mapping
```

## IOMMU_IOAS_ALLOC
```cpp
/*
 * ctx: iommufd_ctx
 * ptr: iommufd_ioas
 * type: IOMMUFD_OBJ_IOAS
 * obj
 */
#define __iommufd_object_alloc(ictx, ptr, type, obj)                           \
        container_of(_iommufd_object_alloc(                                    \
                             ictx,                                             \
                             sizeof(*(ptr)) + BUILD_BUG_ON_ZERO(               \
                                                      offsetof(typeof(*(ptr)), \
                                                               obj) != 0),     \
                             type),                                            \
                     typeof(*(ptr)), obj)

#define iommufd_object_alloc(ictx, ptr, type) \
        __iommufd_object_alloc(ictx, ptr, type, obj)
```

```sh
iommufd_ioas_alloc_ioctl
|=> ioas = iommufd_ioas_alloc(ucmd->ictx);
    |=> iommufd_object_alloc(ictx, ioas, IOMMUFD_OBJ_IOAS);
        |=> _iommufd_object_alloc
            |=> obj = kzalloc(size, GFP_KERNEL_ACCOUNT); ## sizeof(*(ptr)) sizeof(*iommufd_ioas)
            |=> xa_alloc(&ictx->objects, &obj->id, XA_ZERO_ENTRY, xa_limit_31b,
                       GFP_KERNEL_ACCOUNT);
        |=> iopt_init_table(&ioas->iopt);
        |=> INIT_LIST_HEAD(&ioas->hwpt_list);
    |=> cmd->out_ioas_id = ioas->obj.id;
    |=> rc = iommufd_ucmd_respond(ucmd, sizeof(*cmd));
    |=> copy_to_user(ucmd->ubuffer, ucmd->cmd, 
             min_t(size_t, ucmd->user_size, cmd_len))
    |=> iommufd_object_finalize(ucmd->ictx, &ioas->obj);
    |=> XA_STATE(xas, &ictx->objects, obj->id);
    |=> old = xas_store(&xas, obj);
```

## VFIO_DEVICE_BIND_IOMMUFD
```sh
vfio_df_ioctl_bind_iommufd
|=> if df->group:
    ## 如果使用leagcy接口获取的vfio device fd, 
    ## 则不能使用该接口绑定
    ## 源码中注释:
    ##
    ## BIND_IOMMUFD only allowed for cdev fds
    |=> return -EINVAL;
## 绑定iommufd
|=> df->iommufd = iommufd_ctx_from_fd(bind.iommufd);
|=> vfio_df_open(df)
    |=> device->open_count++
    ## 说明第一次打开
    |=> if device->open_count == 1:
        |=> vfio_df_device_first_open(df)
            |=> if df->iommufd
                |=> vfio_df_iommufd_bind(df)
                    ## &df->devid 是出参，返回新分配的devid
                    |=> vdev->ops->bind_iommufd(,, &df->devid) : vfio_iommufd_physical_bind
                        |=> iommufd_device_bind()
            --> else
                |=> vfio_device_group_use_iommu();
            |=> device->ops->open_device()
## 将devid copy到用户态
|=>  copy_to_user(, &df->devid)

## 如果分配了iommufd，
|=> if df->iommufd && device->open_count == 1:

iommufd_device_bind
|=> igroup = iommufd_get_group(ictx, dev);
    ## 通过dev找到其iommu_group
    |=> group = iommu_group_get(dev);
        |=> return dev->iommu_group
    ## 找到group id
    |=> id = iommu_group_id(group);
    ## 在ictx->groups xarray中尝试找该id对应的iommufd_group
    |=> igroup = xa_load(&ictx->groups, id);
    ## 如果找到了, 直接返回
    |=> if iommufd_group_try_get(igroup, group)
           |=> if ! group return false
           |=> if ! igroup->group != group return false
           |=> return kref_get_unless_zero(&igroup->ref)
        |=> return igroup
    ## 未找到 iommufd_group分支，说明该group是首次添加到
    ## 该iommufd中
    ##
    ## 分配新的group
    |=> new_igroup = kzalloc(sizeof(*new_igroup), GFP_KERNEL);
    |=> new_igroup->group = group
    |=> new_igroup->ictx = ictx
    ## 替换 ictx->groups, 这块看下具体代码(1)
## !!!!!!!!!!
## 待详细查看
## !!!!!!!!!!
|=> iommu_device_claim_dma_owner(dev, ictx); 
## alloc iommufd_device
|=> idev = iommufd_object_alloc(ictx, idev, IOMMUFD_OBJ_DEVICE);
|=> INIT idev->ictx, dev, igroup
|=> iommufd_object_finalize(ictx, &idev->obj);
|=> *id = idev->obj.id;
|=> return idev

```
1. iommufd_get_group -- xchg ictx->groups
```cpp
iommufd_get_group
{
        ...

        //先假定 ictx->groups 没有该id(NULL)
        cur_igroup = NULL;
        xa_lock(&ictx->groups);
        while (true) {
                //尝试xchg
                igroup = __xa_cmpxchg(&ictx->groups, id, cur_igroup, new_igroup,
                                      GFP_KERNEL);
                if (xa_is_err(igroup)) {
                        xa_unlock(&ictx->groups);
                        iommufd_put_group(new_igroup);
                        return ERR_PTR(xa_err(igroup));
                }
                //如果交换出来的，和假定的一样，说明已经成功替换，并且
                //在替换过程中，没有其他人更改
                /* new_group was successfully installed */
                if (cur_igroup == igroup) {
                        xa_unlock(&ictx->groups);
                        return new_igroup;
                }

                //这个说明其他人有更改，查看其更改的符不符合预期
                //如果返回true，说明符合预期，将新分配的删除。
                /* Check again if the current group is any good */
                if (iommufd_group_try_get(igroup, group)) {
                        xa_unlock(&ictx->groups);
                        iommufd_put_group(new_igroup);
                        return igroup;
                }

                //走到这里说明，有人更改，另外，更改后的结果不符合预期，
                //所以下一步需要replace 别人更改后的
                cur_igroup = igroup;
        }
        ...
}
```
## IOMMU_IOAS_ALLOC
```sh
iommufd_ioas_alloc_ioctl
|=> iommufd_ioas_alloc(ucmd->ictx)
|=> ioas = iommufd_ioas_alloc(ucmd->ictx);
    |=> ioas = iommufd_object_alloc(ictx, ioas, IOMMUFD_OBJ_IOAS)\
    |=> iopt_init_table(&ioas->iopt);
    |=> INIT_LIST_HEAD(&ioas->hwpt_list)
|=> cmd->out_ioas_id = ioas->obj.id
## copy 到用户态
|=> iommufd_ucmd_respond
|=> iommufd_object_finalize()
```

## VFIO_DEVICE_ATTACH_IOMMUFD_PT
vfio_device_fops_unl_ioctl
```sh
vfio_device_fops_unl_ioctl
|=> switch (cmd) VFIO_DEVICE_ATTACH_IOMMUFD_PT:
    |=> vfio_df_ioctl_attach_pt
        |=> if attach.flags & VFIO_DEVICE_ATTACH_PASID
            => device->ops->pasid_attach_ioas(, attach.pasid, &attach.pt_id)
        --> else:
            ## vfio_iommufd_physical_attach_ioas
            => ret = device->ops->attach_ioas(device, &attach.pt_id)
    |=> copy_to_user(&arg->pt_id, &attach.pt_id, sizeof(attach.pt_id))

vfio_iommufd_physical_attach_ioas
|=> if vdev->iommufd_attached
    |=> iommufd_device_replace()
--> else
    |=> iommufd_device_attach()
        |=> iommufd_device_change_pt(,,,&iommufd_device_do_attach)
            |=> switch pt_obj->type:
            --> case IOMMUFD_OBJ_HWPT_NESTED:
                |=> struct iommufd_hw_pagetable *hwpt = container_of(pt_obj,)
                |=> (*do_attach)(idev, pasid, hwpt); ## iommufd_device_do_attach
            --> case IOMMUFD_OBJ_IOAS:
                |=> iommufd_device_auto_get_domain(idev, pasid, ioas,
                                      pt_id, do_attach);
|=> vdev->iommufd_attached()
```
iommufd_device_auto_get_domain
```sh
iommufd_device_auto_get_domain
## 这里会找当前ioas的所有的 iommufd_hw_paging, 看看哪一个能attach进去
|=> foreach(hwpt_paging, &ioas->hwpt_list, hwpt_item)
    |=> hwpt = &hwpt_paging->common
    |=> destroy_hwpt = (*do_attach)(idev, pasid, hwpt) ## iommufd_device_do_attach
        |=> iommufd_hw_pagetable_attach()
            |=> struct iommufd_hwpt_paging *hwpt_paging = find_hwpt_paging(hwpt);
            ## attach 的话，实际上是attach group
            |=> struct iommufd_group *igroup = idev->igroup;
            ## 查找 group 有没有将该pasid attach到别的 hwpt
            |=> attach = xa_cmpxchg(&igroup->pasid_attach, pasid, NULL,
                    XA_ZERO_ENTRY, GFP_KERNEL);
            ## 说明没有attach，新分配一个
            |=> if !attach
                |=> attach = kzalloc()
                |=> xa_init(&attach->device_array)
        |=> old_hwpt = attach->hwpt;
        |=> xa_insert(&attach->device_array, idev->obj.id, XA_ZERO_ENTRY,
                   GFP_KERNEL);
        |=> if old_hwpt && old_hwpt != hwpt:
            ## 说明已经attach到  别的   hwpt 上了。就不能attach 当前的hwpt.
            |=> return -EIVAL
        |=> if attach_resv
            --> iommufd_device_attach_reserved_iova()
        |=> if iommufd_group_first_attach(igroup, pasid))
               ## 查看该pasid 有没有被attach过
               |=> return !xa_load(&igroup->pasid_attach, pasid);
            |=> iommufd_hwpt_attach_device(hwpt, idev, pasid)
                |=> iommufd_hwpt_pasid_compat()
                # 新分配一个handle
                |=> handle = kzalloc(sizeof(*handle), GFP_KERNEL)
                |=> handle->idev = idev
                |=> if pasid == IOMMU_NO_PASID:
                    |=> rc = iommu_attach_group_handle(hwpt->domain, idev->igroup->group,
                                  &handle->handle);
                        |=> ret = xa_insert(&group->pasid_array,
                                  IOMMU_NO_PASID, XA_ZERO_ENTRY, GFP_KERNEL);
                    |=> __iommu_attach_group(domain, group);
                --> else:
                    |=> iommu_attach_device_pasid(hwpt->domain, idev->dev, pasid,
                                  &handle->handle);
                        |=> ret = xa_insert(&group->pasid_array, pasid, XA_ZERO_ENTRY, GFP_KERNEL);
                        |=> __iommu_set_group_pasid(domain, group, pasid, NULL);
            |=> attach->hwpt = hwpt
        ## 可以用该hwpt
        |=> refcount_inc(&hwpt->obj.users);
        ## END iommufd_hw_pagetable_attach()
    ## END iommufd_device_do_attach
    |=> if IS_ERR(destroy_hwpt) and (PTR_ERR(destroy_hwpt) == -EINVAL)
        ## 说明没有出错，只不过该hwpt 不适合该dev(或者说 dev->igroup)
        ## 再继续找下一个
        |=> continue
    |=> *pt_id = hwpt->obj.id;
## END foreach
## 说明所有的hwpt都不合适, 新创建一个
|=> hwpt_paging = iommufd_hwpt_paging_alloc(idev->ictx, ioas, idev, pasid,
                                     0, immediate_attach, NULL);
    |=> hwpt_paging = __iommufd_object_alloc(
                ictx, hwpt_paging, IOMMUFD_OBJ_HWPT_PAGING, common.obj);
    |=> hwpt = &hwpt_paging->common;
    |=> hwpt->pasid_compat = flags & IOMMU_HWPT_ALLOC_PASID;
    |=> if ops->domain_alloc_paging_flags:
        |=> hwpt->domain = ops->domain_alloc_paging_flags()
        |=> hwpt->domain->owner = ops;
    --> else:
        |=> hwpt->domain = iommu_paging_domain_alloc(idev->dev);
            |=> iommu_paging_domain_alloc_flags(dev, 0)
                |=> __iommu_paging_domain_alloc_flags(dev, 
                       IOMMU_DOMAIN_UNMANAGED, flags)
                    |=> ops->domain_alloc_paging_flags() ## intel_iommu_domain_alloc_paging_flags
    |=> hwpt->domain->iommufd_hwpt = hwpt
```
## IOMMU_IOAS_MAP
iommufd_ioas_map
```sh
iommufd_ioas_map
## 通过id找到在ictx中找到相应的obj，然后转换为iommufd_ioas
|=> ioas = iommufd_get_ioas(ucmd->ictx, cmd->ioas_id);
    |=> return container_of(iommufd_get_object(ictx, id, IOMMUFD_OBJ_IOAS),
          struct iommufd_ioas, obj);
        => xa_load(&ictx->objects, id)
    |=> iopt_map_user_pages
        |=> iopt_alloc_user_pages
            ## 向下以pagesize取整 user_addr
            |=> void __user *uptr_down =
                    (void __user *) ALIGN_DOWN((uintptr_t)uptr, PAGE_SIZE);
            |=> pages = iopt_alloc_pages(uptr - uptr_down, length, writable);
                |=> struct iopt_pages *pages;
                ## 分配相关数据结构
                |=> pages = kzalloc(sizeof(*pages), GFP_KERNEL_ACCOUNT);
                |=> init pages struct member
                    |=> pages->source_mm = current->mm
                    |=> mmgrab(pages->source_mm)
                    |=> pages->source_task = current->group_leader
            |=> pages->uptr = uptr_down
            |=> pages->type = IOPT_ADDRESS_USER
        |=> iopt_map_common
            |=> iopt_alloc_area_pages
    |=> iommufd_ucmd_respond
```
iopt_alloc_area_pages
```sh

```
## 参考链接
1. [kernel doc: VFIO - "Virtual Function I/O"](https://www.kernel.org/doc/Documentation/driver-api/vfio.rst)
2. [kernel doc: IOMMUFD](https://docs.kernel.org/userspace-api/iommufd.html)
3. 

## 其他
### container cdev
```cpp
static struct miscdevice vfio_dev = {
        .minor = VFIO_MINOR,
        .name = "vfio",
        .fops = &vfio_fops,
        .nodename = "vfio/vfio",
        .mode = S_IRUGO | S_IWUGO,
};
static const struct file_operations vfio_fops = {
        .owner          = THIS_MODULE,
        .open           = vfio_fops_open,
        .release        = vfio_fops_release,
        .unlocked_ioctl = vfio_fops_unl_ioctl,
        .compat_ioctl   = compat_ptr_ioctl,
};
```
