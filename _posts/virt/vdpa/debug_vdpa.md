## libvirt xml
```
      <source type='unix' path='/export/libvirt/instances/vm/i-ddqksvroam/vfblk-0000:37:00.1.sock' mode='server'/>
      <source type='unix' path='/export/libvirt/instances/vm/i-ddqksvroam/vfnet-0000:36:14.3.sock' mode='server'/>

```

## crash
```
  ff11017596ad4000 0000:36:14.3  0200  1af4:1041  ENDPOINT ## blk
  ff110175968e1000 0000:37:00.1  0200  1af4:1042  ENDPOINT ## net
```

## blk
```
crash> struct pci_dev.dev.iommu_group ff11017596ad4000
  dev.iommu_group = 0xff11017596993600,

crash> struct iommu_group.domain 0xff11017596993600
  domain = 0xff11017d7d4f0c80,
crash> struct dmar_domain.domain -o
struct dmar_domain {
  [128] struct iommu_domain domain;
}
crash> struct dmar_domain.pgd 0xff11017d7d4f0c00
      pgd = 0xff1100c08fa51000,
```

## net
```
crash> struct pci_dev.dev.iommu_group ff110175968e1000
  dev.iommu_group = 0xff11017596b05c00,
crash> struct iommu_group.domain 0xff11017596b05c00
  domain = 0xff1100ba5774c080,
crash> struct dmar_domain.pgd 0xff1100ba5774c000
      pgd = 0xff11017fb876e000,
```
