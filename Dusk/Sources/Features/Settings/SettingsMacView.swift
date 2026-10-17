import SwiftUI

struct SettingsMacView: View {
    @Environment(PlexService.self) private var plex
    @Environment(UserPreferences.self) private var preferences
    @Environment(DownloadManager.self) private var downloads
    @State private var confirmsSignOut = false
    let viewModel: SettingsViewModel

    var body: some View {
        @Bindable var preferences = preferences
        SettingsContainer(viewModel: viewModel) {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $preferences.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Playback") {
                Toggle("Continue to the next episode", isOn: $preferences.continuousPlayEnabled)
                Picker("Skip intros", selection: $preferences.autoSkipIntroMode) {
                    ForEach(AutoSkipIntroMode.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Skip credits", isOn: $preferences.autoSkipCredits)
                Picker("Subtitle size", selection: $preferences.subtitleFontSize) {
                    ForEach(SubtitleFontSize.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Audio language", selection: $preferences.defaultAudioLanguage) {
                    ForEach(SettingsSupport.audioLanguageOptions, id: \.self) { code in
                        Text(SettingsSupport.languageDisplayName(for: code)).tag(code)
                    }
                }
                Picker("Subtitle language", selection: SettingsSupport.subtitleLanguageBinding(preferences)) {
                    ForEach(SettingsSupport.subtitleLanguageOptions, id: \.self) { code in
                        Text(SettingsSupport.subtitleDisplayName(for: code)).tag(code)
                    }
                }
                Toggle("Forced subtitles only", isOn: $preferences.subtitleForcedOnly)
                Toggle("Dolby Atmos remux", isOn: $preferences.spatialAudioRemuxEnabled)
                Toggle("HDR & Dolby Vision remux", isOn: $preferences.hdrVideoRemuxEnabled)
                Toggle("Dolby Vision 7 → 8.1", isOn: $preferences.dolbyVision7ConversionEnabled)
            }
            Section("Library") {
                Toggle("Personalized shelves", isOn: $preferences.personalizedShelvesEnabled)
                Toggle("Live TV on Home", isOn: $preferences.showsLiveTVOnHome)
                NavigationLink("Server priority") { ServerPrioritySettingsView() }
                NavigationLink("Library order") { LibraryOrderSettingsView() }
            }
            Section("Downloads") {
                Picker("Maximum resolution", selection: $preferences.downloadMaxResolution) {
                    ForEach(MaxResolution.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Wi-Fi only", isOn: $preferences.downloadsWifiOnly)
            }
            Section("Privacy") {
                Toggle("Share anonymous usage statistics", isOn: $preferences.analyticsEnabled)
                Text("No Plex data is shared. You can turn off reporting at any time.")
                    .foregroundStyle(.secondary)
            }
            Section("Account") {
                if plex.homeUsers.count > 1 {
                    Button("Switch User") { viewModel.showHomeUserPicker = true }
                }
                NavigationLink("Seerr") { SeerrSettingsView() }
                Button("Sign Out", role: .destructive) { confirmsSignOut = true }
            }
        }
        .formStyle(.grouped)
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of Plex?", isPresented: $confirmsSignOut) {
            Button("Sign Out", role: .destructive) { plex.signOut() }
        }
    }
}
