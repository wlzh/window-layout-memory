# v0.3.0 技术

LayoutCore新增StageFill纯几何策略。Preferences新增stageFill和stageInsets，缺失字段默认关闭/空。保留schema 1，验证条目数量、键长度和有限非负宽度；旧版本忽略新增字段，降级再写可能丢失新偏好。

Engine在稳定前台批次里先处理铺满，再处理普通恢复。独立激活尝试集合避免AX反馈循环；左边缘手势使用现有按下/松开证据，留白写入现有串行原子存储，不改profiles/history。写入期间下一次目标核对合并排队，代际变化取消延迟移动。

Platform注入stageManagerEnabled与stageDisplay以便测试。生产只读CFPreferences和NSScreen；系统状态未知失败关闭。AX移动沿用逐步权限/焦点/鼠标/拓扑检查，额外重验实时目标工作区。不新增第三方依赖、周期扫描或录屏权限。对外服务接口无新增网络API。

导入关闭新模式。测试使用假AX与真实Engine，另需人工验证操作系统偏好读取及实际应用尺寸限制。
