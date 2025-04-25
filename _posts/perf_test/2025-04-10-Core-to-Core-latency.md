---
layout: post
title:  "[perftest] core-to-core-latency"
author: fuqiang
date:   2025-04-09 11:50:00 +0800
categories: [perftest]
tags: [perftest, core-to-core-latency]
---

## 使用方法
```
core-to-core-latency

USAGE:
    core-to-core-latency [OPTIONS] [ARGS]

ARGS:
    <NUM_ITERATIONS>    The number of iterations per sample [default: 1000]
    <NUM_SAMPLES>       The number of samples [default: 300]

OPTIONS:
    -b, --bench <BENCH>    Select which benchmark to run, in a comma delimited list, e.g., '1,3'
                            1: CAS latency on a single shared cache line.
                            2: Single-writer single-reader latency on two shared cache lines.
                            3: One writer and one reader on many cache line, using the clock.
                            [default: 1]
    -c, --cores <CORES>    Specify the cores by id that should be used, comma delimited. By default
                           all cores are used
        --csv              Outputs the mean latencies in CSV format on stdout
    -h, --help             Print help information
```

* **_-b_**: bench 的类型
  1. cas: CAS -- compare and swap, 通过atomic swap 测试shared cache line 延迟
      (下面会介绍代码细节)
  2. single-write single-reader latency:
  3. one writer and one reader on many cache line: 

  默认采用1:cas

* **_-c_**: 指定要测试的核心，默认测量所有核心
* **_--csv_**: 将测量结果以csv格式输出.

## 代码细节

(由于对rust不了解，这里大概展示下，三个bench的相关代码)

### CAS
```rust
impl super::Bench for Bench {
    // The two threads modify the same cacheline.
    // This is useful to benchmark spinlock performance.

    // NOTE
    // 两个threads修改同一个cacheliine
    //
    //- thread 1: pong thread
    //  - swap(PING->PONG)
    //- thread 2: ping thread
    //  - swap(PONG->PING)
    //  - test duration of (PING->PONG->PING) time and 
    //     record result
    fn run(
        &self,
        (ping_core, pong_core): (CoreId, CoreId),
        clock: &Clock,
        num_round_trips: Count,
        num_samples: Count,
    ) -> Vec<f64> {
        let state = self;

        crossbeam_utils::thread::scope(|s| {
            //创建pong线程
            let pong = s.spawn(move |_| {
                core_affinity::set_for_current(pong_core);
                //等待ping线程到达该点
                state.barrier.wait();
                //一共测量num_round_trips * num_samples
                // num_samples: 表示进行几组测试
                // num_round_trips: 表示每一组测试ping->pong->ping
                //                  的次数
                for _ in 0..(num_round_trips*num_samples) {
                    while state.flag.compare_exchange(PING, PONG, 
                      Ordering::Relaxed, Ordering::Relaxed).is_err() {}
                }
            });
            //创建ping线程
            let ping = s.spawn(move |_| {
                core_affinity::set_for_current(ping_core);

                let mut results = Vec::with_capacity(num_samples as usize);
                //等到pong线程达到该点
                state.barrier.wait();
                //采集 num_samples 数据
                for _ in 0..num_samples {
                    let start = clock.raw();
                    //测量num_round_trips 组数据
                    for _ in 0..num_round_trips {
                        while state.flag.compare_exchange(PONG, PING, 
                          Ordering::Relaxed, Ordering::Relaxed).is_err() {}
                    }
                    //计算一组测试的时间差
                    let end = clock.raw();
                    let duration = clock.delta(start, end).as_nanos();
                    //获取每次内存访问的延迟, 由于测量的是PING->PONG->PING，中间
                    //执行了两次内存操作, 所这里要/2, 获取每次内存访问的延迟
                    results.push(duration as f64 / num_round_trips as f64 / 2.0);
                }

                results
            });

            pong.join().unwrap();
            ping.join().unwrap()
        }).unwrap()
    }
}
```
