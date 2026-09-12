import Foundation
import Combine
import SocketFiNativeKit
@preconcurrency import ReownAppKit
import WalletConnectNetworking
import WalletConnectRelay
import Starscream
import OSLog

#if canImport(UIKit)
import UIKit
#endif

/// Owns the one-time Reown/AppKit setup used by the native EVM sign-in flow.
@MainActor
final class SocketFiWalletConnect: ObservableObject {
    static let shared = SocketFiWalletConnect()
    private var configured = false
    private var subscriptions = Set<AnyCancellable>()
    private var boundAddress: String?
    private var boundTopic: String?
    private var rejected = false
    private var projectID = ""
    private var attempt = UUID()
    private var pairingTopic: String?
    private var connectionError: Error?
    private var connectionTask: Task<Void, Never>?
    private var selectedWallet: SocketFiWalletChoice?
    private var pendingPairingURL: URL?
    private var accountChanged = false
    private var invalidatedTopics = Set<String>()
    private var fundingChain: Int?
    var isFunding: Bool { fundingChain != nil }
    @Published var showingPicker = false
    @Published private(set) var choosing = false
    @Published private(set) var pairingReady = false
    @Published private(set) var wallets: [SocketFiWalletChoice] = []
    @Published private(set) var catalogueError: String?
    @Published private(set) var loadingWallets = false
    private var cataloguePage = 0
    private var catalogueCount = 0
    var hasMoreWallets: Bool { wallets.count < catalogueCount }


    private init() {}

    func configure(projectID: String) {
        guard !configured else { return }
        guard !projectID.isEmpty else { return }

        self.projectID = projectID
        Networking.configure(
            groupIdentifier: "group.fi.socket.socketfi",
            projectId: projectID,
            socketFactory: SocketFiWebSocketFactory()
        )

        let metadata = AppMetadata(
            name: "SocketFi",
            description: "Smart accounts for your digital money.",
            url: "https://socket.fi",
            icons: ["https://socket.fi/icon.png"],
            redirect: try! AppMetadata.Redirect(native: "socketfi://walletconnect", universal: nil)
        )

        AppKit.configure(
            projectId: projectID,
            metadata: metadata,
            crypto: SocketFiReownCryptoProvider(),
            sessionParams: SessionParams(namespaces: [
                "eip155": ProposalNamespace(
                    chains: [Blockchain("eip155:1")!],
                    methods: ["personal_sign"],
                    events: ["accountsChanged", "chainChanged"]
                )
            ]),
            authRequestParams: nil,
            includeWebWallets: true,
            coinbaseEnabled: false
        )
        AppKit.instance.sessionRejectionPublisher.receive(on: DispatchQueue.main).sink { [weak self] proposal, _ in
            guard let self, proposal.pairingTopic == self.pairingTopic else { return }
            self.rejected = true
        }.store(in: &subscriptions)
        AppKit.instance.sessionEventPublisher.receive(on: DispatchQueue.main).sink { [weak self] payload in
            guard let self, payload.sessionTopic == self.boundTopic,
                  payload.event.name == "accountsChanged" else { return }
            self.accountChanged = true
            self.invalidatedTopics.insert(payload.sessionTopic)
        }.store(in: &subscriptions)
        configured = true
    }

    func presentWalletPicker() {
        fundingChain = nil
        attempt = UUID()
        rejected = false
        connectionError = nil
        accountChanged = false
        boundAddress = nil
        boundTopic = nil
        selectedWallet = nil
        pairingTopic = nil
        pendingPairingURL = nil
        pairingReady = false
        choosing = false
        NSLog("[SocketFiEVM] stage=wallet_picker")
        // Every attempt requires a wallet choice and a newly approved account.
        // Restored sessions must never bypass the picker or supply an old address.
        showingPicker = true
    }

    var selectedSessionTopic: String? { currentSession?.topic }

    /// Transactions are bound to the wallet session used for this account's login.
    /// Never fall back to a different saved wallet or the authentication picker.
    func useAccountAuthority(_ accountSession: SocketFiSession) throws {
        fundingChain = nil
        finishAttempt()
        boundTopic = nil
        boundAddress = nil
        selectedWallet = nil
        connectionError = nil
        rejected = false
        accountChanged = false
        guard configured, accountSession.account.signer == .evmWallet else {
            throw SocketFiNativeError.sessionUnavailable
        }
        let session = try Self.transactionSession(
            sessions: AppKit.instance.getSessions(), topic: accountSession.evmWalletSessionTopic,
            owner: accountSession.evmOwnerAddress, invalidatedTopics: invalidatedTopics
        )
        boundTopic = session.topic
        boundAddress = accountSession.evmOwnerAddress?.lowercased()
        NSLog("[SocketFiWithdrawal] stage=account_authority_selected")
    }

    static func transactionSession(sessions: [Session], topic: String?, owner: String?,
                                   invalidatedTopics: Set<String> = []) throws -> Session {
        guard let topic, !topic.isEmpty, let owner, !owner.isEmpty,
              !invalidatedTopics.contains(topic),
              let session = sessions.first(where: { $0.topic == topic && $0.expiryDate > Date() }) else {
            throw SocketFiNativeError.configuration("Your wallet connection needs to be renewed. Sign in again with this account’s EVM wallet, then retry the transaction.")
        }
        _ = try resolveAccount(session: session, displayedAddress: nil, boundAddress: owner.lowercased())
        return session
    }

    func finishAttempt() {
        attempt = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        pairingTopic = nil
        pendingPairingURL = nil
        pairingReady = false
        showingPicker = false
        choosing = false
    }

    var hasSelectedSession: Bool { currentSession != nil }

    var connectedWalletName: String? { configured ? currentSession?.peer.name : nil }

    func loadWallets() async {
        guard configured, !loadingWallets else { return }
        loadingWallets = true
        catalogueError = nil
        defer { loadingWallets = false }
        do {
            var url = URLComponents(string: "https://explorer-api.walletconnect.com/v3/wallets")!
            url.queryItems = [URLQueryItem(name: "page", value: String(cataloguePage + 1)),
                              URLQueryItem(name: "entries", value: "1000"),
                              URLQueryItem(name: "projectId", value: projectID),
                              URLQueryItem(name: "sdks", value: "sign_v2"),
                              URLQueryItem(name: "platforms", value: "ios"),
                              URLQueryItem(name: "chains", value: "eip155:1")]
            var request = URLRequest(url: url.url!, timeoutInterval: 20)
            request.setValue(projectID, forHTTPHeaderField: "x-project-id")
            request.setValue("appkit", forHTTPHeaderField: "x-sdk-type")
            request.setValue("SocketFi", forHTTPHeaderField: "Referer")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let page = try JSONDecoder().decode(SocketFiWalletCatalogue.self, from: data)
            let existing = Set(wallets.map(\.id))
            wallets += page.data.filter { !existing.contains($0.id) }
            let querySchemes = Set(Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? [])
            func installed(_ wallet: SocketFiWalletChoice) -> Bool {
                guard let link = wallet.mobile_link, let url = URL(string: link),
                      let scheme = url.scheme, querySchemes.contains(scheme) else { return false }
                return UIApplication.shared.canOpenURL(url)
            }
            wallets.sort {
                let lhs = installed($0), rhs = installed($1)
                return lhs == rhs ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : lhs
            }
            catalogueCount = page.total
            cataloguePage += 1
        } catch { catalogueError = "Couldn’t load wallets. Check your connection and retry." }
    }

    func choose(_ wallet: SocketFiWalletChoice) {
        guard !choosing else { return }
        choosing = true // Lock before starting any async work: one tap, one proposal.
        selectedWallet = wallet
        boundTopic = nil
        let operation = attempt
        connectionTask = Task {
            do {
                let uri: WalletConnectURI
                if let fundingChain {
                    guard let chain = Blockchain("eip155:\(fundingChain)") else { throw SocketFiNativeError.invalidResponse }
                    uri = try await Sign.instance.connect(namespaces: ["eip155": ProposalNamespace(
                        chains: [chain], methods: ["eth_sendTransaction"], events: ["accountsChanged", "chainChanged"])])
                } else {
                    guard let connectionURI = try await AppKit.instance.connect(walletUniversalLink: nil) else {
                        throw SocketFiNativeError.configuration("Couldn’t prepare the wallet connection. Try again.")
                    }
                    uri = connectionURI
                }
                try Task.checkCancellation()
                guard operation == attempt else { return }
                pairingTopic = uri.topic
                guard let link = wallet.mobile_link,
                      let url = Self.pairingURL(link: link, uri: uri.absoluteString) else {
                    throw SocketFiNativeError.configuration("This wallet has no supported iPhone connection link. Choose another wallet.")
                }
                var destination = url
                let schemes = Set(Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? [])
                if let scheme = url.scheme, schemes.contains(scheme),
                   !UIApplication.shared.canOpenURL(URL(string: link)!),
                   let universal = wallet.mobile.universal, !universal.isEmpty,
                   let fallback = Self.pairingURL(link: universal, uri: uri.absoluteString) {
                    destination = fallback
                }
                pendingPairingURL = destination
                pairingReady = true
                // A declined iOS Open prompt must not trigger another launch.
                try await openWalletURL(destination)
                NSLog("[SocketFiEVM] stage=pairing_wallet_opened")
            } catch {
                guard operation == attempt else { return }
                connectionError = error
            }
        }
    }

    static func pairingURL(link: String, uri: String) -> URL? {
        guard let base = URL(string: link), let scheme = base.scheme, !scheme.isEmpty else { return nil }
        let prefix = link.hasSuffix("/") ? String(link.dropLast()) : link
        let normalized = (scheme == "https" || scheme == "http") ? prefix : (link.contains("://") ? link : link + "//")
        let alreadyWC = base.host == "wc" || base.path.split(separator: "/").last == "wc"
        let target = alreadyWC ? prefix : (normalized.hasSuffix("://") ? normalized + "wc" : normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/wc")
        guard var parts = URLComponents(string: target) else { return nil }
        parts.queryItems = [URLQueryItem(name: "uri", value: uri)]
        return parts.url
    }

    private func openWalletURL(_ url: URL) async throws {
        let deadline = Date().addingTimeInterval(10)
        while UIApplication.shared.applicationState != .active {
            try Task.checkCancellation()
            guard Date() < deadline else { throw SocketFiNativeError.configuration("Return to SocketFi and tap Open wallet to continue.") }
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] = url.scheme == "https" ? [.universalLinksOnly: true] : [:]
        let opened = await UIApplication.shared.open(url, options: options)
        guard opened else { throw SocketFiNativeError.configuration("Couldn’t open the wallet. Make sure it is installed, or choose another wallet.") }
    }

    func reopenWallet() async throws {
        if let pendingPairingURL, currentSession == nil { try await openWalletURL(pendingPairingURL); return }
        guard let session = currentSession else { throw SocketFiNativeError.sessionUnavailable }
        let links = [session.peer.redirect?.native, selectedWallet?.mobile_link, session.peer.redirect?.universal].compactMap { $0 }.compactMap(URL.init(string:))
        let schemes = Set(Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? [])
        for link in links {
            if let scheme = link.scheme, schemes.contains(scheme), !UIApplication.shared.canOpenURL(link) { continue }
            try await openWalletURL(link)
            return
        }
        throw SocketFiNativeError.configuration("Couldn’t open your connected wallet. Open it manually to approve, or cancel and sign in again with the same account.")
    }

    private var currentSession: Session? {
        guard configured else { return nil }
        let sessions = AppKit.instance.getSessions().filter { $0.expiryDate > Date() && !invalidatedTopics.contains($0.topic) }
        if let pairingTopic { return sessions.first { $0.pairingTopic == pairingTopic } }
        if let boundTopic { return sessions.first { $0.topic == boundTopic } }
        return nil
    }

    private func selectedAccount() throws -> Account {
        guard !accountChanged else {
            throw SocketFiNativeError.configuration("The wallet changed accounts. Cancel the old request and reconnect with the intended account.")
        }
        guard let session = currentSession else {
            throw SocketFiNativeError.configuration("The wallet disconnected. Reconnect and try again.")
        }
        return try Self.resolveAccount(session: session, displayedAddress: nil, boundAddress: boundAddress)
    }

    static func resolveAccount(session: Session, displayedAddress: String?, boundAddress: String?) throws -> Account {
        // Trust can approve both Solana and EVM when using AppKit defaults.
        // AppKit.getAddress() picks session.accounts.first (unordered), which
        // may be Solana. Resolve only explicitly approved EVM signing accounts.
        let accounts = session.namespaces.values
            .filter { $0.methods.contains("personal_sign") }
            .flatMap { $0.accounts }
            .filter { $0.blockchain.namespace == "eip155" }
            .sorted { $0.absoluteString < $1.absoluteString }
        let addresses = Set(accounts.map { $0.address.lowercased() })
        let displayed = displayedAddress?.lowercased()
        let selectedEvm = displayed.flatMap { addresses.contains($0) ? $0 : nil }
        guard let address = boundAddress ?? selectedEvm ?? (addresses.count == 1 ? addresses.first : nil),
              addresses.contains(address),
              selectedEvm == nil || selectedEvm == address,
              let account = accounts.first(where: { $0.address.lowercased() == address }) else {
            throw SocketFiNativeError.configuration("The wallet changed accounts or has no unambiguous EVM signing account. Disconnect, select the intended EVM account in your wallet, and reconnect.")
        }
        return account
    }

    func sign(message: String) async throws -> String {
        guard configured else { throw SocketFiNativeError.configuration("Wallet connection is not configured.") }
        if message == "__socketfi_address__" {
            let deadline = Date().addingTimeInterval(120)
            while currentSession == nil {
                try Task.checkCancellation()
                if let connectionError { throw connectionError }
                if rejected { throw SocketFiNativeError.authenticationCancelled }
                guard Date() < deadline else {
                    throw SocketFiNativeError.configuration("Wallet connection timed out. Return to SocketFi and try again.")
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            showingPicker = false
            let account = try selectedAccount()
            boundAddress = account.address.lowercased()
            boundTopic = currentSession?.topic
            NSLog("[SocketFiEVM] stage=session_settled")
            return account.address
        }
        let account = try selectedAccount()
        guard let session = currentSession else { throw SocketFiNativeError.sessionUnavailable }
        // Explicit params preserve the raw 32-byte hex challenge, and avoid
        // AppKit's convenience API silently returning without a selected chain.
        let request = try Request(topic: session.topic, method: "personal_sign",
                                  params: AnyCodable([message, account.address]), chainId: account.blockchain)
        var result: Result<String, Error>?
        let subscription = AppKit.instance.sessionResponsePublisher.receive(on: DispatchQueue.main).sink { response in
            guard response.id == request.id, response.topic == request.topic else { return }
            Task { @MainActor in
                switch response.result {
                case let .response(value):
                    result = Result { try value.get(String.self) }
                case let .error(error):
                    result = .failure(error.code == 4001 || error.code == 5000
                        ? SocketFiNativeError.authenticationCancelled
                        : SocketFiNativeError.configuration("The wallet could not sign the request. Reconnect and retry."))
                }
            }
        }
        let sendTask = Task { @MainActor in
            do {
                try await AppKit.instance.request(params: request)
                try Task.checkCancellation()
                if result == nil { try await reopenWallet() }
                NSLog("[SocketFiEVM] stage=signature_requested")
            } catch { result = .failure(error) }
        }
        defer { subscription.cancel(); sendTask.cancel() }
        let deadline = Date().addingTimeInterval(120)
        while result == nil {
            try Task.checkCancellation()
            _ = try selectedAccount()
            guard Date() < deadline else {
                throw SocketFiNativeError.configuration("Signature approval timed out. Reject the old request in your wallet, then retry in SocketFi.")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        try Task.checkCancellation()
        _ = try selectedAccount()
        NSLog("[SocketFiEVM] stage=signature_response")
        return try result!.get()
    }

    func disconnect() async throws {
        guard configured else { return }
        for session in AppKit.instance.getSessions() {
            try await Sign.instance.disconnect(topic: session.topic)
        }
        boundAddress = nil
        boundTopic = nil
        selectedWallet = nil
    }

    /// Funding is a separate, newly approved session. It never updates the
    /// SocketFi login's saved topic or owner used for outgoing authorization.
    func connectFunding(chainID: Int) async throws -> (topic: String, address: String) {
        guard configured, chainID > 0 else { throw SocketFiNativeError.sessionUnavailable }
        presentWalletPicker()
        fundingChain = chainID
        let deadline = Date().addingTimeInterval(120)
        do {
            while currentSession == nil {
                try Task.checkCancellation()
                if let connectionError { throw connectionError }
                if rejected { throw SocketFiNativeError.authenticationCancelled }
                guard Date() < deadline else { throw SocketFiNativeError.configuration("The wallet connection timed out. Retry and approve the selected network in your wallet.") }
                try await Task.sleep(for: .milliseconds(200))
            }
            guard let session = currentSession else { throw SocketFiNativeError.sessionUnavailable }
            let account = try Self.fundingAccount(session: session, chainID: chainID, owner: nil)
            boundTopic = session.topic
            boundAddress = account.address.lowercased()
            finishAttempt()
            return (session.topic, account.address)
        } catch { finishAttempt(); throw error }
    }

    static func fundingAccount(session: Session, chainID: Int, owner: String?) throws -> Account {
        let accounts = session.namespaces.values.filter { $0.methods.contains("eth_sendTransaction") }
            .flatMap { $0.accounts }.filter { $0.blockchain.absoluteString == "eip155:\(chainID)" }
        let addresses = Set(accounts.map { $0.address.lowercased() })
        guard session.expiryDate > Date(), addresses.count == 1, let account = accounts.first,
              SocketFiCctpABI.isAddress(account.address), owner == nil || owner?.lowercased() == account.address.lowercased() else {
            throw SocketFiNativeError.configuration("Select the intended EVM account and source network in your wallet, then connect again. This wallet must support transactions on that network.")
        }
        return account
    }

    func fundingTransaction(topic: String, owner: String, chainID: Int, to: String, data: String) async throws -> String {
        fundingChain = chainID
        boundTopic = topic
        boundAddress = owner.lowercased()
        pairingTopic = nil
        guard let session = currentSession, !invalidatedTopics.contains(topic), SocketFiCctpABI.isAddress(to) else {
            throw SocketFiNativeError.configuration("The funding wallet disconnected or changed accounts. Check its transaction activity before continuing.")
        }
        let account = try Self.fundingAccount(session: session, chainID: chainID, owner: owner)
        let transaction = ["from": account.address, "to": to, "data": data, "value": "0x0", "chainId": "0x" + String(chainID, radix: 16)]
        let request = try Request(topic: topic, method: "eth_sendTransaction", params: AnyCodable([transaction]), chainId: account.blockchain)
        var result: Result<String, Error>?
        let subscription = AppKit.instance.sessionResponsePublisher.receive(on: DispatchQueue.main).sink { response in
            guard response.id == request.id, response.topic == topic else { return }
            Task { @MainActor in
                switch response.result {
                case let .response(value): result = Result { try value.get(String.self) }
                case let .error(error): result = .failure(error.code == 4001 || error.code == 5000
                    ? SocketFiNativeError.authenticationCancelled
                    : SocketFiNativeError.configuration("The wallet could not complete the transaction. Check its activity before retrying."))
                }
            }
        }
        let send = Task { @MainActor in
            do {
                try await AppKit.instance.request(params: request)
                if result == nil { try await reopenWallet() }
            } catch { if result == nil { result = .failure(error) } }
        }
        defer { subscription.cancel(); send.cancel() }
        let deadline = Date().addingTimeInterval(180)
        while result == nil {
            try Task.checkCancellation()
            guard Date() < deadline else { throw SocketFiNativeError.configuration("Wallet approval timed out. Check your wallet activity; SocketFi will track this deposit without sending it again.") }
            try await Task.sleep(for: .milliseconds(200))
        }
        // Preserve a returned hash even if the wallet changed accounts after
        // broadcasting. The backend verifies the burn's exact sender and calldata.
        let hash = try result!.get()
        guard SocketFiCctpABI.isHash(hash) else { throw SocketFiNativeError.invalidResponse }
        return hash
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard configured else { return false }
        guard url.scheme == "socketfi", url.host == "walletconnect" else { return false }
        NSLog("[SocketFiEVM] stage=deep_link_return")
        // A plain redirect only foregrounds the app; settlement comes via relay.
        if url.query == nil { return true }
        return AppKit.instance.handleDeeplink(url)
    }
}

private struct SocketFiWebSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        SocketFiWebSocket(request: URLRequest(url: url))
    }
}

private final class SocketFiWebSocket: NSObject, WebSocketConnecting, WebSocketDelegate {
    private let socket: WebSocket
    private(set) var isConnected = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?

    var request: URLRequest {
        get { socket.request }
        set { socket.request = newValue }
    }

    init(request: URLRequest) {
        socket = WebSocket(request: request)
        super.init()
        socket.delegate = self
        socket.callbackQueue = DispatchQueue(label: "fi.socket.socketfi.walletconnect", attributes: [])
    }

    func connect() { socket.connect() }

    func disconnect() { socket.disconnect() }

    func write(string: String, completion: (() -> Void)?) {
        socket.write(string: string, completion: completion)
    }

    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected:
            isConnected = true
            onConnect?()
        case let .disconnected(reason, _):
            isConnected = false
            onDisconnect?(NSError(domain: "SocketFiWalletConnect", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]))
        case let .text(value):
            onText?(value)
        case let .error(error):
            isConnected = false
            onDisconnect?(error)
        case .cancelled, .peerClosed:
            isConnected = false
            onDisconnect?(nil)
        default:
            break
        }
    }
}
