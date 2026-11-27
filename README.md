# Astrview

Astrview 是一个用于启动和管理 [AstrBot](https://github.com/AstrBotDevs/AstrBot) 的原生 macOS 应用。它用 Swift 和 AppKit 显示启动日志，使用 WKWebView 打开 AstrBot 自带的控制面板。不依赖 Electron，也不需要安装完整的 Xcode。

## 快速开始

1. 确认系统为 **macOS 13 或更新版本**，并已安装 AstrBot CLI、准备好包含 `.astrbot` 标记的项目目录。已有项目不用重新初始化。
2. 从 [GitHub Releases](https://github.com/JasonHu051219/Astrview/releases) 下载可用的 `.app`，或按下文从源码构建。
3. 打开应用，点「运行astrbot」。如果没有找到项目，选择已有的 AstrBot 项目根目录；也可以通过启动面板右侧齿轮进入设置，提前选择目录。

默认勾选「启动后隐藏」。**无论是否勾选，启动时都会打开窗口显示日志**。收到 `AstrBot v… WebUI is ready` 后，勾选时会先收起窗口，AstrBot 继续运行；取消勾选时会直接打开管理界面。

## 日常使用

| 功能 | 操作 |
| --- | --- |
| 打开管理窗口 | 点菜单栏的机器人图标 →「打开 Astrview」，或点 Dock 图标 |
| 调整终端高度 | 拖动底部日志面板的上沿；点细方框最大化或恢复，点细横线收起到标题栏 |
| 更改启动偏好 | 在设置里切换「显示 Dock 图标」和「启动后隐藏」；两项都会保存 |
| 查看运行状态 | 打开菜单栏机器人菜单；即使隐藏 Dock 图标，菜单栏入口仍保留 |
| 停止 AstrBot | 从菜单栏选择「退出 Astrview」，或在应用激活时按 `⌘Q`；仅关闭管理窗口不会停止进程 |

管理界面保留 macOS 菜单栏与 Dock，不会进入系统全屏模式。WebUI 地址为 `http://localhost:6185`；Astrview 启动的实例使用本机回环地址，不改写 AstrBot 的仪表板配置文件。

## 从源码构建

需要 **Xcode Command Line Tools**；未安装时执行 `xcode-select --install`。构建使用本机架构，由系统工具完成本地签名，不需要安装第三方 Swift 或图标处理依赖。

```bash
git clone https://github.com/JasonHu051219/Astrview.git
cd Astrview
bash build.sh
open build/Astrview.app
```

## 常见问题

- **找不到 `astrbot`**：Astrview 优先使用项目中的 `.venv/bin/astrbot`，其次查看继承的 `PATH` 和常见安装目录。如果命令只在交互式 Shell 中可用，建议将 AstrBot CLI 安装到常见目录（例如 `~/.local/bin`），或放在项目虚拟环境中。
- **看不到自己的 zsh 主题**：日志面板不是交互式终端。应用优先通过系统 `/bin/zsh` 执行 `astrbot run`，无法启动 zsh 时才回退 `/bin/bash`，并实时捕获标准输出和错误。它不会加载交互式 zsh 主题或提示符，也不能输入命令。
- **界面没打开或端口冲突**：先从菜单栏打开 Astrview，看终端日志是否输出就绪信息。确认 `6185` 未被其他服务占用、AstrBot 的 WebUI 已启用。如果已有 AstrBot 实例，不要同时启动第二个实例。

## 测试

```bash
bash test.sh
```

冒烟测试需要登录 macOS 图形会话。它使用模拟项目和随机本地端口，覆盖启动和隐藏、菜单栏与 Dock 开关、WebView、日志面板以及进程退出，不会启动真实的 AstrBot。

## 许可证

Astrview 采用 [MIT 许可证](LICENSE)，与上游 AstrBot 项目独立。
