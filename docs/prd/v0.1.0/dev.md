# v0.1.0 技术设计

状态：方案已获确认，开发预览已实现。下文含未完成设计，不是现有能力清单或测试通过报告。

## 历史实现与方案差异

本节开头记录v0.1.0-preview.1，末尾补充preview.2；第0至14节保留早期设计，不是当前代码清单。现行能力见[状态总览](../../STATUS.md)。早期“最多2次重试、镜像折叠、独立reducer、拟新增文件”等均不可视为已实现；现行仅对特定无几何变化的AX临时错误重试一次，镜像拒绝。

核心集中于Sources/LayoutCore/Core.swift，应用为Engine.swift、Platform.swift、main.swift。尚无完整纯reducer、恢复重试、第三方应用启动、规则编辑器和屏幕别名映射。候选仅会话内保留，需用户保存；只核对/恢复前台窗口。自动恢复默认关闭。

CLT已用Swift插桩/llvm-cov测核心覆盖，无需XCTest；71核心用例通过、行覆盖98.41%，不含AX/Engine/UI。实际验收见 [TESTING](../../TESTING.md)。

需求见 [PRD](prd.md)，界面见 [design.md](design.md)。

## 0. 设计启动时的历史审查

已检查 main 分支：现有仓库只有 README、VERSION、MIT、贡献/安全文档、更新日志与 PRD；没有 Package.swift、入口、运行时、数据模型或测试模块。以下文件和类型均为拟新增，不冒充现有架构。

当前开发环境实际检查：macOS 15.6 / arm64，Swift 6.1，Command Line Tools。直接导入 XCTest 返回 no such module；本地基础测试不能假设存在完整 Xcode。发行签名仍需在构建时重新检查。

本地 SDK 已核实：AXObserverCreate、AXObserverAddNotification、窗口创建/移动/缩放/焦点通知、CGDisplayRegisterReconfigurationCallback。通知可能不受具体应用支持，必须处理错误码。

## 1. 技术选择

| 项 | 方案 | 原因 |
| --- | --- | --- |
| 运行时 | Swift + AppKit 菜单栏应用 | 无 WebView/Electron/浏览器运行时；按需创建设置界面 |
| 构建 | Swift Package Manager + app bundle 打包脚本 | 支持本机 CLT，保持依赖少且构建可重复 |
| 最低部署目标 | 拟 macOS 13，先在 macOS 15.6 实测 | SMAppService 可用；低版本运行兼容不能只凭编译宣称 |
| 窗口读写 | 公共 Accessibility API | 不使用私有 CGS、窗口注入或绕过 SIP |
| 屏幕几何 | NSScreen + CoreGraphics 显示回调 | 捕获重配置开始与完成，使用逻辑点 |
| 持久化 | Codable JSON、版本化文件与原子替换 | 数据量小，无常驻数据库服务 |
| 登录启动 | SMAppService.mainApp | 用户显式选择，报告真实注册状态 |
| 测试 | 无系统依赖的核心测试可执行程序 + macOS 集成测试 | 本地 CLT 可执行；CI 完整 Xcode补覆盖率测量 |

不引入第三方运行时依赖。ARM64/x86_64 可构建性、实际架构运行情况与签名公证分别记录。

## 2. 模块边界

```text
AppKit UI (main thread)
        | commands / immutable state
Coordinator (serial state machine)
        | effects, each bound to generation
        +-- DisplayMonitor
        +-- WorkspaceMonitor
        +-- AXWindowService (dedicated run-loop thread)
        +-- LayoutStore (serialized file I/O)
        +-- LoginService

LayoutCore: geometry, matching, learning policy, reducer, persistence validation
```

主线程只做菜单、窗口展示与必要 AppKit 读取。跨进程 AX 调用不在主线程执行；每次调用设超时，整个批次有时间预算。UI 的暂停先改变协调状态，尚未完成的同步 AX 调用不能被强行中断，但结果必须通过代际校验才能生效。

AX 观察者在专有 RunLoop 注册/移除；每应用一个观察者，按窗口订阅需要的事件。窗口销毁、应用退出、权限撤销时释放引用与回调上下文，防止悬空回调。

## 3. 事件驱动与性能

### 3.1 事件入口

- 显示回调开始：立刻递增 topology generation，冻结学习并取消待恢复/写入候选。
- 显示回调完成和 AppKit 屏幕变化：提交新屏幕描述，安排一次可取消的稳定性核对。
- 应用启动/退出/激活、隐藏/显示、系统睡眠/唤醒：更新受影响的应用，不全量高频扫描。
- AX 窗口创建、移动、缩放、销毁、最小化、焦点及标题变化：标记对应窗口 dirty；订阅失败逐项记录。
- 手动刷新、从权限设置返回：执行有界检查，不开启永久权限轮询。

SDK 将移动和缩放通知描述为操作结束时通知，但不能假设所有第三方应用遵循一致行为；仍需合并和去重。

### 3.2 有界调度

每个窗口只保留最新待处理状态；使用一个可重新调度的最早截止时间计时器，而非每次事件生成 Task/Timer。没有 dirty 项或待重试项时取消计时器。

初始参数：变化尾沿合并 500ms；显示稳定核对间隔 750ms，最多 3 次；未稳定则进入等待事件状态，不自旋。数值是实现起点，须结合实机调整并维持 PRD 性能预算。

dirty 集合与工作队列有上限；超限只保留“某应用需重新核对”标记，不生成无界任务。事件风暴时先停止学习，不丢弃权限/显示拓扑失效事件。

不监听全局键盘文本、不持续监听鼠标移动、不做截屏/OCR，不借屏幕录制权限全量枚举窗口作为后台常规路径。

### 3.3 降级而不是忙等

应用不支持某 AX 通知时记录 capability；在应用激活、用户刷新、已知窗口事件时局部重读。不能承诺这种应用在完全不产生事件时也会自动即时学习；兼容性报告必须明确。

窗口未出现或台前调度未激活时只保留轻量 pending 数据，无永久重试计时器。后续应用/窗口事件触发恢复。

权限缺失不弹窗循环；回到应用或用户点击重试再检查。暂停取消业务动作与计时器，可保留显示变化/退出等必要观察。

## 4. 数据模型

所有持久化标识与运行时句柄分开。PID、AX 对象、CGWindowID 仅存在内存中，不能作为重启匹配依据。

| 类型 | 字段及职责 |
| --- | --- |
| DisplayDescriptor | UUID、厂商/型号/序列号线索、builtIn、逻辑 frame/visibleFrame、rotation、scale、mirrorTarget |
| TopologyKey | 显示身份 + 相对排列 + 尺寸/缩放/旋转 + 主屏，经稳定排序规范化；忽略枚举顺序 |
| Profile | schemaVersion、id、名称、topology、baselineRevision、locked、confirmed、保存窗口 |
| SavedWindow | roleID、bundleID、匹配线索、displayID、屏幕内 absolute frame、normalized frame、sourceVisibleFrame |
| Observation | 运行时窗口 token、AX 几何、状态/证据、单调时间、topology/visibility generations |
| Candidate | 最后稳定观察及其来源，独立于 confirmed baseline |
| RestoreTransaction | topologyGeneration、profileRevision、每窗口目标、操作前值、attempt、actualResult |
| WindowRule | 用户定义的应用范围、窗口角色、精确/受限标题规则、匹配策略 |
| Preferences | 自动记忆/恢复、排除、历史上限、可选启动应用；登录启动真实状态从系统读取 |

布局基准不带台前调度开关作为分裂条件；可用区域适配结果独立于原基准。旧扫描 JSON 不是本应用 schema，不自动导入为可信基准。

双窗口标题完全相同、同应用实例且缺乏其他线索时为 ambiguous，不以数组顺序填充。

## 5. 坐标与显示识别

统一坐标为主屏左上角原点、向下为正的逻辑点。AppKit 的坐标转换以当前主屏边界计算，不缓存过期主屏高度。

同时保存目标屏幕可用区域内的 point offset 和 normalized rect。相同 frame/visibleFrame 优先点坐标；缩放或可用区域不同才映射比例。拒绝 NaN、Infinity、零/负尺寸、未知显示器。

窗口跨屏时按最大相交面积确定主归属，平局使用此前已确认归属或要求确认；归一化值允许超出 0...1 以保留跨屏事实。恢复到变更环境时保证标题栏可达，不能随意夹紧整个窗口破坏正常跨屏布局。

若 exact TopologyKey 不存在，不自动模糊套用。用户可确认别名映射后继承。UUID 改变或重复厂商/型号不独自构成可移动授权。

镜像显示折叠为可操作目标；无法无歧义折叠时标记 unsupported topology 并禁用自动恢复。

## 6. 普通桌面与台前调度

v0.1.0普通布局管线不依赖未文档化的台前调度defaults key，也不假设有可靠公共开关通知。v0.3.0新增的可选横屏铺满另行读取非公开约定的WindowManager偏好，限制见[铺满说明](../../STAGE_FILL.md)，不能把此处旧方案当作全应用现状。

1. 只读取 AX 标准窗口，排除系统覆盖层和非目标辅助窗口；全屏在范围外。
2. AXPosition/AXSize 成功、有限值、角色合法仅是基本条件，不等于已证实真实几何。
3. 活跃/聚焦普通窗口在稳定后可成为学习候选；非活跃组若几何无法验证，保留上次可信值、等待激活。
4. 最小化/隐藏不自动展开；事件后核对标志，不能用小窗口尺寸阈值识别预览。
5. 台前调度开关/组切换带来的集中几何或焦点变化提升 visibility generation 并进入保护；此为保守策略，不声称能检测所有模式切换。
6. 无可靠变化来源证据时不自动覆盖 confirmed baseline。候选历史可记录，但需用户确认后才成为恢复基准。

**可行性门禁**：必须实测台前调度开启/关闭/切换时 AX 实际返回及事件时序。若模式切换与用户拖动不可可靠区分，安全降级为候选确认，不能凭设计宣称实现无感全自动。不得用 CG 缩略图几何填补缺失。

## 7. 学习与恢复状态机

```text
permissionBlocked / paused / sleeping
           |
topologyChanging -> settling -> unknownProfile / ready
                                    |
                                 restoring -> verifying -> ready

per-window: waitingForAppearance / waitingForActivation /
            ambiguous / candidate / eligible / failed / excluded
```

每个异步结果含 topologyGeneration、visibilityGeneration、profileRevision、operationID。提交前比较全部相关代际；失配则丢弃，不能给新配置写旧结果。

所有坐标写入前复核权限、排除、暂停、当前拓扑、实时窗口有效性、状态可操作性。用户已再次移动或焦点变化导致窗口不可访问时终止该次恢复。

恢复写入产生的观察带 suppression 信息；即使目标应用延迟发通知，也不能自动学习为新基准。恢复目标核验与学习基准更新彻底分离。

有脏候选时显示变化：丢弃未确认候选或保留其原代际为历史待确认，不在断屏回调里扫描并保存已被系统挤压的布局。

## 8. 窗口匹配与恢复执行

匹配顺序：同会话已确认 runtime binding → 用户角色规则 → 唯一文档/稳定标识组合 → 唯一标题匹配。单窗口应用 fallback 必须要求当前和已存双方确实唯一，不能用于多个相同应用实例。

采用全局一对一分配并检查候选冲突；任何等分/冲突匹配返回 ambiguous。自动恢复不使用低置信模糊标题匹配。

AX 写入前检查属性 settable。针对应用约束采用有限的 position/size 写入顺序并核验实际值；批次内每次跨进程调用有超时，避免无响应应用阻塞队列。

目标每个分量误差 ≤4pt 判通过。每事务初次尝试加最多 2 次重试，退避但无周期常驻任务。未知/不支持/被撤销权限不盲重试。仅部分坐标成功要报告 partial，并保留实际结果。

撤销仅对成功改变的同会话窗口记录操作前几何；拓扑或窗口身份变化禁止盲撤销。进程重启后不重用内存句柄执行旧撤销。

## 9. 持久化与资源上限

数据目录：用户 Application Support 下独立应用目录。目录权限 0700，文件 0600；无网络写入。

单写者、同目录临时文件、验证编码后原子替换；保留最后已确认版本。磁盘满/权限错误不得报保存成功。损坏隔离，拒绝未知高版本 schema 自动覆盖。备份和恢复均验证 schema、数值和大小。

历史采用每配置有界版本数与总字节上限，默认拟 20 份/配置、总 20 MiB；清理仅清理非当前旧历史，不删除唯一有效基准。无变化 digest 不写盘。

内存缓存只留当前配置、运行时绑定和有界待处理状态；历史按需读取。诊断环形缓冲限制条数且默认脱敏，不记录持续的原始窗口标题。

导入防止路径穿越/符号链接误写；允许单文件 JSON，拒绝超限、冲突 ID、无效规则。窗口匹配规则限制复杂度，避免灾难性正则回溯。

## 10. 拟新增文件

| 文件 | 职责 |
| --- | --- |
| Package.swift | LayoutCore、App、CoreTests 可执行 target 与测试 target |
| Sources/LayoutCore/Models.swift | 序列化模型、版本 |
| Sources/LayoutCore/Geometry.swift | 逻辑坐标、比例、屏幕归属 |
| Sources/LayoutCore/Topology.swift | 规范化与精确匹配 |
| Sources/LayoutCore/WindowMatcher.swift | 一对一保守匹配 |
| Sources/LayoutCore/LearningPolicy.swift | 候选/基准与学习保护 |
| Sources/LayoutCore/Coordinator.swift | 纯状态机、动作与代际 |
| Sources/LayoutCore/LayoutStore.swift | 存储验证、历史与原子提交 |
| Sources/WindowLayoutMemory/main.swift | 入口与 App 生命周期 |
| Sources/WindowLayoutMemory/DisplayMonitor.swift | 显示事件适配 |
| Sources/WindowLayoutMemory/WorkspaceMonitor.swift | 应用/睡眠/激活适配 |
| Sources/WindowLayoutMemory/AXWindowService.swift | 观察者、窗口枚举、读写及超时 |
| Sources/WindowLayoutMemory/Scheduler.swift | 有界 dirty 集合与单次定时 |
| Sources/WindowLayoutMemory/MenuController.swift | 菜单栏 |
| Sources/WindowLayoutMemory/SettingsController.swift | 按需设置与布局 UI |
| Sources/WindowLayoutMemory/LoginService.swift | 登录服务 |
| Sources/CoreTests/main.swift | CLT 下相同核心用例执行入口 |
| Tests/LayoutCoreTests/RegressionTests.swift | Xcode CI 测试入口与覆盖率 |
| Tests/Support/Fixtures.swift | 合成窗口/屏幕/事件数据 |
| Tests/Support/Fakes.swift | 虚拟时钟、失败注入、AX/store 替身 |
| Resources/Info.plist | bundle identity、版本、最低系统 |
| scripts/test-all.sh | 本地测试统一入口 |
| scripts/package-release.sh | 构建、打包、签名验证与校验和 |
| scripts/install-local.sh | 本地安装、版本核验与旧数据保护 |
| .github/workflows/ci.yml | 构建、测试、覆盖率与文档校验 |
| docs/TESTING.md | 自动化命令、覆盖口径、实机流程 |
| docs/COMPATIBILITY.md | 系统/应用两模式兼容矩阵 |
| docs/USER_GUIDE.md | 安装、权限、学习、恢复、卸载 |
| docs/releases/v0.1.0.md | 发行状态、结果、限制 |

拟改动：README、VERSION、CHANGELOG、版本文档索引。删除：无。无 SQL/远程服务/HTTP API。

## 11. 内部接口

`WindowService.observe/read/apply` 返回 typed Result 与 capability，不把空数组当权限不足。
`Coordinator.reduce(event, state)` 产生明确 effects；不直接操作系统，可用虚拟时钟穷举时序。
`Store.commit(profile, expectedRevision)` 拒绝过期覆盖，报告编码/写入/验证错误。
`Matcher.assign(saved, live)` 返回 resolved、ambiguous、missing，不同结果在 UI 与测试中可区分。

UI 只提交用户命令，不直接写 JSON 或 AX 属性。展示层不会触发无边界刷新循环。

## 12. 测试设计与证据

42 个 PRD 条目逐项映射测试 ID；同一个功能的模拟通过不能替代真实 API/窗口验证。

- 核心测试：几何、拓扑、不变量、匹配、写入失败、schema、安全导入、代际竞态、事件合并、历史上限。
- 性质测试：枚举顺序置换不变、一对一分配不冲突、未知拓扑不写坐标、锁定不覆盖、同值不写盘、旧事件永不提交。
- 事件轨迹：两种模式、1/2/3 屏、插拔与恢复同时发生、权限中途撤销、关闭/新建窗口、重启标识变化。
- 适配器集成：AX 通知不支持、读取/写入超时、单边写入成功、观察者释放、菜单暂停与取消。
- 实机验证：台前调度开/关各跑完整 PRD 流程；两模式切换额外跑基准保护与合法小窗口回归。
- 性能：release 构建、无调试器、关闭设置面板；CPU/物理 footprint/RSS/唤醒分开测，记录工具自身影响。

覆盖率目标：LayoutCore executable lines ≥90%，安全分支至少一个正例/反例；UI 和 OS 适配器单独列分母，不能通过排除它们声称全项目90%。如工具不能给出真实分支覆盖，报告为未测，不把行覆盖换名。

测试入口共享核心用例，避免 CLT 与 XCTest 两套断言漂移。CI 可用 XCTest 后测覆盖率；本机无 XCTest 的事实不能成为不跑测试的理由。测试数量、断言数量、通过/失败/跳过分别报告。

文档检查验证本地链接、版本一致、需求映射、无已知私人数据；这类检查不计入运行时功能测试通过数。

## 13. 部署与回退

开发 app 使用稳定 bundle ID 拟 `uk.869hr.WindowLayoutMemory`，固定本地安装路径以减少权限身份漂移；ad-hoc 更新仍可能需要重新授权，不能保证凭 bundle ID 保持授权。

不默认注册登录服务；由用户设置。升级前验证存储 schema 并保留可回退备份。应用二进制回滚不自动降级未知数据。

发行不得捆绑本机布局/日志。归档解压、架构、版本、codesign 验证、checksum、安装启动单独检查；无 Developer ID 则标记未公证预发布。

## 14. 技术风险与确认门禁

1. 台前调度的 AX 实际几何与通知需实测；公共 API 存在不等于完整场景可用。
2. AX 变化没有可靠“用户主动”来源字段；候选与基准分离是必要安全边界，不能承诺所有调整无确认自动识别。
3. 不支持 AX 通知的应用不以高频轮询补齐，兼容性与无感程度必须透明。
4. 多个完全同质窗口重启匹配可能需要用户角色；不能凭顺序猜。
5. 性能预算为门槛，UI/框架及 AX 的实际开销需实测；不提前宣称≤50MiB。

技术方案已确认，继续实现与验证。若关键API实测不满足自动化程度，先报告限制而非静默改变需求。

## 15. 官方依据

- [AXObserverAddNotification](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification)：可能返回 notificationUnsupported。
- [CGDisplayReconfigurationCallBack](https://developer.apple.com/documentation/coregraphics/cgdisplayreconfigurationcallback)：配置前后分别回调，回调不用于改显示配置。
- [SMAppService.register](https://developer.apple.com/documentation/servicemanagement/smappservice/register())：登录启动受用户授权控制。

上述依据只证明接口契约，不证明本项目已实现或所有应用兼容。
## v0.1.0-preview.2 历史实现补充

Engine通过WindowService及EngineEnvironment注入窗口服务、拓扑、权限、时钟、鼠标和进程快照。假服务集成测试使用临时目录，不接触真实用户窗口或布局。系统通知仍只在生产环境注册。

LearningGate保存有界、30秒过期的鼠标几何证据；前台标题栏/边缘事件才授予证据。两次稳定扫描、鼠标释放后，经2秒合并保存。代际切换清空证据和待保存任务，CaptureMerge拒绝锁定/错拓扑并去重未变化布局。旧数据缺少autoRemember字段时解码为false，新安装默认true。

恢复尝试按代际与运行期窗口令牌去重，不随基准修订号自动重置。AX临时失败只在几何完全未变化时重试一次；每次写入重新检查权限、焦点、拓扑和鼠标状态。通知按窗口增量维护，部分扫描保留仍存在窗口的运行期身份。

手动显示器映射必须覆盖全部源屏幕且目标唯一。以目标可用区域比例换算复制窗口，保留源配置，更新目标历史，复制后暂停恢复供用户确认。
