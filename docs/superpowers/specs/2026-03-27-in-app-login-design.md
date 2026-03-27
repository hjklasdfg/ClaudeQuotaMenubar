# In-App Login for ClaudeQuotaMenubar

## Problem

Current onboarding requires users to open browser DevTools, find sessionKey from cookies, and extract orgId from network requests. This is too technical for most users.

## Solution

Add an in-app login flow using WKWebView that loads claude.ai's login page directly. Users log in normally (Google, email, etc.), and the app extracts credentials automatically.

## Architecture

### New Component: LoginWebView

A WKWebView wrapped in an NSWindow that handles the login flow.

**Behavior:**
- Loads `https://claude.ai/login` in a WKWebView with persistent `WKWebsiteDataStore` (required for Google OAuth and other third-party login flows)
- Implements `WKHTTPCookieStoreObserver` to monitor cookie changes
- Login success is detected when a `sessionKey` cookie appears (value starts with `sk-ant-sid01-`)
- On success, executes a JS fetch to `https://claude.ai/api/organizations` to retrieve the user's organization ID (first org's UUID)
- Stores both sessionKey and orgId into Keychain via `KeychainService`
- Closes the login window and notifies `AppState` via a callback

**Window properties:**
- Resizable, appropriate size for a login page (~800x700)
- Title: "Login to Claude"
- Destroyed after login completes or user closes it

### Modified: SettingsView

New layout with three sections:

1. **Login section** (top):
   - "Login with Claude" button that opens LoginWebView
   - Status indicator: logged in / not logged in

2. **Advanced section** (collapsible, collapsed by default):
   - Manual input fields for sessionKey and orgId (existing functionality)
   - Save button for manual credentials

3. **General section** (unchanged):
   - Launch at login toggle

### Modified: AppState

**First launch:**
- If `keychain.hasCredentials` is false, open LoginWebView automatically

**Session expiry detection:**
- When QuotaFetcher returns an error (401/403, HTML response, API failure), treat it as session expired
- Set menu bar to `C ⚠️` error state
- Automatically open LoginWebView for re-authentication
- If user closes LoginWebView without completing login, keep `C ⚠️` state; retry on next refresh cycle

**Post-login:**
- On successful login (new or re-auth), update Keychain, reset QuotaFetcher with new credentials, resume polling

## Files Changed

| File | Change |
|------|--------|
| `LoginWebView.swift` (new) | WKWebView login window with cookie observation and org fetching |
| `SettingsView.swift` | New layout: login button + status, collapsible advanced section, general |
| `AppState` (likely `ClaudeQuotaMenubarApp.swift`) | First-launch detection, session expiry handling, login window management |

## Files Not Changed

- `QuotaFetcher.swift` — no changes, continues to receive sessionKey/orgId as before
- `KeychainService.swift` — no changes, existing save/load API is sufficient
- `QuotaStore.swift` — no changes

## Flow Diagrams

### First Launch
```
App launch → Keychain empty → open LoginWebView
→ User logs in (Google/email/any method)
→ sessionKey cookie detected → fetch /api/organizations → get orgId
→ Save to Keychain → close window → create QuotaFetcher → start polling
```

### Session Expiry
```
QuotaFetcher fails → menu bar shows C ⚠️ → open LoginWebView
→ User re-authenticates → credentials updated → reset QuotaFetcher → resume polling
```

### Settings Manual Entry
```
User opens Settings → expands Advanced → enters sessionKey + orgId → Save
→ Keychain updated → reset QuotaFetcher → resume polling
```
