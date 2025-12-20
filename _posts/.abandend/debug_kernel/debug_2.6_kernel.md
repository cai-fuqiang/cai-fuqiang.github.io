
## 遇到的问题
### 隐含和普通规则混合：已弃用的语法

现象:
```
[root@A06-R08-I134-73-919XB72 linux-history]# make menuconfig
Makefile:415: *** 隐含和普通规则混合：已弃用的语法
Makefile:1440: *** 隐含和普通规则混合：已弃用的语法
make: *** 没有规则可制作目标“menuconfig”。 停止。
```
参考<sup>1</sup>:
修改Makefile
```diff
[root@A06-R08-I134-73-919XB72 linux-history]# git diff
diff --git a/Makefile b/Makefile
index 6393738fe96..9db97d013a2 100644
--- a/Makefile
+++ b/Makefile
@@ -412,10 +412,13 @@ ifeq ($(config-targets),1)
 include $(srctree)/arch/$(ARCH)/Makefile
 export KBUILD_DEFCONFIG

-config %config: scripts_basic outputmakefile FORCE
+config : scripts_basic outputmakefile FORCE
        $(Q)mkdir -p include/linux include/config
        $(Q)$(MAKE) $(build)=scripts/kconfig $@

+%config: scripts_basic outputmakefile FORCE
+       $(Q)mkdir -p include/linux include/config
+       $(Q)$(MAKE) $(build)=scripts/kconfig $@
 else
 # ===========================================================================
 # Build targets only - this includes vmlinux, arch specific targets, clean
@@ -1437,7 +1440,10 @@ endif
        $(Q)$(MAKE) $(build)=$(build-dir) $(target-dir)$(notdir $@)

 # Modules
-/ %/: prepare scripts FORCE
+/: prepare scripts FORCE
+       $(Q)$(MAKE) KBUILD_MODULES=$(if $(CONFIG_MODULES),1) \
+       $(build)=$(build-dir)
+%/: prepare scripts FORCE
        $(Q)$(MAKE) KBUILD_MODULES=$(if $(CONFIG_MODULES),1) \
        $(build)=$(build-dir)
 %.ko: prepare scripts FORCE

```
### gcc版本过高

```sh
[root@A06-R08-I134-73-919XB72 linux-history]# make
  CHK     include/linux/version.h
  CHK     include/linux/utsrelease.h
  CC      arch/x86_64/kernel/asm-offsets.s
In file included from include/linux/stddef.h:4,
                 from include/linux/posix_types.h:4,
                 from include/linux/types.h:14,
                 from include/asm/alternative.h:6,
                 from include/asm/atomic.h:4,
                 from include/linux/crypto.h:20,
                 from arch/x86_64/kernel/asm-offsets.c:7:
include/linux/compiler.h:40:2: 错误：#error no compiler-gcc.h file for this gcc version
   40 | #error no compiler-gcc.h file for this gcc version
      |  ^~~~~
```
## 参考链接
1. [“Makefile:xxx：***混合的隐含和普通规则。停止”](https://blog.csdn.net/zyllong/article/details/37812703)
