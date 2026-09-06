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
        errorMessage = nil
        do {
            let session = try await client.authenticate(method: method, mode: mode)
            state = .signedIn(session)
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
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.socketFiAccent, in: RoundedRectangle(cornerRadius: 20))
                        Text("Welcome to SocketFi")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.socketFiInk)
                        Text("A smarter way to hold, move and use your digital assets.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose how you want to continue").font(.headline)
                        Text("Each account uses one owner method. You can change it later from Security.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(SocketFiSignInMethod.allCases, id: \.self) { method in
                            if method == .passkey {
                                VStack(spacing: 8) {
                                    Button { authenticate(.passkey, .signIn) } label: {
                                        SocketFiMethodCard(method: method)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        authenticate(.passkey, .signUp)
                                    } label: {
                                        Label("Create account with passkey", systemImage: "plus.circle.fill")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(Color.socketFiAccent)
                                }
                            } else {
                                Button { authenticate(method, .signIn) } label: {
                                    SocketFiMethodCard(method: method)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if isWorking {
                        Label("Waiting for passkey approval…", systemImage: "faceid")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.socketFiAccent)
                    }

                    Label("Your keys stay with you. SocketFi never receives a private wallet key.", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.socketFiSurface, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .background(Color.socketFiBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func authenticate(_ method: SocketFiSignInMethod, _ mode: SocketFiAuthMode) {
        isWorking = true
        Task {
            await model.authenticate(method: method, mode: mode)
            isWorking = false
        }
    }
}

struct SocketFiMethodCard: View {
    let method: SocketFiSignInMethod

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: method.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(method == .passkey ? .white : Color.socketFiInk)
                .frame(width: 48, height: 48)
                .background(method == .passkey ? Color.socketFiAccent : Color.white, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(method.displayName).font(.headline)
                    if method == .passkey {
                        Text("RECOMMENDED")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Color.socketFiAccent)
                    }
                }
                Text(method.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(method == .passkey ? Color.socketFiAccent.opacity(0.35) : Color.black.opacity(0.06), lineWidth: 1)
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
