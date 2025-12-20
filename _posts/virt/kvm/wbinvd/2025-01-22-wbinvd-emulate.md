---
layout: post
title:  "emulate wbinvd"
author: fuqiang
date:   2025-01-22 13:05:00 +0800
categories: [kvm,wbinvd]
tags: [kvm]
---


## related patch
* KVM: VMX: wbinvd exiting
  + commit
    + e5edaa01c4cea5f60c617fac989c6458df0ecc4e
    + Eddie Dong
    + Sun Nov 11 12:28:35 2007 +0200

* KVM: VMX: Execute WBINVD to keep data consistency with assigned devices
  + commit 
    + f5f48ee15c2ee3e44cf429e34b16c6fa9b900246
    + Sheng Yang
    + Wed Jun 30 12:25:15 2010 +0800
  + [v1](https://lore.kernel.org/all/1277452623-24046-1-git-send-email-sheng@linux.intel.com/)
  + [v2](https://lore.kernel.org/all/1277471336-26059-1-git-send-email-sheng@linux.intel.com/)
  + [v3](https://lore.kernel.org/all/1277696187-3571-1-git-send-email-sheng@linux.intel.com/)
  + [v4](https://lore.kernel.org/all/1277714558-6451-1-git-send-email-sheng@linux.intel.com/)
  + [v5](https://lore.kernel.org/all/1277781419-13227-1-git-send-email-sheng@linux.intel.com/)
  + [v6](https://lore.kernel.org/all/1277871916-8348-1-git-send-email-sheng@linux.intel.com/)
 
* kvm: x86: make kvm_emulate_* consistant
  + commit
    + 5cb56059c94ddfaf92567a1c6443deec8363ae1c
    + Joel Schopp
    + Mon Mar 2 13:43:31 2015 -0600
