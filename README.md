# ClaudeQuotaMenubar

A native macOS menu bar app that displays your Claude Pro/Max subscription usage in real-time.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu bar display** — Shows 5-hour usage percentage at a glance
- **Detailed breakdown** — 5-hour / 7-day / Opus / Sonnet usage
- **Hourly trend** — Shows usage change in the last hour
- **Trend chart** — Line graph with 24h / 7d / 30d time ranges (SwiftUI Charts)
- **Auto refresh** — Polls every 5 minutes + manual refresh
- **Launch at login** — Optional via macOS ServiceManagement
- **Secure storage** — Credentials stored in macOS Keychain

## Screenshot

```
C 58%
┌──────────────────────────────────────────┐
│ 5 小时用量：58%  ↑1h: +1%（重置：03:00）   │
│ 7 天用量：5%（重置：6 天后）                 │
│ ──────────────────────────────────────── │
│ Sonnet (7d)：0%                          │
│ ──────────────────────────────────────── │
│ 📈 查看趋势                               │
│ ──────────────────────────────────────── │
│ ⟳ 刷新                                   │
│ ⚙ 设置...                                │
│ ──────────────────────────────────────── │
│ 退出                                     │
└──────────────────────────────────────────┘
```

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (to build from source)
- Claude Pro or Max subscription

## Build & Install

1. Clone the repo:
   ```bash
   git clone https://github.com/RockyLi1986/ClaudeQuotaMenubar.git
   ```

2. Open in Xcode:
   ```bash
   cd ClaudeQuotaMenubar
   open ClaudeQuotaMenubar/ClaudeQuotaMenubar.xcodeproj
   ```

3. Build and run (Cmd+R)

4. (Optional) To install permanently: Product → Archive → Distribute App → Copy App → drag to `/Applications`

## Setup

On first launch, you need to provide your claude.ai credentials:

### Get your Session Key

1. Open your browser and go to [claude.ai](https://claude.ai)
2. Open DevTools (F12) → Application → Cookies → `claude.ai`
3. Find `sessionKey` — the value starts with `sk-ant-sid01-`

### Get your Organization ID

1. In DevTools → Network tab
2. Click on any request to claude.ai
3. Look at the Request URL — it contains `organizations/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/`
4. Copy that UUID

### Enter credentials

Click the menu bar icon → Settings → paste both values → Save.

## How it works

The app uses a hidden WKWebView to:

1. Navigate to `claude.ai` (to pass Cloudflare verification)
2. Execute a JavaScript `fetch()` to query the internal usage API
3. Parse the response and display usage data

Usage history is stored locally in SQLite (`~/Library/Application Support/ClaudeQuotaMenubar/quota.db`) for trend visualization. Data is retained for 30 days.

## Security & Privacy

- **Credentials are stored in macOS Keychain** — not in plain text files
- **Session key is only sent to `claude.ai`** — never to any third party
- **All data stays local** — no analytics, no telemetry, no external servers
- **Open source** — audit the code yourself

## Disclaimer

This is an **unofficial** tool. It uses undocumented claude.ai internal APIs that may change at any time without notice. This project is not affiliated with, endorsed by, or sponsored by Anthropic.

- The internal API may change, breaking this app
- Your session key may expire; you'll need to update it in Settings
- Use at your own risk

## License

MIT
