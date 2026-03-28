# ClaudeQuotaMenubar

[English](README.md) | [中文](README_CN.md)

一款原生 macOS 菜单栏应用，实时显示 Claude Pro/Max 订阅的用量情况。

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## 功能

- **菜单栏显示** — 一眼看到 5 小时用量百分比
- **详细分类** — 5 小时 / 7 天 / Opus / Sonnet 用量
- **小时趋势** — 显示最近 1 小时的用量变化
- **趋势图表** — 24 小时 / 7 天 / 30 天折线图（SwiftUI Charts）
- **应用内登录** — 直接在 app 内登录 claude.ai（支持邮箱登录）
- **自动刷新** — 每 5 分钟轮询 + 手动刷新
- **开机启动** — 基于 macOS ServiceManagement
- **安全存储** — 凭据存储在 macOS 钥匙串中

## 截图

```
C 58%
┌─────────────────────────────────────────────┐
│ 5h Usage: 58%  ↑1h: +1% (resets: 03:00)    │
│ 7d Usage: 5% (resets: in 6d)                │
│ ─────────────────────────────────────────── │
│ Sonnet (7d): 0%                             │
│ ─────────────────────────────────────────── │
│ 📈 Trend                                    │
│ ─────────────────────────────────────────── │
│ ⟳ Refresh                                   │
│ ⚙ Settings...                               │
│ ─────────────────────────────────────────── │
│ Quit                                        │
└─────────────────────────────────────────────┘
```

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- Xcode 15+（从源码编译时需要）
- Claude Pro 或 Max 订阅

## 编译安装

1. 克隆仓库：
   ```bash
   git clone https://github.com/hjklasdfg/ClaudeQuotaMenubar.git
   ```

2. 用 Xcode 打开：
   ```bash
   cd ClaudeQuotaMenubar
   open ClaudeQuotaMenubar/ClaudeQuotaMenubar.xcodeproj
   ```

3. 编译运行（Cmd+R）

4. （可选）永久安装：Product → Archive → Distribute App → Copy App → 拖入 `/Applications`

## 配置

### 方式一：应用内登录（推荐）

1. 点击菜单栏图标 → Settings → **Login with Claude**
2. 使用邮箱登录（输入邮箱 → 查收验证码）
3. 登录成功后凭据会自动提取

> **注意：** 由于 Passkey/2FA 限制，Google 登录在内嵌浏览器中可能无法使用，请使用邮箱登录。

### 方式二：手动输入

如果应用内登录不可用，可以手动输入凭据：

1. 在浏览器中打开 [claude.ai](https://claude.ai) 并登录
2. 打开开发者工具（F12）→ **Application** → **Cookies** → `claude.ai`
3. 找到 `sessionKey`，值以 `sk-ant-sid02-` 开头
4. 获取 Organization ID：切换到 **Console** 标签，运行：
   ```js
   fetch('/api/organizations').then(r=>r.json()).then(d=>console.log(d[0].uuid))
   ```
5. 点击菜单栏图标 → Settings → 展开 **Advanced** → 粘贴两个值 → Save

## 工作原理

应用使用一个隐藏的 WKWebView：

1. 导航到 `claude.ai`（通过 Cloudflare 验证）
2. 执行 JavaScript `fetch()` 请求内部用量 API
3. 解析响应并显示用量数据

用量历史存储在本地 SQLite 数据库中（`~/Library/Application Support/ClaudeQuotaMenubar/quota.db`），用于趋势图展示，数据保留 30 天。

## 安全与隐私

- **凭据存储在 macOS 钥匙串中** — 不以明文形式保存
- **Session Key 仅发送到 `claude.ai`** — 不会发送给任何第三方
- **所有数据留在本地** — 无分析、无遥测、无外部服务器
- **完全开源** — 可自行审计代码

## 免责声明

这是一个**非官方**工具，使用了 claude.ai 未公开的内部 API，可能随时变更。本项目与 Anthropic 没有任何关联。

- 内部 API 可能变更导致应用失效
- Session Key 可能过期，可在 Settings 中重新登录
- 使用风险自负

## 许可证

MIT
