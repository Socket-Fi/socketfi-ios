import SwiftUI
import SocketFiNativeKit

@main
struct SocketFiApp: App {
    @StateObject private var model: SocketFiAppModel

    init() {
        let configuration = SocketFiConfiguration.fromInfoPlist()
        _model = StateObject(wrappedValue: SocketFiAppModel(
            client: SocketFiNativeAccountClient(configuration: configuration), configuration: configuration
        ))
    }

    var body: some Scene {
        WindowGroup { SocketFiRootView(model: model) }
    }
}

@MainActor
final class SocketFiAppModel: ObservableObject {
    enum State { case loading, signedOut, signedIn(SocketFiSession) }

    @Published var state: State = .loading
    @Published var errorMessage: String?
    private var isAuthenticating = false
    let client: SocketFiNativeAccountClient
    let configuration: SocketFiConfiguration

    init(client: SocketFiNativeAccountClient, configuration: SocketFiConfiguration) {
        self.client = client
        self.configuration = configuration
    }

    func restore() async {
        do {
            if let session = try await client.restoreSession() { state = .signedIn(session) }
            else { state = .signedOut }
        } catch {
            state = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func authenticate(method: SocketFiSignInMethod, mode: SocketFiAuthMode, username: String? = nil) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        errorMessage = nil
        do {
            let session = try await client.authenticate(method: method, mode: mode, username: username)
            state = .signedIn(session)
        } catch SocketFiNativeError.authenticationCancelled {
            errorMessage = nil
        } catch is CancellationError {
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func signOut() async {
        await client.signOut()
        state = .signedOut
    }
}

struct SocketFiRootView: View {
    @ObservedObject var model: SocketFiAppModel

    var body: some View {
        Group {
            switch model.state {
            case .loading: SocketFiLoadingView()
            case .signedOut: SocketFiSignInView(model: model)
            case let .signedIn(session):
                SocketFiWalletShell(session: session, configuration: model.configuration, signer: model.client) {
                    Task { await model.signOut() }
                }.id(session.account.address + session.account.network.rawValue)
            }
        }
        .task { await model.restore() }
    }
}

struct SocketFiLoadingView: View {
    var body: some View {
        ZStack {
            Color.socketFiBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                SocketFiBrandMark()
                    .fill(AccessStyle.brand, style: FillStyle(eoFill: true))
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                ProgressView()
                Text("Opening SocketFi…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Native onboarding using the SocketFi web application's visual language.
struct SocketFiSignInView: View {
    @ObservedObject var model: SocketFiAppModel
    @State private var showingPasskey = false
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 42

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        SocketFiBrandMark()
                            .fill(AccessStyle.brand, style: FillStyle(eoFill: true))
                            .frame(width: 30, height: 30)
                            .accessibilityHidden(true)
                        Text("socketfi")
                            .font(.title3.weight(.semibold))
                            .tracking(-0.5)
                    }

                    Spacer(minLength: 48)

                    Text("Your account.\nYour control.")
                        .font(.system(size: headlineSize, weight: .semibold))
                        .tracking(-1.2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text("A simpler way to manage your digital money. Choose how you want to continue.")
                        .font(.body)
                        .foregroundStyle(AccessStyle.secondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)

                    Spacer(minLength: 56)

                    VStack(spacing: 10) {
                        Button {
                            model.errorMessage = nil
                            showingPasskey = true
                        } label: {
                            onboardingMethodLabel(
                                title: "Continue with passkey",
                                subtitle: "Recommended · Fast and passwordless",
                                systemImage: "touchid",
                                prominent: true
                            )
                        }
                        .buttonStyle(AccessButtonStyle())
                        .accessibilityHint("Open passkey sign-in and account creation options")

                        onboardingMethodButton(
                            title: "Continue with Stellar wallet",
                            subtitle: "Freighter, xBull, LOBSTR, and more",
                            assetName: "SocketFiStellar"
                        )

                        onboardingMethodButton(
                            title: "Continue with EVM wallet",
                            subtitle: "MetaMask, Coinbase Wallet, and more",
                            assetName: "SocketFiEthereum"
                        )
                    }

                    Text("Passkey access is available now. Stellar and EVM wallet sign-in are coming soon.")
                        .font(.footnote)
                        .foregroundStyle(AccessStyle.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                }
                .foregroundStyle(AccessStyle.text)
                .frame(maxWidth: 480)
                .padding(.horizontal, 28)
                .padding(.vertical, 28)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .background {
                ZStack(alignment: .topTrailing) {
                    AccessStyle.background
                    AccessStyle.headerGradient
                        .frame(height: 280)
                        .accessibilityHidden(true)
                }
                .clipped()
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingPasskey) {
            SocketFiPasskeySheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }

    private func onboardingMethodButton(title: String, subtitle: String, systemImage: String? = nil, assetName: String? = nil) -> some View {
        Button {} label: {
            onboardingMethodLabel(title: title, subtitle: subtitle, systemImage: systemImage, assetName: assetName, prominent: false)
        }
        .buttonStyle(AccessButtonStyle())
        .disabled(true)
        .opacity(0.55)
        .accessibilityHint("This sign-in method is coming soon")
    }

    private func onboardingMethodLabel(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        assetName: String? = nil,
        prominent: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Group {
                if let assetName {
                    Image(assetName)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .padding(1)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(prominent ? Color.white : AccessStyle.brand)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(prominent ? Color.white.opacity(0.8) : AccessStyle.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: prominent ? 72 : 60, alignment: .leading)
        .padding(.horizontal, 18)
        .foregroundStyle(prominent ? Color.white : AccessStyle.text)
        .background(
            prominent ? AnyShapeStyle(AccessStyle.primary) : AnyShapeStyle(AccessStyle.surface),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            if !prominent {
                RoundedRectangle(cornerRadius: 16).stroke(AccessStyle.border)
            }
        }
    }
}

struct SocketFiPasskeySheet: View {
    @ObservedObject var model: SocketFiAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingMode: SocketFiAuthMode?
    @State private var authTask: Task<Void, Never>?
    @State private var showingCreateAccount = false

    private var isWorking: Bool { pendingMode != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle().fill(AccessStyle.primary.opacity(0.1))
                        Image(systemName: "touchid")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(AccessStyle.brand)
                    }
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Passkey access")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AccessStyle.brand)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text("Continue with passkey")
                            .font(.title2.weight(.semibold))
                            .tracking(-0.3)
                        Text("Use Face ID, Touch ID, or your device passcode.")
                            .font(.subheadline)
                            .foregroundStyle(AccessStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(AccessStyle.secondary)
                            .background(AccessStyle.background, in: Circle())
                    }
                    .accessibilityLabel("Close passkey sign-in")
                    .disabled(isWorking)
                }

                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Authentication error: \(message)")
                }

                VStack(spacing: 12) {
                    Button { authenticate(.signIn) } label: {
                        HStack(spacing: 10) {
                            if pendingMode == .signIn { ProgressView().tint(.white) }
                            else { Image(systemName: "touchid") }
                            Text(pendingMode == .signIn ? "Signing in…" : "Sign in with passkey")
                                .fontWeight(.semibold)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(.white)
                        .background(AccessStyle.primary, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(AccessButtonStyle())
                    .disabled(isWorking)

                    Button { model.errorMessage = nil; showingCreateAccount = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AccessStyle.brand)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Sign up with passkey")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AccessStyle.text)
                                Text("Create a new smart account")
                                    .font(.caption)
                                    .foregroundStyle(AccessStyle.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AccessStyle.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .padding(.horizontal, 16)
                    }
                    .background(AccessStyle.background, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AccessStyle.border))
                    .font(.subheadline.weight(.medium))
                    .tint(AccessStyle.brand)
                    .disabled(isWorking)
                    .accessibilityHint("Choose a username and create your account")
                }
            }
            .padding(24)
        }
        .background(AccessStyle.surface.ignoresSafeArea())
        .interactiveDismissDisabled(isWorking)
        .onDisappear { authTask?.cancel() }
        .sheet(isPresented: $showingCreateAccount) {
            SocketFiCreateAccountView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
    }

    private func authenticate(_ mode: SocketFiAuthMode) {
        guard !isWorking else { return }
        pendingMode = mode
        model.errorMessage = nil
        authTask = Task {
            defer { pendingMode = nil }
            await model.authenticate(method: .passkey, mode: mode)
        }
    }
}

private extension Color {
    static let socketFiAccent = Color(red: 0.16, green: 0.39, blue: 0.93)
    static let socketFiInk = Color(red: 0.05, green: 0.08, blue: 0.16)
    static let socketFiBackground = Color(red: 0.965, green: 0.97, blue: 0.985)
    static let socketFiSurface = Color(red: 0.93, green: 0.95, blue: 0.985)
}
