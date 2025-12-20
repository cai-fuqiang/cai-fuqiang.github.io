```
crash> dev -p |grep -E '38:1f.6|38:1f.5'
  ff11017ad11c1000 0000:38:1f.5  0200  1af4:1042  ENDPOINT
  ff11017ad11c5000 0000:38:1f.6  0200  1af4:1042  ENDPOINT
```

## device1
```
crash> struct pci_dev.dev.iommu_group ff11017ad11c1000
  dev.iommu_group = 0xff11017ad1195e00,
crash> struct iommu_group.domain 0xff11017ad1195e00
  domain = 0xff1100bd602a2480,
crash> struct dmar_domain.pgd 0xff1100bd602a2400
      pgd = 0xff1100bf46a56000,
```
## device2
```
crash> struct pci_dev.dev.iommu_group ff11017ad11c5000
  dev.iommu_group = 0xff11017ad1195400,
crash> struct iommu_group.domain 0xff11017ad1195400
  domain = 0xff1100bd602a6c80,
crash> struct dmar_domain.pgd 0xff1100bd602a6c00
      pgd = 0xff1100bfe3ffe000,
```
