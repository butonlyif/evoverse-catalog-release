# ws-e2 BSP 交付物许可清单（LICENSES）

[English](LICENSES.en.md) | 中文

本目录 BSP 材料由四组上游组件组装而成，按下列许可随 catalog 公开分发（核实日 2026-11-11）。

| 组件 | 许可 | 再分发 | 义务 |
|---|---|---|---|
| kernel（rockchip-linux develop-6.1） | GPL-2.0（COPYING） | 允许 | 随附源码（本目录 bundle 即源码）、保留 LICENSE |
| u-boot（rockchip-linux next-dev） | GPL-2.0（Licenses/README） | 允许 | 同上 |
| buildroot（官方 tag 2026.08.1） | GPL-2.0+（COPYING） | 允许 | 同上 |
| rkbin 预编译固件（loaders/） | Rockchip 专有许可（loaders/LICENSE） | **明文授予**（原文："hereby grants … to use, copy, distribute the Software"） | 不得反编译/逆向；保留版权与声明（原字节分发即满足）；按 AS IS 条款传递，不得附加担保声称 |
| mkbootimg.py（board-ws-e2 内 vendor 的构建脚本） | Apache-2.0（The Android Open Source Project，文件头原文随附） | 允许 | 保留 LICENSE 声明与 NOTICE（文件头部已含） |

本目录中 EvoVerse 自有产物（manifest.json、layouts/ws-e2-minimal-parameter.txt、
board-ws-e2/ 板级支持、LICENSES.md、README.md）不包含 Rockchip/Linux 上游代码，
随 catalog 仓库自身许可证分发。

注意事项：

- loaders/ 内文件是 Rockchip electronics 发布的预编译二进制（SPL/DDR init/BL31/BL32），
  按 rkbin LICENSE 原文随附分发；不要修改、重打包或剥离声明。
- GPL 组件的对应源码即本目录各 `.bundle`（git bundle，可 clone 为完整仓库）；
  交付时不剥离 LICENSE/COPYING 文件。
- 若客户对 Rockchip 固件有独立商务授权需求，应直接与 SoC 供应商确认——本清单
  只覆盖「按 rkbin 公开 LICENSE 再分发」这一事实。
