---
layout: post
title:  "dirty-rate calc"
author: fuqiang
date:   2024-11-25 11:00:00 +0800
categories: [live_migration, dirty_rate]
tags: [dirty rate]
---
## calc-dirty-rate 整体流程

```sh
qmp_calc_dirty_rate
  => qemu_thread_create(,MIGRATION_THREAD_DIRTY_RATE, get_dirtyrate_thread,,)
     (get_dirtyrate_thread)
     => dirtyrate_set_state(,,DIRTY_RATE_STATUS_MEASURING)
     => calculate_dirtyrate()
        => switch(mode)
           => DIRTY_RATE_MEASURE_MODE_DIRTY_BITMAP
              => calculate_dirtyrate_dirty_bitmap
           => DIRTY_RATE_MEASURE_MODE_DIRTY_RING
              => calculate_dirtyrate_dirty_ring
           => other:
              => calculate_dirtyrate_sample_vm
     => dirtyrate_set_state(,,DIRTY_RATE_STATUS_MEASURED)
```
### dirty_bitmap
```sh
calculate_dirtyrate_dirty_bitmap
## may execute log_start(), may be not
=> memory_global_dirty_log_start(GLOBAL_DIRTY_DIRTY_RATE, )
=> record_dirtypages_bitmap(&dirty_pages ,true)
   => dirty_pages->start_pages = total_dirty_pages;
## get start end
=> start_time = get_clock_get_ms(QEMU_CLOCK_REALTIME)
=> global_dirty_log_sync(GLOBAL_DIRTY_DIRTY_RATE, true);
## WAIT... unit calc_time_ms + start_time expired
=> DirtyStat.calc_time_ms = dirty_stat_wait(config.calc_time_ms, start_time);
## record timeend dirtypages
=> record_dirtypages_bitmap(&dirty_pages, false);
   => dirty_pages->end_pages = total_dirty_pages;
=> do_calculate_dirtyrate
   => (end_pages-start_pages) * 1000 / calc_time_ms

```
### dirty_ring
```sh
calculate_dirtyrate_dirty_ring
=> global_dirty_log_change(GLOBAL_DIRTY_DIRTY_RATE, true);
=> start_time = qemu_clock_get_ms(QEMU_CLOCK_HOST) / 1000;
=> vcpu_calculate_dirtyrate
   => vcpu_dirty_stat_collect(records, true);
      => foreach VCPU
         => record_dirtypages(,true)
            => dirty_pages[cpu->cpu_index].start_pages = cpu->dirty_pages

   ## WAIT... unit calc_time_ms + start_time expired
   => duration = dirty_stat_wait(calc_time_ms, init_time_ms);

   => global_dirty_log_sync(flag, one_shot);
   => vcpu_dirty_stat_collect
      => foreach VCPU
         => record_dirtypages(, false)
             => dirty_pages[cpu->cpu_index].start_pages = cpu->dirty_pages
   => foreach VCPU
      ## 计算每一个vcpu的脏页速率
      => do_calculate_dirtyrate
```
对于`dirty_bitmap`和`dirty_ring`两者统计dirty page number依据不一样:
* dirty_bitmap: total_dirty_pages
* dirty_ring: cpu->dirty_pages

## query_migrate.ram.dirty-pages-rate

```sh
qmp_query_migrate
  => fill_source_migration_info
     => case MIGRATION_STATUS_ACTIVE
        => populate_time_info
        => populate_ram_info
           ...
           => info->ram->dirty_pages_rate = stat64_get(&mig_stats.dirty_pages_rate);
           ...
        => migration_populate_vfio_info
```
依据`mig_stats.dirty_pages_rate`

我们来看几个流程:


## sync log
```sh
global_dirty_log_sync
  => memory_global_dirty_log_sync
  => memory_region_sync_dirty_bitmap
     => foreach memorylistener
        => if listener->log_sync
           => view = address_space_get_flatview()
              => foreach flat range   ## foreach mr
                  => listener->log_sync() ## dirty bitmap
                     (kvm_log_sync)
        => if listener->log_sync_global
           => listener->log_sync_global() ## dirty ring
              (kvm_log_sync_global)
  => if one_shot
     => memory_global_dirty_log_stop(flag)
```

kvm_log_sync:
```sh
kvm_physical_sync_dirty_bitmap
=> kvm_slot_get_dirty_log()
   => kvm_vm_ioctl(s, KVM_GET_DIRTY_LOG, &d);
=> kvm_slot_sync_dirty_pages()
   => cpu_physical_memory_set_dirty_lebitmap()
```