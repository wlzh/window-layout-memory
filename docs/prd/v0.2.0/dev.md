# v0.2.0 技术实现

- LayoutCore提供PreviewScene、PreviewRow、PreviewObservation、PreviewTransform。全局左上角逻辑坐标按统一比例投影；差值保持有符号数值。
- Engine为每批成功返回数据关联拓扑键与读取时间。预览只消费缓存；拓扑过渡、授权失效时不提供当前观察值，保存数据仍可查看。
- 组合键不一致时，模型层排除当前观察值，UI层同时禁用不适用视图。
- LayoutPreviewController复用Engine.changed通知，DispatchWorkItem将事件刷新合并为最多10Hz；无自有周期扫描。
- LayoutCanvas使用NSView矢量绘制；NSTableView提供键盘选择与列表可访问性，详情使用原生可选择文本。
- 关闭取消任务、清空模型与闭包、解除委托并释放NSWindow；AppDelegate随后释放controller。弱引用测试检查controller/window/canvas析构。
- 不写布局、不移动窗口、不触发屏幕采集；唯一主动读取是打开入口时调用现有refresh一次。
- AppVersion统一从Info.plist读取版本、构建号及发行通道，调试CLI提供一致回退值。

数据schema保持1，不迁移或覆盖既有布局。截图测试仅渲染合成Fixture，调试测试入口不编译进release实现。
