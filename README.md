# Window Layout Memory

Remember your workspace, separately for every display setup.

面向 macOS 的窗口布局记忆应用。目标是保留用户在单屏、双屏、多屏环境下分别调整好的窗口大小、位置与显示器归属，在显示器切换和重新登录后恢复，不让系统临时重排覆盖用户偏好。

**Status: technical design review / 技术设计评审中。需求已确认，当前仓库仅包含项目基础文件和需求/设计文档，没有可运行应用，没有完成实现或测试，未发布版本。**

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

Read [v0.1.0 PRD](docs/prd/v0.1.0/prd.md) for scope, user stories, edge cases and 42 acceptance criteria. Requirements are confirmed, but are not a statement of implemented features. [Interaction design](docs/prd/v0.1.0/design.md) and [technical design](docs/prd/v0.1.0/dev.md) are ready for review.

Implementation, architecture, user guide, automated tests, hardware verification and release artifacts will follow the requirements and technical-design review gates. Supported macOS versions and architectures will be recorded from actual validation.

## Privacy

Do not commit real window titles, document paths, display serial numbers, screenshots or layout exports. Reports and tests must use synthetic or redacted fixtures. No telemetry or cloud upload is planned.

## Version and license

Target first version: **0.1.0**, currently unreleased. See [CHANGELOG](CHANGELOG.md).

Copyright (c) 2026 wlzh. Licensed under the [MIT License](LICENSE).
