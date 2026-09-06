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
        WindowGroup {
            SocketFiRootView(model: model)
        }
    }
}

@MainActor
final class SocketFiAppModel: ObservableObject {
    enum State {
        case loading
        case signedOut
        case signedIn(SocketFiSession)
    }

    @Published var state: State = .loading
    @Published var selectedMethod: SocketFiSignInMethod = .passkey
    @Published var errorMessage: String?

    private let client: SocketFiNativeAccountClient

    init(client: SocketFiNativeAccountClient) {
        self.client = client
    }

    func restore() async {
        do {
            if let session = try await client.restoreSession() {
                state = .signedIn(session)
            } else {
                state = .signedOut
            }
        } catch {
            state = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func authenticate(mode: SocketFiAuthMode) async {
        errorMessage = nil
        do {
            let session = try await client.authenticate(method: selectedMethod, mode: mode)
            state = .signedIn(session)
        } catch {
            errorMessage = error.localizedDescription
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
            case .loading:
                ProgressView("Loading SocketFi…")
            case .signedOut:
                SocketFiSignInView(model: model)
            case let .signedIn(session):
                SocketFiHomeView(session: session, signOut: { Task { await model.signOut() } })
            }
        }
        .task { await model.restore() }
    }
}

struct SocketFiSignInView: View {
    @ObservedObject var model: SocketFiAppModel
    @State private var isSigningIn = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Text("Your wallet, secured by SocketFi")
                    .font(.largeTitle.bold())
                Text("Choose one owner method for this smart account. You can rotate the signer later from Security.")
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    ForEach(SocketFiSignInMethod.allCases, id: \.self) { method in
                        Button {
                            model.selectedMethod = method
                        } label: {
                            HStack {
                                Image(systemName: method.icon)
                                Text(method.displayName)
                                Spacer()
                                if method != .passkey {
                                    Text("Coming next")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: model.selectedMethod == method ? "checkmark.circle.fill" : "circle")
                            }
                            .padding()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }

                Button {
                    isSigningIn = true
                    Task {
                        await model.authenticate(mode: .signIn)
                        isSigningIn = false
                    }
                } label: {
                    Text(isSigningIn ? "Waiting for approval…" : "Sign in")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSigningIn)

                Button("Create a new smart account") {
                    Task { await model.authenticate(mode: .signUp) }
                }
                .frame(maxWidth: .infinity)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("SocketFi")
        }
    }
}

struct SocketFiHomeView: View {
    let session: SocketFiSession
    let signOut: () -> Void

    var body: some View {
        TabView {
            NavigationStack {
                List {
                    Section("Smart account") {
                        LabeledContent("Address", value: session.account.address)
                        LabeledContent("Network", value: session.account.network.rawValue)
                        LabeledContent("Owner", value: session.account.signer.displayName)
                    }
                }
                .navigationTitle("Home")
            }
            .tabItem { Label("Home", systemImage: "house") }

            Text("Explore")
                .tabItem { Label("Explore", systemImage: "square.grid.2x2") }
            Text("Activity")
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
            NavigationStack {
                List {
                    Button("Sign out", role: .destructive, action: signOut)
                }
                .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
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
}
