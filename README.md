# Window Layout Memory

Remember your workspace, separately for every display setup. Native Swift/AppKit, MIT, no third-party runtime dependencies.

面向 macOS 的窗口布局记忆应用。目标是保留用户在单屏、双屏、多屏环境下分别调整好的窗口大小、位置与显示器归属，在显示器切换和重新登录后恢复，不让系统临时重排覆盖用户偏好。

**v0.1.0-preview.1：开发预览，不是稳定版。** 已有可运行应用、构建与核心测试；尚未完整满足PRD，台前调度开/关、实际插拔与登录恢复、代表性性能均未完成验收。

当前实现：前台普通窗口核对、候选保存、按显示器组合隔离基准、锁定、历史回退、保守匹配、可选恢复及一次核验、暂停、排除、私人备份和登录启动设置。自动移动默认关闭。

**自动核对仅产生会话内候选，需点击保存才持久化。** 它还不是完全无感自动学习成品。后台窗口需用户激活，不展开最小化窗口或强制切换台前调度组。角色规则编辑器、显示器别名映射、启动其它应用、恢复重试等尚未完成。

## Build and use

```sh
zsh scripts/test-all.sh
zsh scripts/coverage.sh
zsh scripts/build-app.sh
zsh scripts/install-local.sh
zsh scripts/package-release.sh
```

需要macOS和Swift Command Line Tools。首次打开应用，在系统设置授权辅助功能后点击“重新核对”。依次激活目标窗口，停留约2秒，点击“保存已核对候选为基准”。确认基准正确后再启用自动恢复。

当前产物arm64、ad-hoc签名、未公证。本机验证macOS15.6，部署目标macOS13不代表低版本或Intel已验证。

71核心用例 / 1,634断言通过；LayoutCore行覆盖98.41%，**不包括Engine、AX、UI**，不得解读为全项目覆盖率。10分钟代表性负载及8小时驻留未通过前，不宣称CPU/内存预算达标。

详见 [使用指南](docs/USER_GUIDE.md)、[测试报告](docs/TESTING.md)、[兼容性](docs/COMPATIBILITY.md)、[发行说明](docs/releases/v0.1.0-preview.1.md)。

## Planned scope

- Separate layouts for distinct monitor identities, arrangements and scaling configurations.
- Automatic learning of deliberate window adjustments, with locked baselines and history.
- Stage Manager-aware handling: never learn sidebar preview bounds as normal window geometry.
- Ordinary desktop operation with Stage Manager OFF is equally required, including switching modes while running.
- Restore existing/reopened ordinary windows after display changes, wake and login.
- Conservative matching of multiple windows from the same application, with visible ambiguity and manual correction.
- Local-only layout storage, export, backup, pause, exclusions and undo.
- Low overhead is a release gate: near-zero idle CPU, bounded memory and no periodic full-window scans. Budgets and measurement criteria are in the PRD; no performance results exist yet.

Spaces, native full-screen windows and Stage Manager group restoration are out of scope. Recreating arbitrary application documents, tabs or unsaved content is not promised.

## Requirements

Read [v0.1.0 PRD](docs/prd/v0.1.0/prd.md) for scope, user stories, edge cases and 42 acceptance criteria. Requirements and [technical design](docs/prd/v0.1.0/dev.md) are confirmed, but are not a statement of implemented features. See [interaction design](docs/prd/v0.1.0/design.md) and [plan](docs/prd/v0.1.0/plan.md).

Hardware verification and stable release remain gated on the acceptance matrix. Supported macOS versions and architectures are recorded from actual validation.

## Privacy

Do not commit real window titles, document paths, display serial numbers, screenshots or layout exports. Reports and tests must use synthetic or redacted fixtures. No telemetry or cloud upload is planned.

## Version and license

Current development preview: **0.1.0-preview.1**, build 1. See [CHANGELOG](CHANGELOG.md).

Copyright (c) 2026 wlzh. Licensed under the [MIT License](LICENSE).
