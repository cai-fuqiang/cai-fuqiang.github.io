## CPU feature
```cpp
static const TypeInfo x86_cpu_type_info = {
    .name = TYPE_X86_CPU,
    .parent = TYPE_CPU,
    .instance_size = sizeof(X86CPU),
    .instance_init = x86_cpu_initfn,
    .abstract = true,
    .class_size = sizeof(X86CPUClass),
    .class_init = x86_cpu_common_class_init,
};
```
type init:
```sh
main
|-> module_call_init
    |-> qemu_init
        |-> qemu_init_subsystems
            |-> module_call_init(type = MODULE_INIT_QOM)
|-> x86_cpu_register_types
    |-> type_register_static(&x86_cpu_type_info);
        |-> for (i = 0; i < ARRAY_SIZE(builtin_x86_defs); i++)
            |-> x86_register_cpudef_type(&builtin_x86_defs[i]);
                |-> char *typename = x86_cpu_type_name(def->name);
                |-> TypeInfo ti = {
                        .name = typename,
                        .parent = TYPE_X86_CPU,
                        .class_init = x86_cpu_cpudef_class_init,
                        .class_data = def,
                    };
                |-> type_register(&ti);
```

## CPU instance init
```
#0  x86_cpu_initfn (obj=0x5555575cf670) at ../target/i386/cpu.c:9059
#1  0x0000555555f42cf0 in object_init_with_type (obj=0x5555575cf670, ti=0x5555572d2010) at ../qom/object.c:428
#2  0x0000555555f42cd2 in object_init_with_type (obj=0x5555575cf670, ti=0x5555572d2220) at ../qom/object.c:424
#3  0x0000555555f432e0 in object_initialize_with_type (obj=0x5555575cf670, size=17104, type=0x5555572d2220) at ../qom/object.c:570
#4  0x0000555555f43b01 in object_new_with_type (type=0x5555572d2220) at ../qom/object.c:774
#5  0x0000555555f43b6f in object_new (typename=0x55555631fed0 "qemu64-x86_64-cpu") at ../qom/object.c:789
#6  0x0000555555e400ba in x86_cpu_new (x86ms=0x55555752fa00, apic_id=0, errp=0x555557251ae0 <error_fatal>) at ../hw/i386/x86-common.c:59
    (gdb) p cpu->class->type.name
    $7 = 0x5555572d23a0 "qemu64-x86_64-cpu"
#7  0x0000555555e4027d in x86_cpus_init (x86ms=0x55555752fa00, default_cpu_version=1) at ../hw/i386/x86-common.c:115
#8  0x0000555555e3c4e6 in pc_init1 (machine=0x55555752fa00, pci_type=0x555556317d42 "i440FX") at ../hw/i386/pc_piix.c:185
#9  0x0000555555e3d11c in pc_i440fx_init (machine=0x55555752fa00) at ../hw/i386/pc_piix.c:451
#10 0x0000555555e3d30e in pc_i440fx_machine_10_1_init (machine=0x55555752fa00) at ../hw/i386/pc_piix.c:492
#11 0x0000555555a7c2f3 in machine_run_board_init (machine=0x55555752fa00, mem_path=0x0, errp=0x7fffffffdb90) at ../hw/core/machine.c:1669
#12 0x0000555555d3829f in qemu_init_board () at ../system/vl.c:2710
#13 0x0000555555d38635 in qmp_x_exit_preconfig (errp=0x555557251ae0 <error_fatal>) at ../system/vl.c:2804
#14 0x0000555555d3b291 in qemu_init (argc=1, argv=0x7fffffffdf38) at ../system/vl.c:3840
#15 0x0000555556079cb2 in main (argc=1, argv=0x7fffffffdf38) at ../system/main.c:71
```


## kvm vcpu init
```sh
kvm_init_vcpu
|-> kvm_arch_init_vcpu
    |-> kvm_x86_build_cpuid
    |-> kvm_vcpu_ioctl(cs, KVM_SET_CPUID2, &cpuid_data)
```
## cpu_x86_cpuid
```sh
cpu_x86_cpuid
|-> case 0xA:
    \-> if cpu->enable_pmu:
        \-> x86_cpu_get_supported_cpuid(0xA, count, )
            |-> if kvm_enabled()
                |-> *eax = kvm_arch_get_supported_cpuid(kvm_state, func, index, R_EAX);
                |-> *ebx = kvm_arch_get_supported_cpuid(kvm_state, func, index, R_EBX);
                |-> *ecx = kvm_arch_get_supported_cpuid(kvm_state, func, index, R_ECX);
                |-> *edx = kvm_arch_get_supported_cpuid(kvm_state, func, index, R_EDX);
```
kvm_arch_get_supported_cpuid
```sh
kvm_arch_get_supported_cpuid:
|-> cpuid = get_supported_cpuid(s);
    |-> if cpuid_cache != NULL
        |-> return cpuid_cache;
    ## 这里为什么搞了一个如此蹩脚的方式... 主要的原因是因为该接口buffer是由用户
    ## 态传入的, 用户态也不确定buffer大小够不够，所以得依次加大buffer大小。然后
    ## 再调用系统调用
    |-> while ((cpuid = try_get_cpuid(s, max)) == NULL)
                ## 可变数组
                |-> size = sizeof(*cpuid) + max * sizeof(*cpuid->entries);
                |-> cpuid = g_malloc0(size);
                |-> cpuid->nent = max;
                    |-> r = kvm_ioctl(s, KVM_GET_SUPPORTED_CPUID, cpuid);
                        ## 说明分配的buffer填满了，需要重新分配一个更大的
                        |-> if r == 0 && cpuid->nent >= max
                            |-> return NULL
        |-> max *= 2;
    |-> cpuid_cache = cpuid;
    |-> return cpuid;
```
kvm 流程:
```sh
kvm_dev_ioctl_get_cpuid
|-> array.entries = kvcalloc(cpuid->nent, sizeof(struct kvm_cpuid_entry2), GFP_KERNEL);
|-> array.maxnent = cpuid->nent;
    |-> for i = 0; i < ARRAY_SIZE(funcs); i++:
        |-> r = get_cpuid_func(&array, funcs[i], type);
            |-> r = do_cpuid_func(array, func, type);
            |-> limit = array->entries[array->nent - 1].eax;
            |-> for (func = func + 1; func <= limit; ++func)
                |-> r = do_cpuid_func(array, func, type);
                    |-> if r
                        |-> break
|-> cpuid->nent = array.nent;
```
do_cpuid_func:
```sh
do_cpuid_func
|-> if type == KVM_GET_EMULATED_CPUID:
    |-> return __do_cpuid_func_emulated()
|-> __do_cpuid_func(array, func)
    |-> entry = do_host_cpuid(array, function, 0);
    |-> switch (function)
        ## 举几个例子
        |-> case 0:
            ## function 0 eax 表示, 最大的cpuid index, 但是
            ## 0x24 超过了手册的最大值，不知道是不是kvm预留的
            |-> entry->eax = min(entry->eax, 0x24U)
            break
        |-> case 1:
            ## 需要用KVM 之前定义好的值覆盖
            |-> cpuid_entry_override(entry, CPUID_1_EDX);
            |-> cpuid_entry_override(entry, CPUID_1_ECX);
            break
        |-> case 4:
            case 0x8000001d:
            # 这个比较特殊, 拿 function 4来说， ECX 是一个selector, 选择
            # 不同的cache level + cache type
            #
            # 上面已经将ECX设置为0, 调用过依次cpuid, 接下来将ecx自增作为selector,
            # 然后观察返回的eax的值，如果是0，则表示本次的ecx是invalid selector
            |-> for (i = 1; entry->eax & 0x1f; ++i)
                |-> entry = do_host_cpuid(array, function, i)
```

cpuid_entry_override:
```cpp
static __always_inline void cpuid_entry_override(struct kvm_cpuid_entry2 *entry,
                                                 unsigned int leaf)
{
        u32 *reg = cpuid_entry_get_reg(entry, leaf * 32);

        BUILD_BUG_ON(leaf >= ARRAY_SIZE(kvm_cpu_caps));
        //从kvm_cpu_caps这个全局变量中获取
        *reg = kvm_cpu_caps[leaf];
}
//全局变量, 表示kvm自定义的cap
u32 kvm_cpu_caps[NR_KVM_CPU_CAPS] __read_mostly;
```

在下面流程中初始化:
```sh
vmx_hardware_setup
|-> vmx_set_cpu_caps
    |-> kvm_set_cpu_caps
        |-> kvm_cpu_cap_init(CPUID_1_ECX,...)
```
kvm_cpu_cap_init:
```cpp
//调用示例
kvm_cpu_cap_init(CPUID_1_ECX,
        F(XMM3),
        F(PCLMULQDQ),
        VENDOR_F(DTES64),
        /*
         * NOTE: MONITOR (and MWAIT) are emulated as NOP, but *not*
         * advertised to guests via CPUID!  MWAIT is also technically a
         * runtime flag thanks to IA32_MISC_ENABLES; mark it as such so
         * that KVM is aware that it's a known, unadvertised flag.
         */
        RUNTIME_F(MWAIT),
        /* DS-CPL */
        VENDOR_F(VMX),
        /* SMX, EST */
        /* TM2 */
        F(SSSE3),
        /* CNXT-ID */
        /* Reserved */
        F(FMA),
        F(CX16),
        /* xTPR Update */
        F(PDCM),
        F(PCID),
        /* Reserved, DCA */
        F(XMM4_1),
        F(XMM4_2),
        EMULATED_F(X2APIC),
        F(MOVBE),
        F(POPCNT),
        EMULATED_F(TSC_DEADLINE_TIMER),
        F(AES),
        F(XSAVE),
        RUNTIME_F(OSXSAVE),
        F(AVX),
        F(F16C),
        F(RDRAND),
        EMULATED_F(HYPERVISOR),
);
```
具体宏展开:
```cpp
/*
 * For kernel-defined leafs, mask KVM's supported feature set with the kernel's
 * capabilities as well as raw CPUID.  For KVM-defined leafs, consult only raw
 * CPUID, as KVM is the one and only authority (in the kernel).
 */
#define kvm_cpu_cap_init(leaf, feature_initializers...)                 \
do {                                                                    \
        const struct cpuid_reg cpuid = x86_feature_cpuid(leaf * 32);    \
        const u32 __maybe_unused kvm_cpu_cap_init_in_progress = leaf;   \
        const u32 *kernel_cpu_caps = boot_cpu_data.x86_capability;      \
        u32 kvm_cpu_cap_passthrough = 0;                                \
        u32 kvm_cpu_cap_synthesized = 0;                                \
        u32 kvm_cpu_cap_emulated = 0;                                   \
        u32 kvm_cpu_cap_features = 0;                                   \
                                                                        \
        feature_initializers                                            \
                                                                        \
        kvm_cpu_caps[leaf] = kvm_cpu_cap_features;                      \
                                                                        \
        if (leaf < NCAPINTS)                                            \
                kvm_cpu_caps[leaf] &= kernel_cpu_caps[leaf];            \
                                                                        \
        kvm_cpu_caps[leaf] |= kvm_cpu_cap_passthrough;                  \
        kvm_cpu_caps[leaf] &= (raw_cpuid_get(cpuid) |                   \
                               kvm_cpu_cap_synthesized);                \
        kvm_cpu_caps[leaf] |= kvm_cpu_cap_emulated;                     \
} while (0)
/*
 * Assert that the feature bit being declared, e.g. via F(), is in the CPUID
 * word that's being initialized.  Exempt 0x8000_0001.EDX usage of 0x1.EDX
 * features, as AMD duplicated many 0x1.EDX features into 0x8000_0001.EDX.
 */
//先不关注
#define KVM_VALIDATE_CPU_CAP_USAGE(name)                                \
do {                                                                    \
        u32 __leaf = __feature_leaf(X86_FEATURE_##name);                \
                                                                        \
        BUILD_BUG_ON(__leaf != kvm_cpu_cap_init_in_progress);           \
} while (0)

#define F(name)                                                 \
({                                                              \
        KVM_VALIDATE_CPU_CAP_USAGE(name);                       \
        kvm_cpu_cap_features |= feature_bit(name);              \
})

//
/* Scattered Flag - For features that are scattered by cpufeatures.h. */
#define SCATTERED_F(name)                                       \
({                                                              \
        BUILD_BUG_ON(X86_FEATURE_##name >= MAX_CPU_FEATURES);   \
        KVM_VALIDATE_CPU_CAP_USAGE(name);                       \
        if (boot_cpu_has(X86_FEATURE_##name))                   \
                F(name);                                        \
})

/* Features that KVM supports only on 64-bit kernels. */
#define X86_64_F(name)                                          \
({                                                              \
        KVM_VALIDATE_CPU_CAP_USAGE(name);                       \
        if (IS_ENABLED(CONFIG_X86_64))                          \
                F(name);                                        \
})

/*
 * Emulated Feature - For features that KVM emulates in software irrespective
 * of host CPU/kernel support.
 *
 * kvm通过软件模拟的特性
 */
#define EMULATED_F(name)                                        \
({                                                              \
        kvm_cpu_cap_emulated |= feature_bit(name);              \
        F(name);                                                \
})

/*
 * Synthesized Feature - For features that are synthesized into boot_cpu_data,
 * i.e. may not be present in the raw CPUID, but can still be advertised to
 * userspace.  Primarily used for mitigation related feature flags.
 * 
 * 这些features是cpuid中没有的，kernel进行了合成，合成到boot_cpu_data中，方便
 * 报告给用户态.
 *
 * 75c489e12d4b90d8aa5ffb34c3c907ef717fe38e
 *   KVM: x86: Add a macro for features that are synthesized into boot_cpu_data
 */
#define SYNTHESIZED_F(name)                                     \
({                                                              \
        kvm_cpu_cap_synthesized |= feature_bit(name);           \
        F(name);                                                \
})
/*
 * Passthrough Feature - For features that KVM supports based purely on raw
 * hardware CPUID, i.e. that KVM virtualizes even if the host kernel doesn't
 * use the feature.  Simply force set the feature in KVM's capabilities, raw
 * CPUID support will be factored in by kvm_cpu_cap_mask().
 */
/*
 * Passthrough Feature - 即使hosts不支持该feature，但是虚拟机中可以支持,
 * 该接口由LA57 feature引入.
 *
 * 5c8de4b3a5bc4dc6a1a8afd46ff5d58beebb6356
 *   KVM: x86: Add a macro to init CPUID features that ignore host 
 *     kernel support
 */
#define PASSTHROUGH_F(name)                                     \
({                                                              \
        kvm_cpu_cap_passthrough |= feature_bit(name);           \
        F(name);                                                \
})
```

## kvm_cpu_realizefn
```
kvm_cpu_realizefn
```

## 附录
`-cpu host` 参数启动
```
#0  max_x86_cpu_initfn (obj=0x555556701ba0) at ../target/i386/cpu.c:4264
#1  0x0000555555d62cd5 in object_init_with_type (ti=0x5555564d3ed0, obj=0x555556701ba0) at ../qom/object.c:376
#2  object_init_with_type (ti=0x5555564d4230, obj=0x555556701ba0) at ../qom/object.c:372
#3  object_initialize_with_type (obj=obj@entry=0x555556701ba0, size=size@entry=51296, type=type@entry=0x5555564d4230)
    at ../qom/object.c:518
#4  0x0000555555d62ee7 in object_new_with_type (type=0x5555564d4230) at ../qom/object.c:733
#5  0x0000555555d62f89 in object_new (typename=<optimized out>) at ../qom/object.c:748
#6  0x0000555555b9b455 in x86_cpu_new (x86ms=<optimized out>, apic_id=0, errp=0x555556451690 <error_fatal>)
    at ../hw/i386/x86.c:109
#7  0x0000555555b9b56a in x86_cpus_init (x86ms=x86ms@entry=0x5555566e2d20, default_cpu_version=<optimized out>)
    at ../hw/i386/x86.c:141
#8  0x0000555555ba2ac1 in pc_init1
    (machine=0x5555566e2d20, pci_type=0x555555ecc7b8 "i440FX", host_type=0x555555ecc7d7 "i440FX-pcihost")
    at ../hw/i386/pc_piix.c:157
#9  0x0000555555a395b4 in machine_run_board_init (machine=machine@entry=0x5555566e2d20) at ../hw/core/machine.c:1186
#10 0x0000555555c3f5c9 in qemu_init_board () at ../softmmu/vl.c:2656
#11 qmp_x_exit_preconfig (errp=<optimized out>) at ../softmmu/vl.c:2745
#12 0x0000555555c43691 in qmp_x_exit_preconfig (errp=<optimized out>) at ../softmmu/vl.c:2740
#13 qemu_init (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>) at ../softmmu/vl.c:3784
#14 0x000055555593bfb9 in main (argc=<optimized out>, argv=<optimized out>, envp=<optimized out>) at ../softmmu/main.c:50
```
## 参考链接
1. [20.40. Guest Virtual Machine CPU Model Configuration](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-managing_guest_virtual_machines_with_virsh-guest_virtual_machine_cpu_model_configuration)
