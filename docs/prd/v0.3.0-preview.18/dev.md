# 正式应用图标：实现

BrandIcon.swift提供确定性绘制源及共享NSImage。构建生成16到1024像素的10个PNG表示，iconutil转为AppIcon.icns，Info.plist引用资源；启动和关于窗口共用安装资源，非打包调试时绘制回退。

build-app.sh和install-local.sh运行图标/签名门禁，check-app.sh核对引用、文件、生成源一致性和全部表示。负向测试在临时包模拟缺资源和错引用。test-all.sh新增文档及图标生成检查，无新依赖或定时器。
