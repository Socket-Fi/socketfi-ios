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
    @State private var showingCreateAccount = false
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

                    Text("A simpler way to manage your digital money. Secured with your passkey.")
                        .font(.body)
                        .foregroundStyle(AccessStyle.secondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)

                    Spacer(minLength: 56)

                    Button {
                        model.errorMessage = nil
                        showingCreateAccount = true
                    } label: {
                        Text("Create account")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .padding(.vertical, 17)
                            .padding(.horizontal, 16)
                            .foregroundStyle(.white)
                            .background(AccessStyle.primary, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(AccessButtonStyle())
                    .accessibilityHint("Choose your username and secure your account with a passkey")

                    Button {
                        model.errorMessage = nil
                        showingPasskey = true
                    } label: {
                        Text("Sign in")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(AccessStyle.brand)
                            .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AccessStyle.border))
                    }
                    .buttonStyle(AccessButtonStyle())
                    .padding(.top, 10)

                    Text("No password to remember.")
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
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showingCreateAccount) {
            SocketFiCreateAccountView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
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
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SocketFiBrandMark()
                        .fill(AccessStyle.brand, style: FillStyle(eoFill: true))
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(AccessStyle.secondary)
                    }
                    .accessibilityLabel("Close passkey sign-in")
                    .disabled(isWorking)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome back")
                        .font(.largeTitle.weight(.semibold))
                        .tracking(-0.5)
                    Text("Use your SocketFi passkey to sign in.")
                        .font(.subheadline)
                        .foregroundStyle(AccessStyle.secondary)
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

                VStack(spacing: 8) {
                    Button { authenticate(.signIn) } label: {
                        HStack(spacing: 10) {
                            if pendingMode == .signIn { ProgressView().tint(.white) }
                            else { Image(systemName: "person.badge.key") }
                            Text(pendingMode == .signIn ? "Signing in…" : "Sign in with passkey")
                                .fontWeight(.semibold)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(.white)
                        .background(AccessStyle.primary, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(AccessButtonStyle())
                    .disabled(isWorking)

                    Button { model.errorMessage = nil; showingCreateAccount = true } label: {
                        HStack(spacing: 8) {
                            if pendingMode == .signUp {
                                ProgressView().tint(AccessStyle.brand)
                            }
                            Text(pendingMode == .signUp ? "Creating account…" : "Create account instead")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
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
                .presentationDetents([.large])
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
