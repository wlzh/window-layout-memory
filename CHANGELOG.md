# Changelog

## [Unreleased]

暂无新增条目。

## [0.3.0-preview.7] - 2026-09-09

- 菜单整理为四个功能组，顶层12项，保留常用动作；统一导航与禁用原因。
- 应用列表增加图标、同名身份区分，支持撤销已停止应用的全局排除。
- 保持窗口策略及schema 1不变；新增26项协调器/菜单检查，完整功能回归294项通过。

## [0.3.0-preview.6] - 2026-09-09

- 新增独立的横屏铺满应用例外：运行列表勾选或从文件选择.app，按Bundle ID持久保存，未运行应用仍可取消；与全部布局功能的应用排除分离。

- 修复尺寸优先流程受原位置屏幕边界约束而无法铺满：同屏、几何可读、原位置容不下目标且明确支持AXZoomWindow时，最多原生缩放一次，再核验尺寸和位置。
- 不使用AXPress或全屏，不跨屏触发此回退，不增加空闲轮询；取消、缺失动作、空间不足、再次尺寸失败均停止。
- 明确原生缩放可能自行改变几何；新增有限重试、取消、延迟、拒绝和防全屏动作选择测试。

## [0.3.0-preview.5] - 2026-09-09

- 新增默认关闭的子窗口铺满选项，依据AX角色及直接父级识别，不把第二个独立窗口当子窗口；未知角色、对话框和浮动面板不放行。
- 新增当前窗口临时排除、精确AX标识持久排除及逐条撤销，排除优先于子窗口选项，防止自动恢复和学习旁路。
- 默认留白100 pt，移除单独设为100 pt菜单，保留手动记忆值。
- 修复快速重新开启铺满时遗留的单次不恢复标记；系统台前调度关闭时仍可走普通恢复。
- 扩展旧数据迁移、存储校验、协调器和原生菜单测试；核心覆盖率分母改为全部LayoutCore文件，无新增第三方依赖。

## [0.3.0-preview.4] - 2026-09-09

- 横屏铺满改为先缩放、有限读回验证，再移动；尺寸失败不先左移，不持续重试。普通恢复和竖屏保存目标恢复不改顺序。
- 默认留白改为100 pt，新增当前组合所有横屏留白设为100 pt的菜单入口；保留其它组合和布局基准。
- 新增尺寸忽略、受限、延迟生效、读回缺失、取消及写入失败的执行顺序测试。真实AX兼容性与硬件验收仍有限制。

## [0.3.0-preview.3] - 2026-09-09

- 修复横屏铺满吞掉保存显示器归属：自动恢复开启、唯一匹配时先确定当前组合的保存显示器，再在目标横屏铺满；目标竖屏恢复保存坐标，不强行铺满。
- 未知组合、未记录或匹配歧义不猜测跨屏；自动恢复关闭时只在当前屏幕铺满。手动拖动临时保留，下一次激活再使用保存显示器。
- 合入保护期内激活保留修复。增加跨屏/竖屏/关闭恢复/未知组合/歧义/手动移动和基准不变回归。
- build 7、schema 1；微信第二实例AX尺寸写入问题仍未解决，真实插拔及长期性能仍需独立验收。

- 文档审计：统一发行/安装/main修复口径、历史PRD与授权时间线、升级偏好、铺满/撤销边界和发行链接；新增状态导航及只读文档校验和5项校验器测试。文档整理不改变应用版本或签名。

- 修复台前调度铺满后2秒保护期内的重新激活请求被直接丢弃：通过现有合并队列延后核对，不增加常驻计时器，不让普通几何通知重新触发已完成的铺满。
- 新增保护期内激活与成功后停止重试两项回归，旧代码上均复现失败。微信第二实例的实际尺寸未到位仍单独待定位，不宣称由此修复。
- 上述此前未发行修复合并到本次build 7，不改变既有布局schema。

## [0.3.0-preview.2] - 2026-09-08

- 新增原生关于窗口，集中展示运行版本/build、作者X @wlzh、869hr.uk、GitHub、使用文档、版本记录及MIT协议。
- 使用系统明暗主题、分组排版及可访问链接，替换原GitHub / MIT / 文档菜单入口，保留独立诊断面板。
- 重复打开复用窗口，关闭释放控制器、视图、链接回调；无计时器、额外窗口扫描或后台网络请求。
- 新增18项原生AppKit关于检查及两种主题渲染检查；build 6，schema 1不变，不修改布局和铺满偏好。
- 此次不修复此前记录的部分应用铺满偏差，实机及长期性能门禁仍独立保留。

## [0.3.0-preview.1] - 2026-09-08

- 新增默认关闭的台前调度横屏自动铺满开关，激活后避开菜单栏和常驻Dock；竖屏不处理。
- 左边缘拖动记忆留白，按完整显示器组合和显示器ID隔离；默认200 pt，同屏不同应用共享。
- 铺满和临时自由调整不覆盖普通布局基准；未知系统状态、暂停、排除和权限失效不自动铺满。
- 使用事件驱动核对，无新空闲轮询；新增几何、偏好和协调器回归。
- build 5，schema 1兼容新增偏好；导入默认关闭铺满模式。实机与长期性能门禁独立记录。

## [0.2.0-preview.2] - 2026-09-08

- 使用鼠标按下/松开生命周期捕获窗口拖动证据，支持松手后AX通知及释放时触发有界核对。
- 不再用移动后鼠标位置命中旧窗口边缘；要求起点命中、位移至少3pt、窗口几何实际改变。
- 暂停、切屏、权限失效撤销未完成手势；无几何变化清理证据，普通点击与内容区拖动不自动保存。
- 新增协调器回归。鼠标仅按下/松开事件监听，无mouseMoved监听、截图或空闲轮询；退出移除监听。
- build 4、schema 1；WPS实际重测与完整硬件性能门禁仍需验证。

## [0.2.0-preview.1] - 2026-09-08

- Add native read-only current/saved/comparison layout preview with proportional monitor geometry and coordinate details.
- Keep other monitor combinations isolated, including their built-in display windows.
- Show last-read timestamps and ambiguity without claiming background visibility or stacking order.
- Coalesce event-driven preview updates; cancel pending work and release window/controller/canvas on close.
- Add projection, matching, cached-preview, AppKit refresh/lifecycle and synthetic rendering checks.
- Centralize bundle version/channel/build display. Build 3; schema 1 retained; no screen recording required.
- Full physical monitor, real AX and long-run performance acceptance remains separate.

## [0.1.0-preview.2] - 2026-09-07

### Added

- Persist deliberate foreground mouse drag/resize adjustments after settling; retain candidates when intent is uncertain.
- Conservative legacy preference migration, locked baseline protection and no-op capture deduplication.
- Manual display mapping/copy UI, layout renaming and cancellation of pending restores.
- 103 core cases / 2,814 assertions and 28 injected Engine integration checks, including a 1,000-event burst.
- Explicit regressions for distinct same-count monitor sets: even the shared built-in screen has separate window layouts in each combination.
- Dedicated Engine coverage script; hardware and real AX coverage remain separate.

### Fixed

- Baseline revisions no longer rearm automatic restoration and fight later user adjustments.
- Reuse window notification registrations and preserve runtime identities across partial scans.
- Cancel queued scans between windows after pause or topology changes; prioritize foreground scans.
- Retry a transient AX write at most once, only when no geometry changed and the pointer is released.
- Check permission and pointer state between writes; remove Engine observers on teardown.

### Status

- Build 2, ad-hoc signed, not notarized. Updating a locally signed binary can require renewed Accessibility permission.
- Stage Manager ON/OFF, physical display cycles, login/wake, real AX writes and long-run performance still require acceptance.

## [0.1.0-preview.1] - 2026-09-07

### Added

- Project scope, MIT license and versioned requirements proposal.
- Functional acceptance matrix covering monitor combinations, Stage Manager,
  learning protections, persistence, recovery, identity matching and privacy.
- P0 performance budgets for idle CPU, memory, wakeups, event storms and soak tests.
- Explicit Stage Manager OFF / ON / runtime-switching requirements; 42 acceptance scenarios.
- Approved native event-driven technical design and interaction specification.
- Native menu-bar preview, AX event adapter, per-topology profiles, candidate capture, restore verification, history and backup.
- 71 passing core cases / 1,634 assertions; measured LayoutCore line coverage 98.41% (not whole-app coverage).
- Build, install, package, coverage and resource measurement scripts; macOS CI.

### Status

- Requirements and design approved; runnable development preview implemented.
- Full functional, Stage Manager, monitor-switching, login and performance acceptance incomplete.
- Candidate observations require explicit save; not fully automatic persistent learning.
