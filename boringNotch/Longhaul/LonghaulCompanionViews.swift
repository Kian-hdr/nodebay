import SwiftUI

struct LonghaulCompanionSettingsSection: View {
    @ObservedObject private var companion = LonghaulCompanionClient.shared
    var body: some View {
        Section("Longhaul") {
            LabeledContent("Connection", value: companion.state.rawValue)
            Text(companion.showsNotchControl
                 ? "Use the notch icon to turn automatic protection on or off. Manage jobs, battery protection and recovery in Longhaul."
                 : "Use Longhaul’s menu bar icon to turn automatic protection on or off. Manage jobs, battery protection and recovery in Longhaul.")
                .foregroundStyle(.secondary)
            Text(companion.message).font(.caption).foregroundStyle(.secondary)
            if companion.appURL != nil {
                HStack {
                    Button("Open Longhaul") { companion.openLonghaul() }
                    if companion.state == .connected {
                        Button("Disconnect Nodebay") { companion.control("disconnect") }
                            .disabled(companion.controlsBusy)
                    } else {
                        Button("Connect to Longhaul") { companion.control("connect") }
                            .disabled(companion.controlsBusy)
                    }
                }
            }
            Toggle("Show important Longhaul notices in the notch", isOn: $companion.notificationsEnabled)
            Text("This preference is independent of volume and brightness displays. Longhaul handles fallback notifications.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Check Connection") { Task { await companion.refresh() } }.disabled(companion.busy)
        }
        .task { companion.start(); await companion.refresh() }
    }
}

struct LonghaulNotchButton: View {
    @ObservedObject private var companion = LonghaulCompanionClient.shared
    private var symbol: String {
        switch companion.state {
        case .connected: companion.snapshot?.enabled == true ? "sun.max.fill" : "moon.zzz"
        case .available: "link"
        case .notInstalled, .needsAttention: "questionmark.circle"
        }
    }
    var body: some View {
        // Keep the target stable across job counts, pending work and connection changes.
        ZStack {
            Button { companion.toggleAutomaticProtection() } label: {
                ZStack {
                    if companion.automaticChange != nil || companion.busy {
                        ProgressView().controlSize(.mini).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!companion.canToggleAutomaticProtection)
            .accessibilityLabel("Longhaul automatic protection")
            .accessibilityValue(companion.automaticProtectionStatus)
            .accessibilityHint(companion.canToggleAutomaticProtection ? companion.automaticActionTitle : "Open Longhaul to manage this connection")
        }
        .frame(width: 28, height: 28)
        .help(companion.automaticProtectionStatus + ". " + (companion.automaticControlIssue ?? (companion.canToggleAutomaticProtection ? companion.automaticActionTitle : companion.message)))
        .contextMenu {
            Button(companion.automaticActionTitle) { companion.toggleAutomaticProtection() }
                .disabled(!companion.canToggleAutomaticProtection)
            Divider()
            Button("Open Longhaul") { companion.openLonghaul() }
                .disabled(companion.appURL == nil)
        }
    }
}

/// A short horizontal notice in the existing notch surface. It never activates
/// another app, changes Spaces, selects a tab, or opens the large notch drawer.
struct LonghaulNotchNotice: View {
    let alert: LonghaulCompanionAlert
    let cameraWidth: CGFloat
    let height: CGFloat
    var body: some View {
        Button { LonghaulCompanionClient.shared.openLonghaul() } label: {
            HStack(spacing: 8) {
                Label("Longhaul", systemImage: "moon.zzz").font(.caption).frame(width: 90)
                Color.clear.frame(width: cameraWidth)
                Text(alert.title).font(.caption.weight(.medium)).lineLimit(1).frame(width: 150, alignment: .leading)
            }
            .foregroundStyle(.white)
            .frame(height: height)
        }
        .buttonStyle(.plain)
        .help(alert.body)
        .accessibilityLabel("Longhaul: \(alert.title). \(alert.body)")
        .task(id: alert.id) { await LonghaulCompanionClient.shared.noticeWasPresented(alert.id) }
    }
}
