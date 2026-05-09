# APIStatusBar

APIStatusBar 是一个为 New API / Kaizo 网关准备的 macOS 菜单栏工具。它把余额、请求量、服务可用性和模型使用情况收进一个轻量弹窗里，适合长期挂在右上角做日常监控。

界面重点很明确：余额用人民币显示，服务状态用连续探针呈现，常用模型直接显示图标和具体名称；展开后可以查看 90 天用量热力图。

## 功能

- 菜单栏常驻图标，低余额或连接异常时会变色提示
- 账户余额、已用额度、请求数和刷新时间一屏可见
- 服务探针显示当前可用性、延迟、24 小时可用率和最近心跳
- 常用模型以 provider icon + model name 呈现
- 90 天用量热力图，支持查看花费、请求、活跃天数、峰值日和连续使用天数
- 设置页支持服务器地址、系统访问令牌、连接验证、刷新间隔和低余额提醒
- Access Token 存入 macOS Keychain，不写入 UserDefaults

## 使用要求

- macOS 26.0 或更新版本
- 一套可访问的 New API / Kaizo 网关
- Web 控制台里的系统访问令牌

令牌不是 `sk-...` API Key，而是个人设置里的系统访问令牌。浏览器登录态不会被静默读取；应用只会打开控制台页面，并读取你主动复制到剪贴板的令牌。

## 从源码运行

```bash
git clone <this repo>
cd APIStatusBar
open APIStatusBar.xcodeproj
```

在 Xcode 里运行 `APIStatusBar` scheme。启动后，菜单栏右侧会出现应用图标。

## 首次配置

1. 点击菜单栏图标，打开设置。
2. 填入服务器地址，例如 `https://www.kaizo.top`。
3. 在控制台生成系统访问令牌，复制后回到设置页读取剪贴板。
4. 点击“验证连接”。
5. 关闭设置页，弹窗会自动刷新余额和状态。

## 项目结构

```text
APIStatusBar/
  APIStatusBarApp.swift          AppKit status item and settings window
  Core/                          networking, polling, Keychain, formatting
  UI/                            SwiftUI popover, settings, dashboard
  UI/Dashboard/                  heatmap and usage widgets
APIStatusBarTests/               unit tests
```

## 测试

```bash
xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar test
```

Keychain 测试默认跳过，避免写入用户登录钥匙串。需要显式运行时设置：

```bash
APISTATUSBAR_RUN_KEYCHAIN_TESTS=1 xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar test
```

## Credits

Provider icons are from [lobehub/lobe-icons](https://github.com/lobehub/lobe-icons) under the MIT license.
