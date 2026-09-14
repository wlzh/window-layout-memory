# 应用图标与打包门禁

build 26安装脚本在资源及签名验证后更新应用目录修改时间，并定向刷新LaunchServices注册。此前Launchpad沿用旧目录时间，单独重新注册及重启Dock未解决；更新时间后用户确认图标恢复。此步骤不清空Launchpad排列，也不修改已签名的程序内容。

0.3.0-preview.18 / build 25修复安装包缺少应用图标的问题。Finder应用图标与关于窗口使用同一彩色布局图形；菜单栏继续使用单色系统符号，适应明暗菜单栏。LSUIElement保持开启，因此不在Dock常驻不是图标丢失。

![应用图标](assets/app-icon.png)

## 资源来源

BrandIcon.swift为可重现绘制源，无外部图片依赖或网络请求。生成器输出16到1024像素共10个标准iconset表示，再由iconutil生成Resources/AppIcon.icns。Info.plist以CFBundleIconFile引用该文件；启动及关于窗口优先加载安装包资源，非打包调试运行使用程序绘制回退。共享图标缓存一次，不添加轮询。

## 构建和校验

- `zsh scripts/generate-icon.sh` 生成全部分辨率并校验尺寸、透明边缘和不透明内容。
- `zsh scripts/build-app.sh` 生成、复制图标，签名后校验；资源错误直接失败。
- `zsh scripts/check-app.sh "/Applications/Window Layout Memory.app"` 检查图标引用、资源与源码产物一致、解码后的10个表示及签名；在本项目完成构建后运行。
- `zsh scripts/test-icon-check.sh` 用临时包确认正确资源通过、缺图标和错误引用被拒绝。
- `zsh scripts/test-all.sh` 包含图标生成、核心/引擎/预览/关于、文档及元数据检查；关于测试覆盖共享图标与明暗布局。最终安装包检查还需运行build-app.sh。

安装脚本在替换前后均执行包校验。不会清理系统图标缓存、修改用户布局数据或增加辅助功能权限。安装后的系统图标显示和授权状态见[测试报告](TESTING.md)。
