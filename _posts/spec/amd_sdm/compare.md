## intel VS amd

### intercept
|feature|intel|amd|
|---|---|---|
|op MSR|||
|IO|+|+|
|instruction|+|+|
|-RDTSC|+|+|
|-PAUSE|+|+|
|interrupt||
|NMI|+|+|
|exception|+|+|


### memory

|feature|intel|amd|
|---|---|---|
|nested page table|+|+|
|TLB ASID|+|+|
|TLB invalid one ASID|+|+|
|PML|+|-|

### Timer
|feature|intel|amd|
|---|---|---|
|VMX-Preemption|+|-|

### interrupt
|feature|intel|amd|
|---|---|---|
|event inject|+|+|
|v CR8/TPR|+|+|
|virtual interrupt|+|+|
|vapic|+|+|
|posted interrupt|+|+|
|vIPI|+|+|
|vNMI|+|+|
|v2xapic|+|+|
|window-exit|+|-|
|vTIMER|+|-|
|v user intr|+|-|
