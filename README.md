# EvoVerse Catalog（客户发布版）

[English](README.en.md) | 中文

本仓库是 EvoVerse SDK 的版本化设计物料库：为工程生成提供**硬件物理边界**（器件管脚权威库、板卡管脚表与 bank 电压约束）与**经过验证的参考设计**（stage-0 骨架、demo 工程、可复用 IP）。

发布树只包含 SDK 消费的物料资产；开发环境（校验脚本、schema、测试、CI、迁移账本）保留在内部开发分支，不随本库分发。

文档采用中英双语并存：`X.md` 为中文原件，`X.en.md` 为同目录英文姊妹文件，文件顶部互链。

## 目录结构

```text
catalog/
├── catalog.yaml        # 版本清单：catalogVersion、releaseTag、treeDigest、item 台账
├── boards/             # 板卡资产（board → carrier → jacket 三层模型）
│   ├── t20f256-xd-ps-eval/   # 独立板：Trion T20F256（jackets: stage0、marquee）
│   ├── ws-e1/                # 模块板：Titanium TJ180A484S + 载板 ws-e1-base
│   │   └── carriers/ws-e1-base/  # jackets、10 个 demo、9 个载板级 IP
│   ├── ws-e2/                # 模块板：RK3588J EVM + FPGA 载板（含 offline 环境与 baselines）
│   └── ws-e3/                # 独立板：Titanium TJ375N484X（jacket: stage0）
├── devices/            # 器件管脚权威库（*.authority.json：per-pin name/bank/voltage_domain/functions/reserved_for）
└── ips/                # 全局可复用 IP（协议桥、FIFO、复位同步、视频时序/图案等，含 RTL 与文档）
```

## 板卡层级模型

- **board**：一块物理板卡的权威定义，含管脚表（pinout）与 bank 电压约束。
- **carrier**：模块板（如 ws-e1、ws-e2）插接的扩展载板，补齐扩展外设的管脚映射；独立板无此层。
- **jacket**：叠加在板卡或载板之上的具体设计交付物（RTL、约束、工程说明）。
- **demo**：挂在载板下的完整演示工程，面向某一硬件场景。

SDK 生成工程时以 `devices/*.authority.json` 与板卡 pinout 为物理边界：任何超出权威库的管脚分配、电压域冲突或保留脚占用都会被拒绝。

## 获取与校验

```bash
git fetch origin tag catalog-v0.9.6
git checkout catalog-v0.9.6
```

`catalog.yaml` 中的 `treeDigest` 是对全部物料内容（boards/、devices/、ips/）的 SHA-256 内容指纹。EvoVerse SDK 在 catalog sync 时自动校验该指纹，任何篡改或缺失都会导致同步失败。手动校验可用 SDK 附带的 catalog 校验器执行。

## 版本契约

- `catalogVersion`：物料库版本，与发布 tag `catalog-v<catalogVersion>` 一一对应。
- `minimumSdkVersion`：消费本库所需的最低 SDK 版本。
- `channel`：`stable`（已验证）或 `preview`。

## 许可

本库内容以 `LicenseRef-EvoVerse-Catalog` 标识授权，仅供获得 EvoVerse 授权的客户在 EvoVerse SDK 工作流内使用。
