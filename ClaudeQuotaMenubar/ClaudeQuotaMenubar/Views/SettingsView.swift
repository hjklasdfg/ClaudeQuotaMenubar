import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let keychain: KeychainService
    let onSave: () -> Void

    @State private var sessionKey: String = ""
    @State private var organizationId: String = ""
    @State private var showingSessionKey = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude Quota Settings")
                .font(.headline)

            GroupBox("Credentials") {
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
                }
                .padding(8)
            }

            GroupBox("How to find these values") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open browser → claude.ai → log in")
                    Text("2. Open DevTools (F12) → Application → Cookies → claude.ai")
                    Text("3. Copy the sessionKey value (starts with sk-ant-sid01-)")
                    Text("4. For Org ID: Network tab → filter 'organizations' → copy UUID from URL")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
            }

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
                            launchAtLogin = !newValue // revert on failure
                        }
                    }
                    .padding(8)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    keychain.save(account: "sessionKey", value: sessionKey)
                    keychain.save(account: "organizationId", value: organizationId)
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sessionKey.isEmpty || organizationId.isEmpty)
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
