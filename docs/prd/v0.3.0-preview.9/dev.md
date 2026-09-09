# 技术设计

生产路径统一使用SizeFirstPlacement：请求目标尺寸、最多4次150 ms读回、尺寸误差各不超过2 pt后才写位置并终验。删除EdgeAnchoredPlacement及其专属实验测试；普通move不变。

已知未解决限制：在当前位置受右下边界钳制时，即使目标矩形可达，也可能一直无法达到目标尺寸，导致位置门禁停止。新增原点约束模型特征测试记录此问题，不将返回尺寸失败解释为应用不支持，不将此用例通过当作需求完成。当前Arc实机失败，详见[测试报告](../../TESTING.md)。

新增EnhancedUILease，仅当应用AXEnhancedUserInterface读为true、VoiceOver和Switch Control均关闭时临时写false。操作结束及释放时尝试恢复原true状态，显式finish幂等；恢复失败向状态面板报告。未知/false属性不改，不修改系统辅助功能设置，不持久保存，不添加轮询。原设置恢复后重新读取最终几何。

参考[Rectangle的兼容处理思路](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityElement.swift)，本项目独立实现事务生命周期与保护，不引入第三方代码或运行时依赖。该属性兼容性仍须实测，不是稳定系统契约。

Engine.enqueue同步实时权限与缓存，变化时重新进入稳定期再核对，修复授权后仍停滞。组合、匹配、偏好字段及schema 1不变，无数据迁移。
