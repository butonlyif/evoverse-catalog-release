[English](README.en.md) | 中文

# ws-e2-rk3588j-minimal 固件基线

RK3588J 最小系统的第一个 **BUILD_READY** 固件包，由 RK3588 Adapter 四阶段交叉编译流水线
（uboot → kernel → rootfs → package）产出，作为后续 RK3588 工程的官方开发基线。

## 包内容

| 产物 | 阶段 | 包内路径 | 说明 |
|------|------|----------|------|
| uboot.img | uboot | `u-boot/uboot.img` | U-Boot 镜像（TPL+SPL 合成） |
| kernel-image | kernel | `kernel/arch/arm64/boot/Image` | Linux 6.1 arm64 内核 |
| board-dtb | kernel | `.evoverse-scratch/dts/rk3588j-evoverse.dtb` | EvoVerse 板级设备树 |
| rootfs.ext2 | rootfs | `.evoverse-scratch/buildroot/images/rootfs.ext2` | Buildroot 根文件系统 |

整体打包为 `ws-e2-rk3588j-minimal-firmware.tar.gz`（17.4 MB），
sha256 与逐产物哈希见同目录 [baseline.yaml](baseline.yaml)。

## 构建身份

- Profile：`ws-e2-rk3588j-minimal-r1`
- BSP：rockchip-linux @ `b8f5dda5`（kernel develop-6.1 / u-boot / rkbin / buildroot）
- 容器：`rk3588-toolchain:2026.09`（aarch64-linux-gnu 交叉工具链）
- 烧录布局：`layouts/ws-e2-minimal-parameter.txt`

## 验证状态

| 状态 | 值 | 说明 |
|------|-----|------|
| build | BUILD_READY | 四阶段全部成功，产物哈希已留痕 |
| program | NOT_RUN | 硬件未到位，未烧录 |
| hardware | NOT_RUN | 硬件未到位，未上板验证 |

## 使用方式

在 SDK 中从 ws-e2 / rk3588j-evm 物料创建 RK3588 工程时，Adapter 默认引用本基线；
也可用 RK3588 Adapter 重新四阶段构建生成新固件。开发流程详见
《RK3588 开发全流程指南》（SDK 文档门户 → RK3588 Adapter）。
