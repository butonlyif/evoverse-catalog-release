English | [中文](README.md)

# WS-E2 RK3588 Offline Development Environment Materials

This directory only declares the offline package identities and health policy accepted by the SDK; it does not store large BSPs or Docker images.

## What to do after receiving the packages

1. Obtain the following two files from EvoVerse; do not rename them:
   - `rk3588-toolchain-2026.09.evopkg` (256,584,627 bytes, ~244.7 MiB)
   - `ws-e2-rk3588-bsp-b8f5dda5.evopkg` (344,225,733 bytes, ~328.3 MiB)
2. Place them in `%USERPROFILE%\evoverse-sdk\downloads\rk3588\`. If the SDK is configured with a different `EVOVERSE_HOME`, place them in `<EVOVERSE_HOME>\downloads\rk3588\`.
3. Open the RK3588 Workbench and click "Check Environment" in Overview. You may also click "Select Offline Packages" to pick the two files one by one.
4. After both packages pass file-size, SHA-256, internal manifest and per-file checksum validation, read and accept the license confirmation, then click "One-Click Deploy".
5. Wait until the status becomes `READY`. `READY` only means Docker, the toolchain, the BSP and the eligibility receipt satisfy the development environment gate; it does not mean a project has been built, nor that hardware validation passed.

Do not extract, rename or re-compress `.evopkg` files. If validation fails, obtain the original files from EvoVerse again; do not bypass the checks by modifying JSON or receipts.

## Install Locations and Disk Space

- BSP: `<EVOVERSE_HOME>\bsp\ws-e2\b8f5dda5\`
- Toolchain archive: `<EVOVERSE_HOME>\toolchains\rk3588\2026.09\`
- Installation receipts: `<EVOVERSE_HOME>\receipts\rk3588\`
- Keep at least 9 GiB of free space before deployment; the tools will re-check against the minimum space requirements in the manifest.

The BSP inside the package is stored as a Git bundle. During deployment it is rebuilt into a clean repository with a fixed root commit and four fixed submodule commits, and then the SDK's regular BSP eligibility validation proceeds. The package contains no local build cache, `.evoverse-scratch`, logs or prebuilt firmware.
