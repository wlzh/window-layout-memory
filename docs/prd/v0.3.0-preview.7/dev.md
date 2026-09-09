# 技术方案

AppDelegate.menuWillOpen负责分组及路由，复用现有selector和Engine命令。新增只读hasAccessibilityPermission供状态入口判断授权。

NSWorkspace运行应用列表每次展开只读取一次，按Bundle ID去重；复制图标后缩为16 pt。持久例外从现有Preferences读取，schema保持1。全局未运行例外使用原Bundle ID显示，不伪造应用名称。

递归关闭NSMenu.autoenablesItems，保留业务显式禁用状态。Engine状态机、窗口服务、布局核心、持久化契约均不改动。没有新依赖、轮询器或后台缓存。

EngineChecks使用注入服务验证层级、路由、状态和无副作用；不替代真实AX或物理显示器验证。
