import SwiftUI
import OSLog
import SocketFiNativeKit

@main
struct SocketFiApp: App {
    @StateObject private var model: SocketFiAppModel

    init() {
        let configuration = SocketFiConfiguration.fromInfoPlist()
        if let projectID = Bundle.main.object(forInfoDictionaryKey: "SocketFiWalletConnectProjectID") as? String {
            SocketFiWalletConnect.shared.configure(projectID: projectID)
        }
        _model = StateObject(wrappedValue: SocketFiAppModel(
            client: SocketFiNativeAccountClient(configuration: configuration), configuration: configuration
        ))
    }

    var body: some Scene {
        WindowGroup {
            SocketFiRootView(model: model)
                .onOpenURL { url in
                    _ = SocketFiWalletConnect.shared.handle(url)
                }
        }
    }
}

@MainActor
final class SocketFiAppModel: ObservableObject {
    enum State { case loading, signedOut, signedIn(SocketFiSession) }

    @Published var state: State = .loading
    @Published var errorMessage: String?
    @Published private(set) var isAuthenticating = false
    @Published private(set) var evmStage: SocketFiEvmAuthStage?
    @Published private(set) var isDisconnectingEvm = false
    @Published var evmError: String?
    @Published var evmNotice: String?
    @Published private(set) var connectedWalletName: String?
    private var evmTask: Task<Void, Never>?

    func startEvm() {
        guard !isAuthenticating, !isDisconnectingEvm, evmTask == nil else { return }
        errorMessage = nil
        evmError = nil
        evmNotice = nil
        evmStage = .connecting
        SocketFiWalletConnect.shared.presentWalletPicker()
        evmTask = Task {
            await authenticateEvm()
            evmTask = nil
        }
    }

    func cancelEvm() {
        guard evmStage != .submitting else { return }
        evmTask?.cancel()
    }

    func refreshEvmConnection() {
        connectedWalletName = SocketFiWalletConnect.shared.connectedWalletName
    }

    func reopenEvmWallet() {
        Task {
            do { try await SocketFiWalletConnect.shared.reopenWallet() }
            catch { evmError = error.localizedDescription }
        }
    }

    func disconnectEvm() {
        guard !isAuthenticating, evmTask == nil, !isDisconnectingEvm else { return }
        isDisconnectingEvm = true
        Task {
            defer { isDisconnectingEvm = false; refreshEvmConnection() }
            do {
                try await SocketFiWalletConnect.shared.disconnect()
                evmError = nil
                evmNotice = "Wallet disconnected. Choose another wallet to continue."
            } catch { evmError = "Could not disconnect. Check your connection and try again." }
        }
    }
    let client: SocketFiNativeAccountClient
    let configuration: SocketFiConfiguration

    init(client: SocketFiNativeAccountClient, configuration: SocketFiConfiguration) {
        self.client = client
        self.configuration = configuration
    }

    func restore() async {
        #if DEBUG
        // Visual UI checks can inspect onboarding without deleting a real session.
        if ProcessInfo.processInfo.arguments.contains("-preview-onboarding") {
            state = .signedOut
            return
        }
        #endif
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

    func authenticateEvm() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        errorMessage = nil
        defer { SocketFiWalletConnect.shared.finishAttempt(); evmStage = nil; refreshEvmConnection() }
        do {
            let session = try await client.authenticateEvm(onStage: { stage in
                self.evmStage = stage
                self.refreshEvmConnection()
            }) { message in
                try await SocketFiWalletConnect.shared.sign(message: message)
            }
            state = .signedIn(session)
        } catch SocketFiNativeError.authenticationCancelled {
            evmNotice = "Request declined. You can try again when you’re ready."
        }
        catch is CancellationError {
            evmNotice = "Sign-in cancelled. You can start again whenever you’re ready."
        }
        catch let error as URLError where error.code == .cancelled {
            evmNotice = "Sign-in cancelled. You can start again whenever you’re ready."
        }
        catch {
            NSLog("[SocketFiEVM] stage=authentication_failed")
            if let networkError = error as? URLError {
                NSLog("[SocketFiEVM] network_error_code=%ld", networkError.code.rawValue)
                evmError = networkError.code == .timedOut
                    ? "SocketFi timed out. Check your connection and start EVM sign-in again."
                    : "Could not reach SocketFi. Check your internet connection, then try EVM sign-in again."
            } else { evmError = error.localizedDescription }
        }
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
                        Text("Use a passkey")
                            .font(.title2.weight(.semibold))
                            .tracking(-0.3)
                        Text("Secure access, made simple.")
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
                                Text("Create account")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AccessStyle.text)
                                Text("Set up your personal smart account")
                                    .font(.caption)
                                    .foregroundStyle(AccessStyle.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .multilineTextAlignment(.leading)
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
