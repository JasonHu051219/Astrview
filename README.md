# Astrview

用 Swift、AppKit 和 WKWebView 编写的原生 macOS AstrBot 管理器。不依赖 Electron、完整的 Xcode 或第三方 Swift 库。

## 构建和运行

需要 macOS 13 或更高版本、Xcode Command Line Tools，以及已安装的 AstrBot CLI 和已初始化的项目。

```bash
bash build.sh
open build/Astrview.app
```

启动时只显示一个无边框的悬浮按钮。应用会查找含 `.astrbot` 的项目根目录，找不到时会提示选择。也可以从 Astrview 菜单手动选择项目。应用优先使用项目的 `.venv/bin/astrbot`，其次从 `PATH` 和常见安装目录查找。

- 点击「运行astrbot」：在后台启动，悬浮按钮显示「正在启动…」，收到就绪日志后自动隐藏。点 Dock 图标或菜单中的「打开 Astrview」可打开管理窗口。
- 从右侧下拉菜单选择「启动astrbot（不隐藏）」：立即打开终端窗口并显示启动日志。收到 `AstrBot v… WebUI is ready` 后，窗口扩大至显示器可用区域（保留菜单栏与 Dock），终端停靠在底部，上方显示 `http://localhost:6185`。

管理界面打开后，可以拖动底部终端的上边缘来调整高度。终端右上角的细方框用于最大化或恢复；细横线把终端收成底部标题栏，日志仍会继续记录。

`astrbot run` 通过系统 `/bin/zsh` 执行，无法启动 zsh 时回退到 `/bin/bash`。内嵌终端显示标准输出和标准错误，可选择和复制，不提供交互式 Shell。若启动失败，可查看日志并点「重试」。

关闭管理窗口不会停止 AstrBot；退出 Astrview（⌘Q）才会停止由它启动的进程。WebUI 只在本机提供，不改写仪表板配置文件。

## 验证

```bash
bash test.sh
```

测试需要登录 macOS 图形会话。脚本使用位于 `build/` 的模拟项目和随机的本地测试端口，不启动实际的 AstrBot 或读取其配置。
