# WS-E2 RK3588J minimal Linux candidate

This directory contains board-owned candidate inputs, not a prebuilt image.

Start with `customer-selection.yaml`. After the customer provides a complete BSP checkout and freezes its repo manifest/commits, use the RK3588 adapter to:

1. qualify the BSP source, licenses, loader, partition layout, toolchain and container;
2. validate the DTS files with the selected BSP's native kernel build;
3. create the bound `evoverse-rk3588-profile.json` workspace;
4. build U-Boot, kernel/DTB, Buildroot rootfs and the firmware package;
5. promote to `BUILD_READY` only when all four receipts share the same input identity.

Until those steps run, `manifest.yaml` must remain `CANDIDATE` and all build, flash and hardware states remain `NOT_RUN`.
