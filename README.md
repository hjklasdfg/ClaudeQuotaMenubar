# ClaudeQuotaMenubar

[English](README.md) | [中文](README_CN.md)

A native macOS menu bar app that displays your Claude Pro/Max subscription usage in real-time.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-6-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu bar display** — Shows 5-hour usage percentage at a glance
- **Detailed breakdown** — 5-hour / 7-day / Opus / Sonnet usage
- **Hourly trend** — Shows usage change in the last hour
- **Trend chart** — Line graph with 24h / 7d / 30d time ranges (SwiftUI Charts)
- **In-app login** — Log in to claude.ai directly within the app (email login supported)
- **Auto refresh** — Polls every 5 minutes + manual refresh
- **Launch at login** — Optional via macOS ServiceManagement
- **Secure storage** — Credentials stored in macOS Keychain

## Screenshot

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

## Install

### Option 1: Download Pre-built App (Recommended)

1. Download `ClaudeQuotaMenubar.zip` from the [latest release](https://github.com/hjklasdfg/ClaudeQuotaMenubar/releases/latest)
2. Unzip and drag `ClaudeQuotaMenubar.app` to `/Applications`
3. Double-click to open (or right-click → Open on first launch)

### Option 2: Build from Source

See [Build & Install](#build--install) below.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ (to build from source)
- Claude Pro or Max subscription

## Build & Install

1. Clone the repo:
   ```bash
   git clone https://github.com/hjklasdfg/ClaudeQuotaMenubar.git
   ```

2. Open in Xcode:
   ```bash
   cd ClaudeQuotaMenubar
   open ClaudeQuotaMenubar/ClaudeQuotaMenubar.xcodeproj
   ```

3. Build and run (Cmd+R)

4. (Optional) To install permanently: Product → Archive → Distribute App → Copy App → drag to `/Applications`

## Setup

### Option 1: In-app Login (Recommended)

1. Click the menu bar icon → Settings → **Login with Claude**
2. Log in with your email (enter email → check inbox for verification code)
3. After login, credentials are extracted automatically

> **Note:** Google login may not work in the embedded browser due to passkey/2FA restrictions. Use email login instead.

### Option 2: Manual Entry

If in-app login doesn't work, you can enter credentials manually:

1. Open your browser and go to [claude.ai](https://claude.ai) and log in
2. Open DevTools (F12) → **Application** → **Cookies** → `claude.ai`
3. Find `sessionKey` — the value starts with `sk-ant-sid02-`
4. For Organization ID, go to **Console** tab and run:
   ```js
   fetch('/api/organizations').then(r=>r.json()).then(d=>console.log(d[0].uuid))
   ```
5. Click the menu bar icon → Settings → expand **Advanced** → paste both values → Save

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
- Your session key may expire; you can re-login from Settings
- Use at your own risk

## License

MIT
