# 技术设计

AXService.fill固定调用SizeFirstPlacement的positionFirst路径：权限、焦点、鼠标、几何、可写属性检查后，先写位置，再次检查取消，再写尺寸；最多4次150 ms读回，最后核对完整矩形。位置先写路径不重复写位置，无原生缩放和回滚。

移除未发布的PlacementProofs及Engine接入，WindowService.fill接口恢复原样，普通move及Engine行为不变。保留事务级辅助兼容属性恢复，schema仍为1，无新数据、依赖、缓存或定时器。

新增接口：无。改动接口：核心放置函数增加默认false的positionFirst参数；生产铺满固定传true，旧默认路径保留为回归参照。删除接口：未发布的成功记录实验接口。
