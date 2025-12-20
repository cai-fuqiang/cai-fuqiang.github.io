---
layout: post
title:  "[arm] virtCCA"
author: fuqiang
date:   2025-08-25 14:55:00 +0800
categories: [coco,virtCCA]
tags: [virtCCA]
---

## ABSTRACT

ARM recently introduced the Confidential Compute Architecture (CCA) as part of
the upcoming ARMv9-A architecture. CCA enables the support of confidential
virtual machines (cVMs) within a separate world called the Realm world,
providing protection from the untrusted normal world. While CCA offers a
promising future for confidential computing, the widespread availability of CCA
hardware is not expected in the near future, according to ARM’s roadmap. To
address this gap, we present virtCCA, an architecture that facilitates
virtualized CCA using TrustZone, a mature hardware feature available on existing
ARM platforms. Notably, virtCCA can be implemented on platforms equipped with
the Secure EL2 (S-EL2) extension available from ARMv8.4 onwards, as well as on
earlier platforms that lack S-EL2 support. virtCCA is fully compatible with the
CCA specifications at the API level. We have developed the entire CCA software
and firmware stack on top of virtCCA, including the enhancements to the normal
world’s KVM to support cVMs, and the TrustZone Management Monitor (TMM) that
enforces isolation among cVMs and provides cVM lifecycle management. We have
implemented virtCCA on real ARM servers, with and without S-EL2 support. Our
evaluation, conducted on micro-benchmarks and macro-benchmarks, demonstrates
that the overhead of running cVMs is acceptable compared to running normal-world
VMs. Specifically, in a set of real-world workloads, the overhead of
virtCCA-SEL2 is less than 29.5% for I/O intensive workloads, while virtCCA-EL3
outperforms the baseline in most cases.

**ACM Reference Format:**

Xiangyi Xu, Wenhao Wang B, Yongzheng Wu, Chenyu Wang, Huifeng Zhu, Haocheng Ma,
Zhennan Min, Zixuan Pang, Rui Hou, and Yier Jin B.
2024. virtCCA: Virtualized Arm Confidential Compute Architecture with TrustZone.

In Proceedings of ACM Conference (Conference’17). ACM, New York, NY, USA, 12
pages. https://doi.org/10.1145/nnnnnnn.nnnnnnn

## 1 INTRODUCTION

Confidential computing is rapidly emerging as an indispensable technology in the
realm of cloud computing. Its primary objective is to safeguard the sensitive
information of tenants from potential risks posed by untrustworthy or improperly
configured cloud service providers (CSPs). This paradigm shift towards
confidential computing not only enhances data privacy and security but also
instills a greater sense of trust in cloud-based services. As a result, it is
increasingly becoming an integral part of modern cloud architectures.
Recognizing the significance of confidential computing, leading chip companies
have stepped forward to offer support for trusted execution environments (TEEs)
within their product offerings. For instance, Intel’s SGX [3] and TDX [19], AMD’
s SEV [34], and IBM’s PEF [18] are all dedicated features that enables the
creation of isolated regions (i.e., enclaves) and confidential virtual machines
(i.e., cVMs) exclusively used by tenants

ARM processors have gained widespread popularity in mobile devices like
smartphones due to their energy efficiency and low power consumption. Notably,
ARM was one of the pioneers in supporting TEEs, i.e., TrustZone, to ensure the
protection of sensitive data like passwords and fingerprints. TrustZone divides
the system into two distinct worlds: the normal world and the secure world.
While the normal world runs the feature-rich operating system (OS), the secure
world handles critical operations requiring enhanced security measures. To cater
to the specific requirements of the secure world, customized trusted OSes like
OPTEE [30] and iTrustee [2] have been developed. These tailored trusted OSes
ensure the provision of secure and reliable services within the secure world.
However, unlike AMD SEV, TrustZone does not fully support the cloud computing
scenario, particularly in supporting a full-featured OS like Linux running
inside cVMs, while the lifecycle of cVMs is managed by the host hypervisor (e.g.,
KVM).

In recent years, ARM has made significant strides in the cloud computing market.
To meet the need for confidential cloud computing, ARM has announced the
Confidential Computing Architecture (CCA), a series of hardware and software
architecture innovations available as part of the ARMv9-A architecture. CCA
supports the dynamic creation and management of Realms (ARM’s terminology for
cVMs), opening confidential computing to all developers and various workloads.

**Motivations.** As ARM’s latest innovation for confidential computing, CCA
points to a convincing future for confidential computing. However, CCA
specifications have still been under active evolution recently. Moreover, it
usually takes years before the commodity chip is shipped, even after the
hardware specifications become stable. It is expected that commercial products
with full CCA support will not be widely available in the near future. On the
other hand, we spot that the CCA software supports, including the cVM guest
kernel, KVM, and Realm Management Monitor (RMM), are evolving at a rapid pace [5,
7, 8]. Unfortunately, these tremendous efforts and innovations are unlikely to
come in handy until real CCA hardware platforms are available in the market.


