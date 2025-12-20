title:  audit inode
author: fuqiang
date:   2025-12-04 20:05:00 +0800
categories: [kernel, audit]
tags: [kernel, audit]
math:true
---

## overflow

对于`path-based`的syscall(例如`sys_open()`)，其中比较关键的审计信息是`path`以及
其文件的inode信息. audit subsystem想将这些信息保存下来。

理想情况下是, 如果我们`open("./aaa", )`

我们希望得到的审计信息包含哪些呢?

* ./aaa的绝对路径: `$pwd/aaa`
* inode 相关信息: ino..
* 其所在的块设备: dev number

理想是很美好的, 但是, 我们知道audit 子系统是在内核的一些现有的流程中插入一些审计
代码，这些代码会从当前的执行上下文中 获取审计信息，然后在系统调用退出之前RECORD
write(这里只关心syscall audit)

那么上面的这些信息在那些上下文中呢?

* ./aaa绝对路径: 系统调用开始, `getname()`后，可得到安全的内核地址(`copy_from_user`)
* inode 相关信息: 在 path walk 后，`path_lookup()`函数
* 所在的块设备: 也需要在path walk 后，才能确定

但是我们思考几个问题:
1. 我们在`path_lookup`获取到的inode信息一定是`path-based` syscall 参数传过来的路
   径么?
2. 我们要不要获取非`path-based` syscall 所进行文件操作的审计信息

带着这两个问题, 我们来看下linux历史长河中关于`audit inode`轰轰烈烈的改革。

## create file, only record parent ?

第一版patch 在<sup>1</sup>中引入, 其中:

**在`getname()`路径中，会记录文件的路径**

```cpp
/*
 * getname()
 *   audit_getname()
 */
/* Add a name to the list.  Called from fs/namei.c:getname(). */
void audit_getname(const char *name)
{
    struct audit_context *context = current->audit_context;

    BUG_ON(!context);
    if (!context->in_syscall) {
#if AUDIT_DEBUG == 2
        printk(KERN_ERR "%s:%d(:%d): ignoring getname(%p)\n",
               __FILE__, __LINE__, context->serial, name);
        dump_stack();
#endif
        return;
    }
    BUG_ON(context->name_count >= AUDIT_NAMES);
    context->names[context->name_count].name = name;
    context->names[context->name_count].ino  = (unsigned long)-1;
    context->names[context->name_count].rdev = -1;
    ++context->name_count;
}
```

可以看到这里只赋值了`name`, 而未赋值`ino, rdev`. 

**在`path_lookup()`中, 会记录inode相关信息:**
```cpp
/*
 * path_lookup
 *   audit_inode()
 */
/* Store the inode and device from a lookup.  Called from
 * fs/namei.c:path_lookup(). */
void audit_inode(const char *name, unsigned long ino, dev_t rdev)
{
    int idx;
    struct audit_context *context = current->audit_context;

    if (!context->in_syscall)
        return;
    if (context->name_count
        && context->names[context->name_count-1].name
        && context->names[context->name_count-1].name == name)
        idx = context->name_count - 1;
    else if (context->name_count > 1
         && context->names[context->name_count-2].name
         && context->names[context->name_count-2].name == name)
        idx = context->name_count - 2;
    else {
        /* FIXME: how much do we care about inodes that have no
         * associated name? */
        if (context->name_count >= AUDIT_NAMES - AUDIT_NAMES_RESERVED)
            return;
        idx = context->name_count++;
        context->names[idx].name = NULL;
#if AUDIT_DEBUG
        ++context->ino_count;
#endif
    }
    context->names[idx].ino  = ino;
    context->names[idx].rdev = rdev;
}
```
可以看到这里作者做了一些匹配, 只匹配数组的最后两个，如果不匹配，那干脆就不匹
配了, 直接搞个新的name, 将 `name` 更新为`NULL`

另外，我们期望得到的是绝对路径，但是`getname()`可能传递绝对路径(也可能传绝对路径)
所以作者采用了另一种方式记录该信息: 记录`pwd`

```cpp
/*
 * audit_log_exit
 */
static void audit_log_exit(void)
{
    ...
    if (context->pwd.dentry && context->pwd.mnt) {
            ab = audit_log_start(context, GFP_KERNEL, AUDIT_CWD);
            if (ab) {
                    audit_log_d_path(ab, "cwd=", &context->pwd);
                    audit_log_end(ab);
            }
    }
    ...
}
```

但是呢? 如果我们执行`open(O_CREAT, )`创建新文件, 

这时`path_lookup`获取的是父节点的 `inode`:
```sh
open_namei
=> if (!(flag & O_CREAT))
   => path_lookup(pathname, lookup_flags(flag)|LOOKUP_OPEN, nd);
   => goto ok
=> path_lookup(pathname, LOOKUP_PARENT|LOOKUP_OPEN|LOOKUP_CREATE, nd);
```

所以我们通过审计在当前版本内核中，只能获取到父节点的`inode`.

## correct more inode information in file move, create, delete

作者在<sup>2</sup> patch 中在file move create delete 相关的流程中
加入了保存child inode 信息, 并将父节点的信息覆盖。(E.g., 比如在`/a_dir`
路径中添加`a_file`文件，按照原来的逻辑，会得到关于`/a_dir`的审计日志，
而在该patch之后，则得到`/a_dir/a.txt`的审计日志)

## 相关commit

1. first commit - `v2.6.6-rc1`
2. add audit_inode_child
   + [PATCH] Collect more inode information during syscall processing.
   + commit 73241ccca0f7786933f1d31b3d86f2456549953a
   + Author: Amy Griffis <amy.griffis@hp.com>
   + Date:   Thu Nov 3 16:00:25 2005 +0000


## 参考链接
