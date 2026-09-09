# 技术方案

删除Platform.fill中的AXZoomWindow调用、按钮动作枚举和准备阶段。SizeFirstPlacement删除prepare/prepared参数及原生缩放辅助函数；唯一调用者同步。成功路径仍为尺寸写入、最多4次150 ms核验、位置写入、一次终验，无新轮询。

以失败/取消/不可读几何保持原位置的回归替换已删除功能的测试。窗口匹配、Engine状态机、Preferences、schema 1、组合标识无修改，无数据库迁移或外部依赖。
