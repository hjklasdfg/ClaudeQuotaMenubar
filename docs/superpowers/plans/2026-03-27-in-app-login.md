# In-App Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace manual DevTools credential extraction with an in-app WKWebView login that supports all auth methods.

**Architecture:** New `LoginWebView` component handles login via WKWebView + cookie observation. `SettingsView` gets a new layout with login button + collapsible advanced section. `AppState` gains session expiry detection and auto-relogin.

**Tech Stack:** Swift 6, SwiftUI, WebKit (WKWebView, WKHTTPCookieStoreObserver)

**Spec:** `docs/superpowers/specs/2026-03-27-in-app-login-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Views/LoginWebView.swift` | Create | WKWebView login window, cookie observation, org ID fetching |
| `Views/SettingsView.swift` | Modify | New layout: login button + status, collapsible advanced, general |
| `ClaudeQuotaMenubarApp.swift` | Modify | AppState: session expiry detection, login window management; App: add login Window scene |
| `Views/MenuBarView.swift` | Modify | Show warning icon on session expiry |

All paths relative to `ClaudeQuotaMenubar/ClaudeQuotaMenubar/ClaudeQuotaMenubar/`.

---

### Task 1: LoginWebView — Cookie Observation and Credential Extraction

**Files:**
- Create: `Views/LoginWebView.swift`
- Test: `ClaudeQuotaMenubarTests/LoginWebViewTests.swift` (for org ID parsing logic)

- [ ] **Step 1: Write test for organization ID parsing**

The `/api/organizations` response is a JSON array of org objects. Write a test for parsing:

```swift
// ClaudeQuotaMenubarTests/LoginWebViewTests.swift
import XCTest
@testable import ClaudeQuotaMenubar

final class LoginWebViewTests: XCTestCase {
    func testParseOrganizationId() throws {
        let json = """
        [
            {
                "uuid": "abc12345-1234-5678-9abc-def012345678",
                "name": "Personal",
                "settings": {}
            }
        ]
        """
        let orgId = LoginCredentialExtractor.parseOrganizationId(from: json)
        XCTAssertEqual(orgId, "abc12345-1234-5678-9abc-def012345678")
    }

    func testParseOrganizationIdEmptyArray() {
        let json = "[]"
        let orgId = LoginCredentialExtractor.parseOrganizationId(from: json)
        XCTAssertNil(orgId)
    }

    func testParseOrganizationIdInvalidJSON() {
        let orgId = LoginCredentialExtractor.parseOrganizationId(from: "not json")
        XCTAssertNil(orgId)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme ClaudeQuotaMenubar -destination 'platform=macOS' -only-testing:ClaudeQuotaMenubarTests/LoginWebViewTests 2>&1 | tail -20`
Expected: FAIL — `LoginCredentialExtractor` not defined.

- [ ] **Step 3: Implement LoginCredentialExtractor**

```swift
// Add to Views/LoginWebView.swift (top of file, before the view)
import Foundation

enum LoginCredentialExtractor {
    static func parseOrganizationId(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let uuid = first["uuid"] as? String else {
            return nil
        }
        return uuid
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme ClaudeQuotaMenubar -destination 'platform=macOS' -only-testing:ClaudeQuotaMenubarTests/LoginWebViewTests 2>&1 | tail -20`
Expected: PASS — all 3 tests green.

- [ ] **Step 5: Implement LoginWebView**

```swift
// Views/LoginWebView.swift (add below LoginCredentialExtractor)
import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    let keychain: KeychainService
    let onLoginSuccess: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(keychain: keychain, onLoginSuccess: onLoginSuccess)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView

        // Observe cookie changes
        config.websiteDataStore.httpCookieStore.add(context.coordinator)

        // Load login page
        let url = URL(string: "https://claude.ai/login")!
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    @MainActor
    class Coordinator: NSObject, WKHTTPCookieStoreObserver {
        let keychain: KeychainService
        let onLoginSuccess: () -> Void
        weak var webView: WKWebView?
        private var hasCompleted = false

        init(keychain: KeychainService, onLoginSuccess: @escaping () -> Void) {
            self.keychain = keychain
            self.onLoginSuccess = onLoginSuccess
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in
                await self.checkForSessionKey(in: cookieStore)
            }
        }

        private func checkForSessionKey(in cookieStore: WKHTTPCookieStore) async {
            guard !hasCompleted else { return }

            let cookies = await cookieStore.allCookies()
            guard let sessionCookie = cookies.first(where: {
                $0.name == "sessionKey" && $0.value.hasPrefix("sk-ant-sid01-")
            }) else { return }

            hasCompleted = true
            keychain.save(account: "sessionKey", value: sessionCookie.value)

            // Fetch organization ID
            await fetchOrganizationId(sessionKey: sessionCookie.value)
        }

        private func fetchOrganizationId(sessionKey: String) async {
            guard let webView else { return }

            let js = """
                try {
                    const response = await fetch('https://claude.ai/api/organizations', {
                        method: 'GET',
                        credentials: 'include',
                        headers: { 'accept': 'application/json' }
                    });
                    const data = await response.json();
                    return JSON.stringify(data);
                } catch (e) {
                    return JSON.stringify([]);
                }
            """

            do {
                let result = try await webView.callAsyncJavaScript(
                    js, arguments: [:], contentWorld: .page
                )
                if let jsonString = result as? String,
                   let orgId = LoginCredentialExtractor.parseOrganizationId(from: jsonString) {
                    keychain.save(account: "organizationId", value: orgId)
                    onLoginSuccess()
                }
            } catch {
                // Org fetch failed — user can retry or use manual entry
            }
        }
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add Views/LoginWebView.swift ../ClaudeQuotaMenubarTests/LoginWebViewTests.swift
git commit -m "feat: add LoginWebView with cookie-based credential extraction"
```

---

### Task 2: Add Login Window Scene to App

**Files:**
- Modify: `ClaudeQuotaMenubarApp.swift`

- [ ] **Step 1: Add `showLogin` state and login window scene**

In `AppState`, add a new property:

```swift
// In AppState, add alongside existing properties:
var showLogin = false
```

In `ClaudeQuotaMenubarApp`, add a new `Window` scene:

```swift
// In ClaudeQuotaMenubarApp body, add after the "Usage Trend" Window:
Window("Login to Claude", id: "login") {
    LoginWebView(keychain: state.keychain, onLoginSuccess: {
        state.onCredentialsSaved()
        state.showLogin = false
    })
    .frame(minWidth: 800, minHeight: 700)
}
.windowResizability(.contentMinSize)
```

- [ ] **Step 2: Update startPolling to open login instead of settings**

In `AppState.startPolling()`, change the no-credentials branch:

```swift
// Before:
guard keychain.hasCredentials else {
    showSettings = true
    return
}

// After:
guard keychain.hasCredentials else {
    showLogin = true
    return
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -scheme ClaudeQuotaMenubar -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add ClaudeQuotaMenubarApp.swift
git commit -m "feat: add login window scene and wire to app launch"
```

---

### Task 3: Redesign SettingsView

**Files:**
- Modify: `Views/SettingsView.swift`

- [ ] **Step 1: Rewrite SettingsView with new layout**

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    let keychain: KeychainService
    let onSave: () -> Void

    @State private var sessionKey: String = ""
    @State private var organizationId: String = ""
    @State private var showingSessionKey = false
    @State private var showAdvanced = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var isLoggedIn: Bool {
        keychain.hasCredentials
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude Quota Settings")
                .font(.headline)

            // MARK: - Login Section
            GroupBox("Account") {
                HStack {
                    Circle()
                        .fill(isLoggedIn ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(isLoggedIn ? "Logged in" : "Not logged in")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Login with Claude") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "login")
                    }
                }
                .padding(8)
            }

            // MARK: - Advanced Section
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session Key")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            if showingSessionKey {
                                TextField("sk-ant-sid01-...", text: $sessionKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("sk-ant-sid01-...", text: $sessionKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button(showingSessionKey ? "Hide" : "Show") {
                                showingSessionKey.toggle()
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Organization ID")
                            .font(.subheadline).foregroundStyle(.secondary)
                        TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $organizationId)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Spacer()
                        Button("Save Credentials") {
                            keychain.save(account: "sessionKey", value: sessionKey)
                            keychain.save(account: "organizationId", value: organizationId)
                            onSave()
                        }
                        .disabled(sessionKey.isEmpty || organizationId.isEmpty)
                    }
                }
                .padding(8)
            }

            // MARK: - General Section
            GroupBox("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
                    .padding(8)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            sessionKey = keychain.sessionKey ?? ""
            organizationId = keychain.organizationId ?? ""
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme ClaudeQuotaMenubar -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Views/SettingsView.swift
git commit -m "feat: redesign SettingsView with login button and collapsible advanced section"
```

---

### Task 4: Session Expiry Detection and Auto-Relogin

**Files:**
- Modify: `ClaudeQuotaMenubarApp.swift` (AppState)
- Modify: `Views/MenuBarView.swift`

- [ ] **Step 1: Add session expired state to AppState**

In `AppState`, add a new property alongside existing ones:

```swift
var sessionExpired = false
```

- [ ] **Step 2: Update refresh() error handling for session expiry**

In `AppState.refresh()`, replace the `catch` block:

```swift
// Before:
} catch {
    consecutiveFailures += 1
    errorMessage = error.localizedDescription

    fetcher.reset()
    setupFetcher()
}

// After:
} catch {
    consecutiveFailures += 1
    errorMessage = error.localizedDescription

    fetcher.reset()
    setupFetcher()

    // Treat repeated failures as session expiry
    if consecutiveFailures >= 2 {
        sessionExpired = true
        showLogin = true
    }
}
```

- [ ] **Step 3: Reset sessionExpired on successful login**

In `AppState.onCredentialsSaved()`, add:

```swift
func onCredentialsSaved() {
    sessionExpired = false
    consecutiveFailures = 0
    setupFetcher()
    Task { await refresh() }
}
```

- [ ] **Step 4: Update statusText and statusColor for expiry state**

In `AppState`, update:

```swift
var statusText: String {
    if sessionExpired { return "⚠️" }
    if let util = fiveHourUtil {
        return "\(Int(util))%"
    }
    return "--"
}

var statusColor: Color {
    if sessionExpired { return .red }
    guard let util = fiveHourUtil else { return .gray }
    return UsageColor.for(utilization: util)
}
```

- [ ] **Step 5: Build and verify**

Run: `xcodebuild build -scheme ClaudeQuotaMenubar -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Run all existing tests**

Run: `xcodebuild test -scheme ClaudeQuotaMenubar -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests pass (existing + new LoginWebViewTests).

- [ ] **Step 7: Commit**

```bash
git add ClaudeQuotaMenubarApp.swift Views/MenuBarView.swift
git commit -m "feat: add session expiry detection with auto-relogin"
```

---

### Task 5: Open Login Window Programmatically

SwiftUI's `openWindow(id:)` is only available in View context via `@Environment`. We need a way for `AppState` to trigger opening the login window.

**Files:**
- Modify: `ClaudeQuotaMenubarApp.swift`

- [ ] **Step 1: Wire showLogin to openWindow in the App body**

In `ClaudeQuotaMenubarApp`, add an `.onChange` modifier to trigger window opening when `showLogin` becomes true:

```swift
// In the MenuBarExtra section, add a modifier to the label or use an overlay approach.
// The simplest way: add a background view that watches the state.

// Replace the existing MenuBarExtra in ClaudeQuotaMenubarApp.body:
MenuBarExtra {
    MenuBarView(state: state)
} label: {
    Text("C \(state.statusText)")
        .monospacedDigit()
}

// Add a helper Window that auto-opens. Alternatively, use the onChange approach:
// After the MenuBarExtra, add a Settings scene or use .defaultAppStorage.

// Simplest approach: In MenuBarView, watch state.showLogin and open the window:
```

Actually, the cleanest approach is to handle this in `MenuBarView` since it has `@Environment(\.openWindow)`:

In `MenuBarView`, add at the end of the body (before the closing `}`):

```swift
// At the bottom of MenuBarView body, after the Quit button:
.onChange(of: state.showLogin) { _, shouldShow in
    if shouldShow {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "login")
        state.showLogin = false
    }
}
```

Wrap the entire MenuBarView body content in a `VStack` or `Group` to attach the modifier (since it's a menu, use `Group`):

```swift
// MenuBarView body becomes:
var body: some View {
    Group {
        // ... all existing menu items ...
    }
    .onChange(of: state.showLogin) { _, shouldShow in
        if shouldShow {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "login")
            state.showLogin = false
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme ClaudeQuotaMenubar -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Views/MenuBarView.swift ClaudeQuotaMenubarApp.swift
git commit -m "feat: wire programmatic login window opening via MenuBarView onChange"
```

---

### Task 6: Clean Up WKWebView Data Store on Logout/Re-login

When a user needs to re-login (session expired), the persistent WKWebView data store may hold stale cookies. Clear it before showing login.

**Files:**
- Modify: `Views/LoginWebView.swift`

- [ ] **Step 1: Clear old cookies before loading login page**

In `LoginWebView.makeNSView()`, add cookie cleanup before loading:

```swift
func makeNSView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()

    let webView = WKWebView(frame: .zero, configuration: config)
    context.coordinator.webView = webView

    // Clear stale cookies before login
    let cookieStore = config.websiteDataStore.httpCookieStore
    cookieStore.add(context.coordinator)

    Task {
        let cookies = await cookieStore.allCookies()
        for cookie in cookies where cookie.domain.contains("claude.ai") {
            await cookieStore.deleteCookie(cookie)
        }
        // Load login page after cleanup
        let url = URL(string: "https://claude.ai/login")!
        webView.load(URLRequest(url: url))
    }

    return webView
}
```

Remove the direct `webView.load()` call that was previously at the bottom of `makeNSView`.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild build -scheme ClaudeQuotaMenubar -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -scheme ClaudeQuotaMenubar -destination 'platform=macOS' 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add Views/LoginWebView.swift
git commit -m "feat: clear stale claude.ai cookies before re-login"
```

---

### Task 7: Manual Testing

- [ ] **Step 1: Test first-launch flow**

1. Delete Keychain entries: open Keychain Access, search "com.claude-quota-menubar", delete both items
2. Launch app
3. Verify login window opens automatically
4. Log in via Google/email
5. Verify: login window closes, menu bar shows usage percentage

- [ ] **Step 2: Test settings UI**

1. Open Settings from menu bar
2. Verify: "Logged in" status shown with green dot
3. Expand Advanced section
4. Verify: sessionKey and orgId fields are populated
5. Click "Done" to close

- [ ] **Step 3: Test session expiry**

1. Open Keychain Access, modify the sessionKey value to something invalid
2. Wait for next refresh (or click Refresh)
3. Verify: after 2 failures, menu bar shows `C ⚠️` and login window opens
4. Re-login
5. Verify: menu bar recovers to normal usage display

- [ ] **Step 4: Test manual credential entry**

1. Open Settings → expand Advanced
2. Enter sessionKey and orgId manually
3. Click "Save Credentials"
4. Verify: app starts fetching usage data
