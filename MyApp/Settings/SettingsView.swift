import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.Key.handwritingRetention)
    private var handwritingRetention = AppSettings.Default.handwritingRetention

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Keep Handwriting", selection: $handwritingRetention) {
                        ForEach(HandwritingRetention.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } header: {
                    Text("Handwriting")
                } footer: {
                    Text("Your handwriting never leaves this device. Time, grade, and the recognized answer are always kept.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.appVersion)
                    NavigationLink("Acknowledgements") {
                        AcknowledgementsView()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
}
