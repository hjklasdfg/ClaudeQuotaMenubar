import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    let keychain: KeychainService
    let onSave: () -> Void
    let onLogout: () -> Void
    let onRelogin: () -> Void

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
                    if isLoggedIn {
                        Button("Log out") {
                            onLogout()
                        }
                    }
                    Button(isLoggedIn ? "Re-login" : "Login with Claude") {
                        onRelogin()
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "login")
                    }
                }
                .padding(8)
            }

            // MARK: - Advanced Section
            DisclosureGroup(isExpanded: $showAdvanced) {
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("How to find these values:")
                            .font(.subheadline).fontWeight(.medium)
                        Text("1. Open browser → claude.ai → log in")
                        Text("2. Open DevTools (F12) → Application → Cookies → claude.ai")
                        Text("3. Copy the sessionKey value (starts with sk-ant-sid01-)")
                        Text("4. For Org ID: Console tab → paste and run:")
                        Text("fetch('/api/organizations').then(r=>r.json()).then(d=>console.log(d[0].uuid))")
                            .textSelection(.enabled)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
            } label: {
                Text("Advanced")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            showAdvanced.toggle()
                        }
                    }
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
