English | [中文](README.md)

# ws-e2-rk3588j-minimal Firmware Baseline

The first **BUILD_READY** firmware package for the RK3588J minimal system, produced by the RK3588
Adapter four-stage cross-compilation pipeline (uboot → kernel → rootfs → package). It serves as the
official development baseline for subsequent RK3588 projects.

## Package Contents

| Artifact | Stage | Path in package | Description |
|------|------|----------|------|
| uboot.img | uboot | `u-boot/uboot.img` | U-Boot image (TPL+SPL composite) |
| kernel-image | kernel | `kernel/arch/arm64/boot/Image` | Linux 6.1 arm64 kernel |
| board-dtb | kernel | `.evoverse-scratch/dts/rk3588j-evoverse.dtb` | EvoVerse board device tree |
| rootfs.ext2 | rootfs | `.evoverse-scratch/buildroot/images/rootfs.ext2` | Buildroot root filesystem |

Packaged as `ws-e2-rk3588j-minimal-firmware.tar.gz` (17.4 MB);
the overall sha256 and per-artifact hashes are in [baseline.yaml](baseline.yaml) in the same directory.

## Build Identity

- Profile: `ws-e2-rk3588j-minimal-r1`
- BSP: rockchip-linux @ `b8f5dda5` (kernel develop-6.1 / u-boot / rkbin / buildroot)
- Container: `rk3588-toolchain:2026.09` (aarch64-linux-gnu cross toolchain)
- Flash layout: `layouts/ws-e2-minimal-parameter.txt`

## Verification Status

| Status | Value | Description |
|------|-----|------|
| build | BUILD_READY | All four stages succeeded, artifact hashes recorded |
| program | NOT_RUN | Hardware not available; not flashed |
| hardware | NOT_RUN | Hardware not available; not validated on board |

## Usage

When creating an RK3588 project from ws-e2 / rk3588j-evm materials in the SDK, the Adapter references
this baseline by default; you can also rebuild a new firmware with the RK3588 Adapter's four-stage
pipeline. For the full development workflow see the RK3588 Development Guide
(SDK documentation portal → RK3588 Adapter).
