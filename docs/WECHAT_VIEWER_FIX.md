# 微信看图窗口兼容修复（0.3.0-preview.14 / build 21）

历史报告：build 24已移除此处描述的图片硬编码，当前使用用户保存的例外；现行规则见[自定义规则](CUSTOM_WINDOW_RULES.md)。下文保留原版本验证事实。

2026-09-11：仅已知微信 bundle `com.tencent.xinWeChat` / `com.tencent.xinWeChat2` 下，标题精确为“图片和视频”的标准窗口受子窗口铺满开关控制。实际观察到了中文标题和标准窗口角色；未确认该窗口直接父级，故规则不依赖推测的父级归属，也不放宽原有安全检查。

规则、限制及既有尺寸处理见 [STAGE_FILL.md](STAGE_FILL.md)。新增规则通过引擎共用入口作用于两个方向及铺满模式中的恢复/学习过滤。不新增后台任务、持久字段或依赖。其它语言、改名或其它多开 bundle 暂不覆盖。

本轮验证：

- Core 146项通过（3300断言），包含两个微信标识、子窗口开关、聊天主窗口、其它应用同名窗口、近似标题、未知父级、模态和对话框。
- Engine 157项、Preview 12项、About 18项通过，共333项；引擎新增入口检查，不等同真实微信操作验收。
- 文档校验器5项测试通过；发行构建、签名验证及元数据检查通过。
- 已同步0.3.0-preview.14 / build 21版本及发行说明；版本更新后再次运行完整333项及文档校验器5项，全部通过。86份Markdown、212个本地链接及版本元数据检查通过。
- 已安装到 `/Applications/Window Layout Memory.app` 并启动，界面确认preview.14 / build 21。沿用原有ad-hoc签名方式和bundle标识，新进程显示辅助功能未授权，需要用户重新授权。
- 安装前布局目录已备份到 `~/Library/Application Support/WindowLayoutMemory-upgrade-backups/build21-before-install-20260911`；安装后及首次启动后layouts.json均与备份逐字节一致。4份布局、当前15个基准、12个应用例外保留，横屏/竖屏开关仍开启，子窗口开关仍关闭。
- 未发布GitHub Release。未做新版真实微信交互和耗电实测，不能据此宣称实机全部通过。

本地最终测试日志：`/tmp/wlm-build21-tests.log`；构建日志：`/tmp/wlm-build21-build.log`。临时日志可能被系统清理。
