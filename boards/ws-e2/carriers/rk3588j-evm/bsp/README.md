# ws-e2 RK3588 BSP 交付物（公开源组装，2026-11-11）

[English](README.en.md) | 中文

ws-e2（carrier rk3588j-evm，RK3588J + 2x LPDDR4X 4GB + eMMC 128GB）的平台开发
BSP 交付物。以**权威公开仓库**组装（可复现），取代已封存的 legacy 离线 evopkg
（commit b8f5dda5，身份正式作废、记录保留于 platforms/environment/）。

## 目录内容

| 项 | 说明 |
|---|---|
| `manifest.json` | BSP 身份与资格输入：root commit、四组件 commit、loader sha、分区表 sha、许可决策、toolchain 事实（Adapter 按 C15 修复链消费） |
| `superproject.bundle` | 超级工程（root + 4 个 submodule gitlink + board-ws-e2/ 板级树 + layouts/） |
| `bundles/{kernel,u-boot,buildroot,rkbin}.bundle` | 四组件受控源码（git bundle，clone 即完整仓库） |
| `loaders/` | 预编译固件原字节：rk3588_spl_v1.14.bin（sha256 b811b90b…，与 legacy 登记值逐字节一致）、DDR init blob v1.24、BL31 v1.56、BL32 v1.23 + Rockchip LICENSE |
| `layouts/ws-e2-minimal-parameter.txt` | 分区表（rkbin/tools/parameter_gpt.txt 权威格式；idbloader@0x40、uboot@0x4000、resource@0x6000、boot@0xE000、rootfs 自 0x16000 grow） |
| `LICENSES.md` | 许可核实结论与分发义务 |
| `tree/`（物化后） | Adapter/现场从 bundle 重建的真实源码树（sourceRoot 候选之一） |

## 身份（实测）

- root commit：见 manifest.json `rootCommit`
- kernel develop-6.1 @ `77168c8d5` · u-boot next-dev @ `1c535d65` · buildroot 2026.08.1 @ `7fdeadb3` · rkbin master @ `3e288fe8`

## 重建（客户侧 / 现场）

bundle 文件本体走 **GitHub Release 附件**（不在 git 树内，catalog sync 不携带）：
按 `manifest.json` 的 `release.urlPattern` 逐个下载，与 `bundleFiles[].sha256`
逐一比对后再使用：

```bash
BASE=https://github.com/butonlyif/evoverse-catalog-release/releases/download/bsp-ws-e2-99a56fe7
for f in superproject.bundle kernel.bundle u-boot.bundle buildroot.bundle rkbin.bundle; do
  curl -LO "$BASE/$f"
done
sha256sum -c   # 对照 manifest.json bundleFiles
```

```bash
git clone superproject.bundle ws-e2-rk3588-bsp
cd ws-e2-rk3588-bsp
git clone ../kernel.bundle    kernel    && git -C kernel    checkout <pin>
git clone ../u-boot.bundle    u-boot    && git -C u-boot    checkout <pin>
git clone ../buildroot.bundle buildroot && git -C buildroot checkout <pin>
git clone ../rkbin.bundle     rkbin     && git -C rkbin     checkout <pin>
# 核对：git rev-parse HEAD 与 manifest.json components 一致
```

（pins 见 manifest.json；Adapter 物化时应逐项校验。）

## 构建入口

见超级工程内 `README.md`（「Build entry points」节）与 SDK 侧
`docs/rk3588/RK3588-vendor构建契约-u-boot与kernel.md`。完整镜像：

```bash
make -C buildroot BR2_EXTERNAL=../board-ws-e2 O=<out> ws-e2_rk3588j_defconfig
make -C buildroot BR2_EXTERNAL=../board-ws-e2 O=<out> -j$(nproc)
# 产出 <out>/ws-e2-image/{boot.img,idbloader.img,u-boot.itb,rootfs.ext4,parameter.txt,SHA256SUMS}
```

## 边界（诚实声明）

- 2026-11-11 冒烟证据为 **compile-level**（kernel Image 6.1.172 + 77 dtbs；
  idbloader.img/u-boot.itb；完整镜像见当日 SHA256SUMS）——烧录/启动/硬件验证 NOT_RUN。
- boot.img 的 DTS 为 EVB1-LP4 占位（schematic 派生的 ws-e2 DTS 为独立物料任务）；
  cmdline root 设备须在 bring-up 时按实板确认。
- vendor u-boot 树 -Werror 与 gcc 13.3 的兼容放宽（`KCFLAGS=-Wno-error`）必须记入构建收据。
