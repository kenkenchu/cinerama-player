import SwiftUI

struct SettingsMacView: View {
    @Environment(PlexService.self) private var plex
    @Environment(UserPreferences.self) private var preferences
    @Environment(DownloadManager.self) private var downloads
    @AppStorage(ExperimentalMPEG2Mode.defaultsKey) private var mpeg2Mode = ExperimentalMPEG2Mode.standard.rawValue
    @State private var confirmsSignOut = false
    let viewModel: SettingsViewModel

    var body: some View {
        @Bindable var preferences = preferences
        SettingsContainer(viewModel: viewModel) {
        Form {
            Section("Appearance") {
                LabeledContent("Theme", value: "Cinematic Metal Blue")
                Text("A consistent metallic-blue appearance with Liquid Glass, independent of macOS light and dark mode.")
                    .foregroundStyle(.secondary)
            }
            Section("Playback") {
                Toggle("Continue to the next episode", isOn: $preferences.continuousPlayEnabled)
                Picker("Skip intros", selection: $preferences.autoSkipIntroMode) {
                    ForEach(AutoSkipIntroMode.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Skip credits", isOn: $preferences.autoSkipCredits)
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
            Section("Live TV decoding experiment") {
                Picker("MPEG-2 decoder", selection: $mpeg2Mode) {
                    ForEach(ExperimentalMPEG2Mode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                Text("Applies when you retune an MPEG-2 channel. Compare Experimental CPU and Experimental Metal using the same channel. Metal performs inverse DCT; parsing and motion prediction use the CPU.")
                    .foregroundStyle(.secondary)
                Text("Experimental modes use the default audio track in stereo, with no captions or track switching. Live playback only; DVR is not supported. Select Standard playback to restore the normal player. Forced player overrides and AirPlay take priority.")
                    .foregroundStyle(.secondary)
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
                Text("Cinerama does not send usage statistics.")
                Text("No analytics endpoint is configured.")
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
        .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of Plex?", isPresented: $confirmsSignOut) {
            Button("Sign Out", role: .destructive) { plex.signOut() }
        }
    }
}
