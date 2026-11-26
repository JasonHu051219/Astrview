# Astrview

用 Swift、AppKit 和 WKWebView 编写的原生 macOS AstrBot 管理器。不依赖 Electron、完整的 Xcode 或第三方 Swift 库。

## 构建和运行

需要 macOS 13 或更高版本、Xcode Command Line Tools，以及已安装的 AstrBot CLI 和已初始化的项目。

```bash
bash build.sh
open build/Astrview.app
```

点击「运行astrbot」。应用会查找含 `.astrbot` 的项目根目录，包括应用所在目录及其父目录；找不到时会提示选择。也可以从 Astrview 菜单手动选择项目。应用优先使用项目的 `.venv/bin/astrbot`，其次从 `PATH` 和常见安装目录查找。

窗口先展开成终端大小并显示 `astrbot run` 的标准输出和标准错误。收到 `AstrBot v… WebUI is ready` 后，窗口会扩大至当前显示器的可用区域（保留菜单栏与 Dock，不进入原生全屏），终端停靠在底部，WebView 打开 `http://localhost:6185`。应用启动的实例仅在本机的 `127.0.0.1:6185` 提供 HTTP WebUI，不改写仪表板配置文件。关闭窗口或点击「停止」会停止应用启动的实例。

这个终端是日志面板，可以选择和复制文本，不提供交互式 Shell。启动失败时可查看输出，再点击「重试」。

## 验证

```bash
bash test.sh
```

测试需要登录 macOS 图形会话。脚本使用位于 `build/` 的模拟项目和随机的本地测试端口，不启动实际的 AstrBot 或读取其配置。
