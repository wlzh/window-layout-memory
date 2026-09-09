# 技术与上下游影响

Preferences增加stageExcludedApplications字典（Bundle ID到显示名称），旧数据缺省空，最多200项、每字段非空且最多1024字节。schema 1、profiles/history及窗口身份不变，备份编码自动包含新偏好。降级写入可能丢弃未知偏好，应先备份。

上游：NSWorkspace运行列表或NSOpenPanel选择.app，经Bundle读取身份和名称，不存路径/书签、不启动应用。UniformTypeIdentifiers是系统框架，无第三方依赖。下游：Engine.stagePermits检查Bundle ID，沿用设置持久化和generation取消；当前横屏铺满被排除时阻断恢复/学习旁路。普通模式的窗口核对照常，全局excludedBundles不变。

SizeFirstPlacement新增可选prepare/prepared注入阶段：首次尺寸读回失败后，AXService仅对同屏且原位置不能容纳目标的可读窗口，枚举Zoom/FullScreen按钮的动作。仅选择明确提供的AXZoomWindow，绝不AXPress。准备、尺寸读回各有4次150 ms上限，最多一次原生缩放；准备后再设尺寸、核验，最后写位置。焦点/鼠标/权限/组合/设置仍由allowed检查。跨屏不做回退。失败也读回实际几何，因为原生动作自身可能改变窗口。

新增核心纯函数、注入时序测试、Engine应用例外持久化和原生文件选择器配置测试。无API服务、SQL、新常驻定时器、录屏或键盘监听。
