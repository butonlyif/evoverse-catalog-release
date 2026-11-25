# ws-e2 BSP deliverable license inventory (LICENSES)

[中文](LICENSES.md) | English

The BSP material in this directory is assembled from four upstream component
groups and is publicly distributed with the catalog under the licenses below
(verified 2026-11-11).

| Component | License | Redistribution | Obligations |
|---|---|---|---|
| kernel (rockchip-linux develop-6.1) | GPL-2.0 (COPYING) | allowed | Ship the source (the bundles in this directory ARE the source); keep LICENSE files |
| u-boot (rockchip-linux next-dev) | GPL-2.0 (Licenses/README) | allowed | Same as above |
| buildroot (official tag 2026.08.1) | GPL-2.0+ (COPYING) | allowed | Same as above |
| rkbin prebuilt firmware (loaders/) | Rockchip proprietary license (loaders/LICENSE) | **explicitly granted** (original text: "hereby grants … to use, copy, distribute the Software") | No decompiling / reverse engineering; keep copyright and notices (distributing original bytes satisfies this); passed on AS IS, no warranty claims may be added |
| mkbootimg.py (vendored build script inside board-ws-e2) | Apache-2.0 (The Android Open Source Project; header notice included in the file) | allowed | Keep the LICENSE notice and NOTICE (contained in the file header) |

EvoVerse's own artifacts in this directory (manifest.json,
layouts/ws-e2-minimal-parameter.txt, board-ws-e2/ board support, LICENSES.md,
README.md) contain no Rockchip/Linux upstream code and are distributed under
the catalog repository's own license.

Notes:

- Files under loaders/ are prebuilt binaries released by Rockchip electronics
  (SPL / DDR init / BL31 / BL32), distributed as-is per the rkbin LICENSE
  original text; do not modify, repackage, or strip notices.
- The corresponding source for the GPL components is the `.bundle` set in
  this directory (git bundles, clonable into full repositories); do not strip
  LICENSE/COPYING files on delivery.
- Customers needing a separate commercial arrangement for Rockchip firmware
  should confirm directly with the SoC vendor — this inventory only covers
  the fact of "redistribution under the public rkbin LICENSE".
