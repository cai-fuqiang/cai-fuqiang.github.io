# query-migration-info
```
qmp_query_migrate
  fill_source_migration_info
    populate_ram_info {
      => info->ram->remaining = ram_bytes_remaining();
         => return ram_state ? (ram_state->migration_dirty_pages * TARGET_PAGE_SIZE) :
    }
```

# tracepoint


```
migration_iteration_run
  => qemu_savevm_state_pending_estimate
  => trace_migrate_pending_estimate
  => if (pending_size < s->threshold_size) {
     => qemu_savevm_state_pending_exact(&must_precopy, &can_postcopy);
     => trace_migrate_pending_exact(pending_size, must_precopy, can_postcopy);
migration_update_counters
  => trace_migrate_transferred
```
