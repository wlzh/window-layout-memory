# 子窗口策略技术与依赖

## 数据与上游

Preferences新增stageFillChildren（旧数据默认false）、stageExcludedKinds（默认空）。schema保持1，数据库校验最多200条唯一有效规则，每字段最多1024 UTF-8字节。布局、历史、留白结构不变。老版本再次写入会丢弃未知偏好，降级需备份。

AXService只对已扫描到的前台标准窗口补读role、AXModal及直接parent，父级非应用时补读其role；每次消息超时150 ms，不递归遍历、无新周期定时器。明确模态或未知角色/父级不参与铺满；缺失AXModal不推断模态关系。AXRecord携带StageWindowTraits，不写入布局身份或改变Matcher。

## 下游

StageWindowTraits允许应用下标准独立窗口，父级Window/Sheet下标准窗口由选项控制。StageWindowRule精确匹配bundle/identifier/role/subrole。Engine在ingest、目标计算、铺满入口和allowed闭包检查，防止自动恢复和学习旁路。偏好变更通过既有持久化和generation取消在途操作。临时token最多500个，仅内存保存，完整扫描确认窗口消失或应用退出时清理。

菜单读取缓存，不额外扫描；规则撤销通过既有setPreferences。普通模式和当前竖屏不受新增横屏跳过逻辑影响；完整显示器组合隔离、预览缓存、备份导入导出沿用原实现。自动恢复到目标屏幕依然要求唯一匹配。

## 依赖与接口影响

无新增第三方包、网络/API/SQL。新增核心纯策略类型，AXRecord新增非持久字段，Preferences增加可缺省字段，Engine增加规则与菜单访问方法。删除AppDelegate.resetStageInsets及其菜单。覆盖率脚本分母从Core.swift扩展到LayoutCore全部Swift文件，包含先尺寸后位置流程。
