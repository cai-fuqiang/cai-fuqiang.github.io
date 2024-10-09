# ftrace log
```
[root@localhost tracing]# cat trace
# tracer: function_graph
#
# CPU  DURATION                  FUNCTION CALLS
# |     |   |                     |   |   |   |
 1) $ 187566289 us |  } /* schedule */
 ------------------------------------------
 1)   ksoftir-18   => qemu-kv-17653
 ------------------------------------------

 1)   0.507 us    |  vfio_fops_unl_ioctl [vfio]();
 1)               |  vfio_fops_unl_ioctl [vfio]() {
 1)               |    vfio_ioctl_check_extension [vfio]() {
 1)               |      down_read() {
 1)               |        _cond_resched() {
 1)   0.055 us    |          rcu_all_qs();
 1)   0.499 us    |        }
 1)   0.899 us    |      }
 1)               |      mutex_lock() {
 1)               |        _cond_resched() {
 1)   0.059 us    |          rcu_all_qs();
 1)   0.451 us    |        }
 1)   0.819 us    |      }
 1)   0.127 us    |      try_module_get();
 1)   0.232 us    |      vfio_iommu_type1_ioctl [vfio_iommu_type1]();
 1)   0.051 us    |      module_put();
 1)   0.038 us    |      mutex_unlock();
 1)   0.035 us    |      up_read();
 1)   5.143 us    |    }
 1)   5.510 us    |  }
 1)               |  vfio_fops_unl_ioctl [vfio]() {
 1)               |    down_write() {
 1)               |      _cond_resched() {
 1)   0.066 us    |        rcu_all_qs();
 1)   0.342 us    |      }
 1)   0.597 us    |    }
 1)               |    mutex_lock() {
 1)               |      _cond_resched() {
 1)   0.036 us    |        rcu_all_qs();
 1)   0.274 us    |      }
 1)   0.519 us    |    }
 1)   0.045 us    |    try_module_get();
 1)   0.070 us    |    vfio_iommu_type1_ioctl [vfio_iommu_type1]();
 1)               |    vfio_iommu_type1_open [vfio_iommu_type1]() {
 1)               |      kmem_cache_alloc_trace() {
 1)               |        _cond_resched() {
 1)   0.035 us    |          rcu_all_qs();
 1)   0.274 us    |        }
 1)   0.034 us    |        should_failslab();
 1)               |        __slab_alloc() {
 1)   0.318 us    |          ___slab_alloc();
 1)   0.572 us    |        }
 1)   1.676 us    |      }
 1)   0.036 us    |      __mutex_init();
 1)   0.037 us    |      __init_rwsem();
 1)   2.469 us    |    }
 1)               |    vfio_iommu_type1_attach_group [vfio_iommu_type1]() {
 1)               |      mutex_lock() {
 1)               |        _cond_resched() {
 1)   0.035 us    |          rcu_all_qs();
 1)   0.272 us    |        }
 1)   0.509 us    |      }
 1)               |      kmem_cache_alloc_trace() {
 1)               |        _cond_resched() {
 1)   0.036 us    |          rcu_all_qs();
 1)   0.268 us    |        }
 1)   0.034 us    |        should_failslab();
 1)   0.827 us    |      }
 1)               |      kmem_cache_alloc_trace() {
 1)               |        _cond_resched() {
 1)   0.035 us    |          rcu_all_qs();
 1)   0.271 us    |        }
 1)   0.035 us    |        should_failslab();
 1)   0.919 us    |      }
 1)               |      iommu_group_for_each_dev() {
 1)               |        mutex_lock() {
 1)   0.059 us    |          _cond_resched();
 1)   0.304 us    |        }
 1)   0.043 us    |        vfio_bus_type [vfio_iommu_type1]();
 1)   0.039 us    |        mutex_unlock();
 1)   1.150 us    |      }
 1)               |      __symbol_get() {
 1)               |        find_symbol() {
 1) + 37.680 us   |          each_symbol_section();
 1) + 38.174 us   |        }
 1) + 38.465 us   |      }
 1)               |      iommu_domain_alloc() {
 1)               |        intel_iommu_domain_alloc() {
 1)   4.302 us    |          alloc_domain();
 1)   1.325 us    |          md_domain_init.constprop.72();
 1)   6.293 us    |        }
 1)   6.910 us    |      }
 1)               |      vfio_iommu_attach_group.isra.16 [vfio_iommu_type1]() {
 1)               |        iommu_attach_group() {
 1)   0.158 us    |          mutex_lock();
 1) ! 205.433 us  |          __iommu_attach_group();
 1)   0.077 us    |          mutex_unlock();
 1) ! 207.127 us  |        }
 1) ! 207.793 us  |      }
 1)   0.046 us    |      iommu_domain_get_attr();
 1)               |      iommu_get_group_resv_regions() {
 1)               |        mutex_lock() {
 1)   0.101 us    |          _cond_resched();
 1)   0.413 us    |        }
 1)               |        intel_iommu_get_resv_regions() {
 1)   0.129 us    |          down_read();
 1)   0.043 us    |          up_read();
 1)   0.294 us    |          iommu_alloc_resv_region();
 1)   1.382 us    |        }
 1)               |        iommu_alloc_resv_region() {
 1)   0.678 us    |          kmem_cache_alloc_trace();
 1)   0.997 us    |        }
 1)               |        generic_iommu_put_resv_regions() {
 1)   0.413 us    |          kfree();
 1)   0.726 us    |        }
 1)   0.043 us    |        mutex_unlock();
 1)   5.202 us    |      }
 1)   0.048 us    |      vfio_iommu_iova_get_copy [vfio_iommu_type1]();
 1)               |      vfio_iommu_aper_resize [vfio_iommu_type1]() {
 1)               |        vfio_iommu_iova_insert [vfio_iommu_type1]() {
 1)   0.166 us    |          kmem_cache_alloc_trace();
 1)   0.476 us    |        }
 1)   0.783 us    |      }
 1)               |      vfio_iommu_resv_exclude [vfio_iommu_type1]() {
 1)               |        vfio_iommu_iova_insert [vfio_iommu_type1]() {
 1)   0.160 us    |          kmem_cache_alloc_trace();
 1)   0.466 us    |        }
 1)               |        vfio_iommu_iova_insert [vfio_iommu_type1]() {
 1)   0.160 us    |          kmem_cache_alloc_trace();
 1)   0.465 us    |        }
 1)   0.139 us    |        kfree();
 1)   1.934 us    |      }
 1)               |      irq_domain_check_msi_remap() {
 1)               |        mutex_lock() {
 1)   0.076 us    |          _cond_resched();
 1)   0.445 us    |        }
 1)   0.042 us    |        mutex_unlock();
 1)   1.449 us    |      }
 1)               |      iommu_capable() {
 1)   0.101 us    |        intel_iommu_capable();
 1)   0.432 us    |      }
 1)               |      printk() {                        -------> ?????????????? 我天
 1)               |        vprintk_func() {
 1) # 1969.479 us |          vprintk_default();
 1) # 1970.068 us |        }
 1) # 1970.461 us |      }
 1)               |      vfio_iommu_detach_group.isra.13 [vfio_iommu_type1]() {
 1)               |        iommu_detach_group() {
 1)   0.132 us    |          mutex_lock();
 1) ! 423.511 us  |          __iommu_detach_group();
 1)   0.063 us    |          mutex_unlock();
 1) ! 424.736 us  |        }
 1) ! 425.040 us  |      }
 1)               |      iommu_domain_free() {
 1)               |        intel_iommu_domain_free() {
 1)   1.383 us    |          domain_exit();
 1)   1.636 us    |        }
 1)   1.924 us    |      }
 1)               |      vfio_iommu_iova_free [vfio_iommu_type1]() {
 1)   0.070 us    |        kfree();
 1)   0.048 us    |        kfree();
 1)   0.649 us    |      }
 1)               |      vfio_iommu_resv_free [vfio_iommu_type1]() {
 1)   0.065 us    |        kfree();
 1)   0.321 us    |      }
 1)               |      kfree() {
 1)   0.055 us    |        __slab_free();
 1)   0.325 us    |      }
 1)   0.057 us    |      kfree();
 1)   0.046 us    |      mutex_unlock();
 1) # 2672.235 us |    }
 1)               |    vfio_iommu_type1_release [vfio_iommu_type1]() {
 1)   0.040 us    |      vfio_iommu_unmap_unpin_all [vfio_iommu_type1]();
 1)   0.044 us    |      vfio_iommu_iova_free [vfio_iommu_type1]();
 1)   0.067 us    |      kfree();
 1)   1.367 us    |    }
 1)   0.047 us    |    module_put();
 1)   0.044 us    |    mutex_unlock();
 1)   0.039 us    |    up_write();
 1) # 2680.276 us |  }
[root@localhost tracing]#
```

# printk
```
[ 4113.264693] vfio_iommu_type1_attach_group: No interrupt remapping support.  Use the module param "allow_unsafe_interrupts" to enable VFIO IOMMU support on this platform
```
