[English](README.en.md) | 中文

# WS-E2 RK3588 离线开发环境物料

> **DEPRECATED（2026-11-10，勿按本文件操作）**：本目录描述的离线 evopkg 部署流程自
> SDK 1.0.0 起已封门——adapter `environment.prepare` 只返回 `LEGACY_ENVIRONMENT` 弃用
> 标注，`environment.deploy` 以 `ENVIRONMENT_MANAGER_REQUIRED` 拒绝执行。新链路：
> 物料 `environment_requirement`（REQUIRED，指向 `platforms/rk3588/profile.template.json`）
> → Linux Environment Manager（`evoverse-env`，见 evoverse-linux-dev 仓库
> `docs/installation.md`）安装环境 → Adapter 解析 `environment-lock.json`。本文件仅作
> 历史记录保留（包身份与校验值仍真实有效，但部署通道已关闭）。

这里仅声明 SDK 接受的离线包身份和健康策略，不存放大型 BSP 或 Docker 镜像。

## 客户拿到包以后怎么做

1. 向 EvoVerse 获取下面两个文件，文件名不可修改：
   - `rk3588-toolchain-2026.09.evopkg`（256,584,627 字节，约 244.7 MiB）
   - `ws-e2-rk3588-bsp-b8f5dda5.evopkg`（344,225,733 字节，约 328.3 MiB）
2. 放入 `%USERPROFILE%\evoverse-sdk\downloads\rk3588\`。如果 SDK 配置了其他 `EVOVERSE_HOME`，则放入 `<EVOVERSE_HOME>\downloads\rk3588\`。
3. 打开 RK3588 Workbench，在 Overview 中点击“检查环境”。也可点击“选择离线包”逐个选择两个文件。
4. 两个包都通过文件大小、SHA-256、内部 manifest 和逐文件 checksum 校验后，阅读并勾选许可确认，再点击“一键部署”。
5. 等待状态变为 `READY`。`READY` 只表示 Docker、工具链、BSP 与资格回执满足开发环境门禁；不代表工程已构建，也不代表硬件验证通过。

不要解压、改名或重新压缩 `.evopkg`。校验失败时重新向 EvoVerse 获取原文件，不要通过修改 JSON 或回执绕过检查。

## 安装位置与空间

- BSP：`<EVOVERSE_HOME>\bsp\ws-e2\b8f5dda5\`
- 工具链归档：`<EVOVERSE_HOME>\toolchains\rk3588\2026.09\`
- 安装回执：`<EVOVERSE_HOME>\receipts\rk3588\`
- 建议部署前至少保留 9 GiB 可用空间；工具会按 manifest 的最低空间要求再次检查。

包内 BSP 以 Git bundle 保存，部署时重建为具有固定 root commit 和四个固定 submodule commit 的干净仓库，然后继续执行 SDK 原有 BSP 资格校验。包内不含本机构建缓存、`.evoverse-scratch`、日志或已生成固件。
