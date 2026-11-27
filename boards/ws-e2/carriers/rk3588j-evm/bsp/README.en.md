# ws-e2 RK3588 BSP deliverable (public-source assembly, 2026-11-11)

[中文](README.md) | English

Platform development BSP deliverable for ws-e2 (carrier rk3588j-evm,
RK3588J + 2x LPDDR4X 4GB + eMMC 128GB). Assembled from **authoritative public
repositories** (reproducible), superseding the sealed legacy offline evopkg
(commit b8f5dda5 — identity formally retired; records kept under
platforms/environment/).

## Contents

| Item | Description |
|---|---|
| `manifest.json` | BSP identity and qualification input: root commit, four component commits, loader sha256, partition layout sha256, license decisions, toolchain facts (consumed by the Adapter via the C15 resolution chain) |
| `superproject.bundle` | Superproject (root + 4 submodule gitlinks + board-ws-e2/ board tree + layouts/) |
| `bundles/{kernel,u-boot,buildroot,rkbin}.bundle` | Controlled sources of the four components (git bundle; clone restores full repositories) |
| `loaders/` | Prebuilt firmware, original bytes: rk3588_spl_v1.14.bin (sha256 b811b90b…, byte-identical to the legacy registration), DDR init blob v1.24, BL31 v1.56, BL32 v1.23 + Rockchip LICENSE |
| `layouts/ws-e2-minimal-parameter.txt` | Partition layout (authoritative rkbin/tools/parameter_gpt.txt format; idbloader@0x40, uboot@0x4000, resource@0x6000, boot@0xE000, rootfs grows from 0x16000) |
| `LICENSES.md` | License verification conclusions and redistribution obligations |
| `tree/` (after materialization) | Real source tree rebuilt from the bundles by the Adapter / on-site (one sourceRoot candidate) |

## Identity (measured)

- root commit: see `manifest.json` `rootCommit`
- kernel develop-6.1 @ `77168c8d5` · u-boot next-dev @ `1c535d65` · buildroot
  2026.08.1 @ `7fdeadb3` · rkbin master @ `3e288fe8`

## Rebuild (customer / on-site)

The bundle files themselves ship as **GitHub Release assets** (not in the git
tree; catalog sync does not carry them): download each one per
`manifest.json` `release.urlPattern` and verify against
`bundleFiles[].sha256` before use:

```bash
BASE=https://github.com/butonlyif/evoverse-catalog-release/releases/download/bsp-ws-e2-99a56fe7
for f in superproject.bundle kernel.bundle u-boot.bundle buildroot.bundle rkbin.bundle; do
  curl -LO "$BASE/$f"
done
sha256sum -c   # check against manifest.json bundleFiles
```

```bash
git clone superproject.bundle ws-e2-rk3588-bsp
cd ws-e2-rk3588-bsp
git clone ../kernel.bundle    kernel    && git -C kernel    checkout <pin>
git clone ../u-boot.bundle    u-boot    && git -C u-boot    checkout <pin>
git clone ../buildroot.bundle buildroot && git -C buildroot checkout <pin>
git clone ../rkbin.bundle     rkbin     && git -C rkbin     checkout <pin>
# Verify: git rev-parse HEAD matches manifest.json components
```

(Pins are in manifest.json; the Adapter verifies each item during
materialization.)

## Build entry points

See the superproject `README.md` ("Build entry points" section) and the SDK
doc `docs/rk3588/RK3588-vendor构建契约-u-boot与kernel.md`. Full image:

```bash
make -C buildroot BR2_EXTERNAL=../board-ws-e2 O=<out> ws-e2_rk3588j_defconfig
make -C buildroot BR2_EXTERNAL=../board-ws-e2 O=<out> -j$(nproc)
# Outputs <out>/ws-e2-image/{boot.img,idbloader.img,u-boot.itb,rootfs.ext4,parameter.txt,SHA256SUMS}
```

## Boundaries (honest statement)

- The 2026-11-11 smoke evidence is **compile-level** (kernel Image 6.1.172 +
  77 dtbs; idbloader.img/u-boot.itb; full image per that day's SHA256SUMS) —
  flash/boot/hardware validation NOT_RUN.
- boot.img carries the EVB1-LP4 placeholder DTS (the schematic-derived ws-e2
  DTS is a separate material task); the cmdline root device must be confirmed
  against the real board during bring-up.
- The vendor u-boot `-Werror` × gcc 13.3 compatibility relaxation
  (`KCFLAGS=-Wno-error`) must be recorded in the build receipt.
