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
                VStack(spacing: 36) {
                    VStack(spacing: 16) {
                        Image(systemName: "wallet.bifold.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.socketFiInk, in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityHidden(true)
                        Text("Continue to SocketFi")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Your money. Your control.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        methodButton(.passkey) {
                            model.errorMessage = nil
                            showingPasskey = true
                        }
                        methodButton(.stellarWallet) { unavailableMethod = "Stellar wallet" }
                        methodButton(.evmWallet) { unavailableMethod = "EVM wallet" }
                    }

                    Label("Secured with your passkey or wallet.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 440)
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .background(Color(uiColor: .systemBackground))
        }
        .sheet(isPresented: $showingPasskey) {
            SocketFiPasskeySheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: method.icon)
                    .font(.title3)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text("Continue with \(method.displayName.lowercased())")
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(method == .passkey ? Color.white : Color.primary)
            .background(
                method == .passkey ? Color.socketFiInk : Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityHint(method == .passkey ? "Sign in or create an account using a passkey" : "View availability")
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
                        .foregroundStyle(Color.socketFiAccent)
                        .accessibilityHidden(true)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close passkey sign-in")
                    .disabled(isWorking)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(isCreating ? "Create your account" : "Welcome back")
                        .font(.title.bold())
                    Text(isCreating
                         ? "Create a passkey to secure your SocketFi account."
                         : "Use your SocketFi passkey to sign in.")
                        .foregroundStyle(.secondary)
                }

                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.red)
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
                        .background(Color.socketFiInk, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    Button(isCreating ? "Sign in instead" : "Create account instead") {
                        mode = isCreating ? .signIn : .signUp
                        model.errorMessage = nil
                    }
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
                    .disabled(isWorking)
                }
            }
            .padding(24)
        }
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
