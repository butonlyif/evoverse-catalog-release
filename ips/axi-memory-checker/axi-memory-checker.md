---
EvoVerse_manifest_version: 1
kind: ip
id: axi-memory-checker
display_name: AXI Memory Checker
version: 1.0.0
maintainer: EvoVerse
license: proprietary
description: "AXI bus master BFM that writes test patterns to memory then reads back and verifies, reporting mismatches"
---

[English](axi-memory-checker.en.md) | 中文

# AXI Memory Checker

## 来源
从以下 demo 工程提取：
- DDR_TEST

> 注：SI5338 demo 中未找到独立的 memory_checker / apb3_slave / timer_start 源文件（仅含 SoC 网表），故仅提取 DDR_TEST 版本。

## 文件
- `rtl/memory_checker.v` — AXI 存储器校验器（来自 DDR_TEST）

## 接口
| 信号 | 方向 | 说明 |
|------|------|------|
| `axi_clk` / `rstn` | input | 时钟 / 低有效复位 |
| `start` | input | 启动检测 |
| `aw*` / `w*` / `b*` | AXI 写通道 | AWADDR / WDATA(512-bit) / BRESP 等 |
| `ar*` / `r*` | AXI 读通道 | ARADDR / RDATA(512-bit) / RRESP 等 |
| `fail` / `done` | output | 校验失败 / 完成标志 |
| `rdata_obs` / `rdata_exp` | output | 实际读出 / 期望数据 |

## 参数
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `ALEN` | `5` | AXI burst 长度 |
| `ASIZE` | `6` | AXI burst 大小（每拍字节数的 log2） |
| `START_ADDR` | `33'h000000000` | 起始地址 |
| `STOP_ADDR` | `33'h000001900` | 结束地址 |

## 使用示例
- DDR_TEST — DDR 存储器读写校验与压力测试
