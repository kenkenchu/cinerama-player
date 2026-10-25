import SwiftUI

struct SignInView: View {
    @Environment(PlexService.self) private var plexService
    @Environment(\.openURL) private var openURL
    @State private var linkPinCode: String?
    @State private var isSigningIn = false
    @State private var error: String?
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.cineramaBackground.ignoresSafeArea()

            signInContent
        }
        .onDisappear {
            pollingTask?.cancel()
        }
    }

    @ViewBuilder
    private var signInContent: some View {
        desktopSignInContent
    }

    private var desktopSignInContent: some View {
        VStack(spacing: 0) {
            Spacer()

            branding(iconSize: 80, titleFont: .largeTitle)

            Spacer()

            VStack(spacing: 24) {
                signInError

                if isSigningIn {
                    VStack(spacing: 12) {
                        Text("Complete sign-in in the Plex page that opened, or go to")
                            .foregroundStyle(Color.cineramaTextSecondary)
                            .font(.callout)

                        if let linkPinCode {
                            linkCodeContent(
                                code: linkPinCode,
                                titleFont: .headline,
                                codeFont: .system(.title, design: .monospaced, weight: .bold)
                            )
                        }
                    }
                }

                signInButton
                    .padding(.horizontal, 40)

                if isSigningIn {
                    cancelButton
                }
            }

            Spacer()
                .frame(height: 60)
        }
    }


    private func branding(iconSize: CGFloat, titleFont: Font) -> some View {
        VStack(spacing: 16) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)

            VStack(spacing: 6) {
                Text("Cinerama")
                    .font(titleFont)
                    .foregroundStyle(Color.cineramaTextPrimary)
                Text("The Plex App we Deserve.")
                    .font(CineramaFont.caption(style: .subheadline))
                    .foregroundStyle(Color.cineramaTextSecondary)
            }
        }
    }

    @ViewBuilder
    private var signInError: some View {
        if let error {
            Text(error)
                .foregroundStyle(.red)
                .font(CineramaFont.body(style: .callout))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var signInButton: some View {
        Button {
            Task { await signIn() }
        } label: {
            HStack(spacing: 8) {
                if isSigningIn {
                    ProgressView()
                        .tint(Color.cineramaPrimaryActionLabel)
                }
                Text(isSigningIn ? "Waiting for approval…" : "Sign in with Plex")
            }
            .font(CineramaFont.buttonLabel(style: .headline))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(Color.cineramaPrimaryActionLabel)
        }
        .disabled(isSigningIn)
        .detailHeroNativePrimaryButtonStyle()
    }

    private var cancelButton: some View {
        Button("Cancel") {
            cancelSignIn()
        }

        .foregroundStyle(Color.cineramaTextSecondary)


    }

    private func linkCodeContent(code: String, titleFont: Font, codeFont: Font) -> some View {
        VStack(spacing: 12) {
            Text("plex.tv/link")
                .font(titleFont)
                .foregroundStyle(Color.cineramaTextPrimary)
            Text("and enter this code:")
                .foregroundStyle(Color.cineramaTextSecondary)
                .font(.callout)
            Text(code)
                .font(codeFont)
                .tracking(4)
                .foregroundStyle(Color.cineramaTextPrimary)
        }
    }

    private func signIn() async {
        isSigningIn = true
        error = nil
        linkPinCode = nil

        do {
            // Plex uses a longer-lived "strong" PIN for browser approval, but
            // plex.tv/link expects the short code flow, so we keep both active.
            let browserPin = try await plexService.generatePin(strong: true)
            let linkPin = try? await plexService.generatePin()
            linkPinCode = linkPin?.code

            guard let url = plexService.authURL(for: browserPin) else {
                throw PlexServiceError.invalidURL
            }

            startPolling(primaryPinID: browserPin.id, fallbackPinID: linkPin?.id)
            openAuthURL(url)
        } catch {
            self.error = error.localizedDescription
            isSigningIn = false
        }
    }

    private func startPolling(primaryPinID: Int, fallbackPinID: Int? = nil) {
        pollingTask?.cancel()
        pollingTask = Task {
            let fallbackActivationAttempt = 15

            for attempt in 0..<120 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }

                if let token = try? await plexService.checkPin(primaryPinID) {
                    plexService.setAuthToken(token)
                    isSigningIn = false
                    linkPinCode = nil
                    return
                }

                if attempt >= fallbackActivationAttempt,
                   let fallbackPinID,
                   let token = try? await plexService.checkPin(fallbackPinID) {
                        plexService.setAuthToken(token)
                        isSigningIn = false
                        linkPinCode = nil
                        return
                }
            }

            // Ran the full window without approval — a genuine timeout.
            // Cancellation (Cancel button, closing the view, restarting sign-in)
            // returns early above, so aborting never surfaces this message.
            isSigningIn = false
            linkPinCode = nil
            error = "Sign-in timed out. Please try again."
        }
    }

    private func cancelSignIn() {
        pollingTask?.cancel()
        isSigningIn = false
        linkPinCode = nil
    }


    /// Opens Plex approval in the default Mac browser while PIN polling continues.
    private func openAuthURL(_ url: URL) {
        openURL(url)
    }
}
