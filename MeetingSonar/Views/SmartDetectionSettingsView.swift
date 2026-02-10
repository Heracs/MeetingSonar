import SwiftUI

@available(macOS 13.0, *)
struct SmartDetectionSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Smart Detection", isOn: $settings.smartDetectionEnabled)
                    .accessibilityIdentifier("Toggle_SmartDetection")

                if settings.smartDetectionEnabled {
                    Picker("Action Mode", selection: $settings.smartDetectionMode) {
                        ForEach(SettingsManager.SmartDetectionMode.allCases) { mode in
                            Text(mode.localizedDisplayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("Picker_SmartDetectionMode")

                    Text(modeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Meeting Awareness")
            }

            // MARK: - Per-App Detection Settings (Phase 1: Tencent Meeting)
            if settings.smartDetectionEnabled {
                Section {
                    Toggle("Tencent Meeting", isOn: $settings.detectTencentMeeting)
                        .accessibilityIdentifier("Toggle_TencentMeeting")

                    Toggle("Feishu/Lark", isOn: $settings.detectFeishu)
                        .accessibilityIdentifier("Toggle_Feishu")

                    Divider()

                    Toggle("WeChat Voice Call", isOn: $settings.detectWeChat)
                        .accessibilityIdentifier("Toggle_WeChat")
                        .help("WeChat voice calls may involve personal privacy. Disabled by default.")
                } header: {
                    Text("App Detection")
                } footer: {
                    Text("Enable or disable detection for specific meeting apps.")
                        .font(.caption)
                }
            }
        }
        .padding()
    }
    
    private var modeDescription: String {
        switch settings.smartDetectionMode {
        case .auto:
            return String(localized: "Automatically start recording when a meeting is detected. A notification will be shown silently.")
        case .remind:
            return String(localized: "Show a notification asking if you want to record when a meeting starts.")
        }
    }
}
