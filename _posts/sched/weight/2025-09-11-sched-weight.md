---
layout: post
title:  "schedule: weight"
author: fuqiang
date:   2025-09-11 22:16:00 +0800
categories: [schedule]
tags: [sched]
math: true
---

## weight 计算公式

Linux weight 和 nice 有一个对应关系, 具体的公式为:
```
x为nice
y为weight
```

$$
\begin{align}
NICE_0\_weigth = 1024 , x \in [-20,19] \\
f(x) =  NICE_0\_weight * \frac{1}{1.25^x}
\end{align}
$$

在kernel 代码中静态保存这个关系的数组:
```cpp
/*
 * Nice levels are multiplicative, with a gentle 10% change for every
 * nice level changed. I.e. when a CPU-bound task goes from nice 0 to
 * nice 1, it will get ~10% less CPU time than another CPU-bound task
 * that remained on nice 0.
 *
 * The "10% effect" is relative and cumulative: from _any_ nice level,
 * if you go up 1 level, it's -10% CPU usage, if you go down 1 level
 * it's +10% CPU usage. (to achieve that we use a multiplier of 1.25.
 * If a task goes up by ~10% and another task goes down by ~10% then
 * the relative distance between them is ~25%.)
 */
const int sched_prio_to_weight[40] = {
 /* -20 */     88761,     71755,     56483,     46273,     36291,
 /* -15 */     29154,     23254,     18705,     14949,     11916,
 /* -10 */      9548,      7620,      6100,      4904,      3906,
 /*  -5 */      3121,      2501,      1991,      1586,      1277,
 /*   0 */      1024,       820,       655,       526,       423,
 /*   5 */       335,       272,       215,       172,       137,
 /*  10 */       110,        87,        70,        56,        45,
 /*  15 */        36,        29,        23,        18,        15,
};
```

注释中提到, nice每增长1，cpu usage 减少 -10%. 每减少1，cpu usage增加
10%，然后一个增长10%一个增加10%，之间的距离大概是25%。有点抽象。我们
通过下面方式证明下:

## 对公式求导
求导过程如下:

$$
\begin{align}
\frac{d}{dx}[lg{y}] &= \frac{d}{dy}[lg{y}] * \frac{dy}{dx} \\
& = \frac{d}{dy}[\frac{ln{y}}{ln{10}}] * \frac{dy}{dx} \\
&= \frac{1}{y ln{10}} * \frac{dy}{dx} \\
&= \frac{1}{y * ln{10}} * (-y * ln{1.25}) \\
&= - \frac{ln{1.25}}{ln{10}} \\
&\approx -0.096 \\
&\approx -0.1 \\
\end{align}
$$

![weight_nice_math_fig](pic/weight_nice_math_fig.png)

结合这个图可以看到，x每增长100, y大概下降10倍, 那x每增长1, y大概下降0.1
