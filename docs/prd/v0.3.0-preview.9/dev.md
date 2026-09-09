# 技术设计

新增LayoutCore.EdgeAnchoredPlacement，四边线性插值，每步不超过32 pt，最多128步。扩展起点边时小步位置/尺寸成对写入，收缩先尺寸，保持计划中的固定边。逐步读回，最多4次、间隔30 ms；适配器每次写入前检查8秒截止及原有权限、焦点、鼠标、组合、偏好保护。

Platform.fill仅对同屏使用新算法，跨屏保留SizeFirstPlacement，普通move不变。写入非原子，取消不强制回滚。无原生缩放动作、无空闲轮询。

Engine.enqueue比较实时授权与缓存，变化时进入displayChanged稳定期；原有refresh更新状态后继续扫描，避免递归。没有新依赖、外部API、偏好字段或schema迁移。EngineChecks注入授权变化，CoreTests模拟右下屏幕限制及各失败阶段。
