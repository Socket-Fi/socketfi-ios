import SwiftUI
import SocketFiNativeKit

@main
struct SocketFiApp: App {
    @StateObject private var model: SocketFiAppModel

    init() {
        let configuration = SocketFiConfiguration.fromInfoPlist()
        _model = StateObject(wrappedValue: SocketFiAppModel(
            client: SocketFiNativeAccountClient(configuration: configuration)
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
    private let client: SocketFiNativeAccountClient

    init(client: SocketFiNativeAccountClient) { self.client = client }

    func restore() async {
        do {
            if let session = try await client.restoreSession() { state = .signedIn(session) }
            else { state = .signedOut }
        } catch {
            state = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func authenticate(method: SocketFiSignInMethod, mode: SocketFiAuthMode) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        errorMessage = nil
        do {
            let session = try await client.authenticate(method: method, mode: mode)
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
            case let .signedIn(session): SocketFiHomeView(session: session) { Task { await model.signOut() } }
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
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.socketFiAccent)
                ProgressView()
                Text("Preparing your secure wallet…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SocketFiSignInView: View {
    @ObservedObject var model: SocketFiAppModel
    @State private var showingPasskey = false
    @State private var unavailableMethod: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    HStack(spacing: 9) {
                        SocketFiBrandMark().fill(AccessStyle.text, style: FillStyle(eoFill: true))
                            .frame(width: 26, height: 26)
                            .accessibilityHidden(true)
                        Text("socketfi").font(.title3.weight(.bold)).tracking(-0.6)
                        Spacer()
                    }

                    VStack(spacing: 0) {
                        VStack(spacing: 14) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(AccessStyle.ink, in: RoundedRectangle(cornerRadius: 20))
                                .accessibilityHidden(true)
                            Text("Continue to SocketFi")
                                .font(.title2.weight(.semibold))
                                .tracking(-0.6)
                                .multilineTextAlignment(.center)
                            Text("Create or access your smart account.")
                                .font(.subheadline)
                                .foregroundStyle(AccessStyle.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 32)
                        .background(AccessStyle.headerGradient)

                        Rectangle().fill(AccessStyle.border).frame(height: 1)

                        VStack(spacing: 12) {
                            methodButton(.passkey) {
                                model.errorMessage = nil
                                showingPasskey = true
                            }
                            methodButton(.stellarWallet) { unavailableMethod = "Stellar wallet" }
                            methodButton(.evmWallet) { unavailableMethod = "EVM wallet" }

                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lock.shield")
                                    .foregroundStyle(AccessStyle.security)
                                    .accessibilityHidden(true)
                                Text("Your private keys and recovery phrase stay yours.")
                                    .foregroundStyle(AccessStyle.secondary)
                            }
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(AccessStyle.background, in: RoundedRectangle(cornerRadius: 14))
                            .padding(.top, 8)
                        }
                        .padding(20)
                    }
                    .background(AccessStyle.surface, in: RoundedRectangle(cornerRadius: 30))
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30).stroke(AccessStyle.border, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.045), radius: 24, x: 0, y: 10)

                    Text("One account. More possibilities.")
                        .font(.footnote)
                        .foregroundStyle(AccessStyle.secondary)
                }
                .foregroundStyle(AccessStyle.text)
                .frame(maxWidth: 440)
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .background(AccessStyle.background.ignoresSafeArea())
        }
        .sheet(isPresented: $showingPasskey) {
            SocketFiPasskeySheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .alert("Coming soon", isPresented: Binding(
            get: { unavailableMethod != nil },
            set: { if !$0 { unavailableMethod = nil } }
        )) {
            Button("OK", role: .cancel) { unavailableMethod = nil }
        } message: {
            Text("\(unavailableMethod ?? "Wallet") sign-in isn't available yet. You can continue with a passkey.")
        }
    }

    private func methodButton(
        _ method: SocketFiSignInMethod,
        action: @escaping () -> Void
    ) -> some View {
        let primary = method == .passkey
        let tint = method == .stellarWallet ? AccessStyle.indigo : AccessStyle.violet
        return Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    switch method {
                    case .passkey: Image(systemName: "person.badge.key.fill")
                    case .stellarWallet: Image(systemName: "globe")
                    case .evmWallet: Image(systemName: "wallet.bifold")
                    }
                }
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(primary ? Color.white : tint)
                .frame(width: 44, height: 44)
                .background(primary ? Color.white.opacity(0.1) : tint.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(primary ? "Continue with passkey" : "\(method.displayName)")
                        .font(.subheadline.weight(.semibold))
                    Text(primary ? "Fast and passwordless" : "Coming soon")
                        .font(.caption)
                        .foregroundStyle(primary ? Color.white.opacity(0.7) : AccessStyle.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primary ? Color.white.opacity(0.6) : AccessStyle.secondary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(primary ? Color.white : AccessStyle.text)
            .background(primary ? AccessStyle.ink : AccessStyle.surface,
                        in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(primary ? Color.clear : AccessStyle.border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(AccessButtonStyle())
        .accessibilityHint(primary ? "Sign in or create an account using a passkey" : "View availability")
    }
}

struct SocketFiPasskeySheet: View {
    @ObservedObject var model: SocketFiAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: SocketFiAuthMode = .signIn
    @State private var isWorking = false
    @State private var authTask: Task<Void, Never>?

    private var isCreating: Bool { mode == .signUp }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Image(systemName: "person.badge.key.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(AccessStyle.ink, in: RoundedRectangle(cornerRadius: 18))
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
                    Text(isCreating ? "Create your account" : "Welcome back")
                        .font(.title2.weight(.semibold))
                        .tracking(-0.5)
                    Text(isCreating
                         ? "Create a passkey to secure your SocketFi account."
                         : "Use your SocketFi passkey to sign in.")
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
                    Button(action: authenticate) {
                        HStack(spacing: 10) {
                            if isWorking { ProgressView().tint(.white) }
                            else { Image(systemName: isCreating ? "plus.circle" : "person.badge.key") }
                            Text(isWorking ? "Waiting for approval…" :
                                 (isCreating ? "Create with passkey" : "Sign in with passkey"))
                                .fontWeight(.semibold)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(.white)
                        .background(AccessStyle.ink, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(AccessButtonStyle())
                    .disabled(isWorking)

                    Button(isCreating ? "Sign in instead" : "Create account instead") {
                        mode = isCreating ? .signIn : .signUp
                        model.errorMessage = nil
                    }
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
                    .font(.subheadline.weight(.medium))
                    .tint(AccessStyle.indigo)
                    .disabled(isWorking)
                }
            }
            .padding(24)
        }
        .background(AccessStyle.headerGradient.ignoresSafeArea())
        .interactiveDismissDisabled(isWorking)
        .onDisappear { authTask?.cancel() }
    }

    private func authenticate() {
        guard !isWorking else { return }
        isWorking = true
        let requestedMode = mode
        authTask = Task {
            defer { isWorking = false }
            await model.authenticate(method: .passkey, mode: requestedMode)
        }
    }
}

struct SocketFiHomeView: View {
    let session: SocketFiSession
    let signOut: () -> Void

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Good to see you").font(.largeTitle.bold())
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Smart account").font(.subheadline).foregroundStyle(.secondary)
                            Text(session.account.address)
                                .font(.headline.monospaced())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Label(session.account.network.rawValue, systemImage: "network")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.socketFiAccent)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
                    }
                    .padding(24)
                }
                .background(Color.socketFiBackground.ignoresSafeArea())
                .navigationTitle("Home")
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            Text("Explore").tabItem { Label("Explore", systemImage: "square.grid.2x2.fill") }
            Text("Activity").tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
            NavigationStack {
                List { Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: signOut) }
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Color.socketFiAccent)
    }
}

private extension SocketFiSignInMethod {
    var displayName: String {
        switch self {
        case .passkey: "Passkey"
        case .evmWallet: "EVM wallet"
        case .stellarWallet: "Stellar wallet"
        }
    }

    var icon: String {
        switch self {
        case .passkey: "person.badge.key"
        case .evmWallet: "link"
        case .stellarWallet: "star"
        }
    }

    var subtitle: String {
        switch self {
        case .passkey: "Fast, private, protected by Face ID or Touch ID"
        case .evmWallet: "Connect an external EVM wallet"
        case .stellarWallet: "Connect an external Stellar wallet"
        }
    }

}

private extension Color {
    static let socketFiAccent = Color(red: 0.16, green: 0.39, blue: 0.93)
    static let socketFiInk = Color(red: 0.05, green: 0.08, blue: 0.16)
    static let socketFiBackground = Color(red: 0.965, green: 0.97, blue: 0.985)
    static let socketFiSurface = Color(red: 0.93, green: 0.95, blue: 0.985)
}
