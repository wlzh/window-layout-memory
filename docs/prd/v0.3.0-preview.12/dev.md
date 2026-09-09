# 技术实现

AppDelegate复用原有NSMenuItem动作和Engine持久化路径，将应用、当前窗口及已保存窗口规则组合成同一子菜单。复制条目保留target、action、representedObject、勾选、图标、提示和显式禁用状态。菜单展开仅读取现有引擎缓存及运行应用列表。

接口影响：移除旧分散的应用例外/管理窗口例外入口；不引入管理窗口控制器或新刷新任务。临时规则复用token，永久规则复用bundle/identifier/role/subrole，应用规则复用bundle。没有数据库迁移、网络依赖或铺满算法改动，schema 1保留。动作前仍校验权限、前台目标、存储忙等条件。

Engine集成测试覆盖统一子菜单、payload、显式禁用、原有持久化/文件选择/撤销和两级深度。独立性能脚本变化不增加应用计时器。
