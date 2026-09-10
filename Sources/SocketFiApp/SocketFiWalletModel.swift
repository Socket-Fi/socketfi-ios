import SwiftUI
import SocketFiNativeKit

@MainActor
final class SocketFiWalletModel: ObservableObject {
    enum Action: String, Identifiable { case deposit, address, delegation, withdraw, swap; var id: String { rawValue } }
    struct Receipt {
        let title: String
        let hash: String?
        let confirmed: Bool
    }

    let session: SocketFiSession
    let configuration: SocketFiConfiguration
    private let wallet: SocketFiWalletClient
    private let signer: SocketFiNativeAccountClient
    @Published var snapshot: SocketFiWalletSnapshot?
    @Published var capabilities: SocketFiProjectCapabilities?
    @Published var loading = false
    @Published var busy = false
    @Published var error: String?
    @Published var actionError: String?
    @Published var action: Action?
    @Published var receipt: Receipt?
    @Published var unresolved: Bool
    @Published var fromID = ""
    @Published var toID = ""
    @Published var amount = ""
    @Published var recipient = ""
    @Published var slippageBps = 50
    @Published var quote: SocketFiSwapQuote?
    @Published var review: SocketFiTransactionRequest?
    @Published var phase = ""
    @Published var hideBalances = false

    init(session: SocketFiSession, configuration: SocketFiConfiguration, signer: SocketFiNativeAccountClient) {
        self.session = session
        self.configuration = configuration
        self.wallet = SocketFiWalletClient(configuration: configuration)
        self.signer = signer
        self.unresolved = UserDefaults.standard.bool(forKey: Self.pendingKey(configuration, session))
        if unresolved { receipt = Receipt(title: "Check your last transaction", hash: nil, confirmed: false) }
    }

    var tokens: [SocketFiToken] { snapshot?.tokens ?? [] }
    var from: SocketFiToken? { tokens.first { $0.id == fromID } }
    var to: SocketFiToken? { tokens.first { $0.id == toID } }
    var networkLabel: String { session.account.network == .testnet ? "Testnet" : "Stellar" }
    var depositURL: URL {
        URL(string: "https://\(session.account.network == .testnet ? "testnet.socketfi.app" : "socketfi.app")/deposit/\(session.account.address)")!
    }
    var explorerURL: URL {
        URL(string: "https://stellar.expert/explorer/\(session.account.network == .testnet ? "testnet" : "public")/contract/\(session.account.address)")!
    }
    func transactionURL(_ hash: String) -> URL {
        URL(string: "https://stellar.expert/explorer/\(session.account.network == .testnet ? "testnet" : "public")/tx/\(hash)")!
    }
    var supportsSwaps: Bool {
        capabilities?.allowedInvocations.contains { $0.network == session.account.network && $0.functions.contains("swap_chained") } == true
    }
    var canWithdraw: Bool {
        guard let from else { return false }
        return capabilities?.allows(network: session.account.network, contract: from.contract, function: "transfer") == true
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        error = nil
        do {
            let next = try await wallet.load(session: session)
            try Task.checkCancellation()
            snapshot = next
            if !tokens.contains(where: { $0.id == fromID }) { fromID = tokens.first?.id ?? "" }
            if !tokens.contains(where: { $0.id == toID }) { toID = tokens.first(where: { $0.id != fromID })?.id ?? "" }
        } catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
        do { capabilities = try await wallet.capabilities() }
        catch is CancellationError { return }
        catch { capabilities = nil; self.error = self.error ?? "Balances are available, but transaction availability could not be checked. Pull down to retry." }
    }

    func addTokenToWatchlist(contract: String) async throws {
        guard !loading && !busy else {
            throw SocketFiNativeError.configuration("Wallet refresh is in progress. Try again after it finishes.")
        }
        loading = true
        error = nil
        defer { loading = false }
        try await wallet.addTokenToWatchlist(session: session, contract: contract)
        let next = try await wallet.load(session: session)
        snapshot = next
        if !tokens.contains(where: { $0.id == fromID }) { fromID = tokens.first?.id ?? "" }
        if !tokens.contains(where: { $0.id == toID }) { toID = tokens.first(where: { $0.id != fromID })?.id ?? "" }
    }

    func open(_ next: Action, token: SocketFiToken? = nil) {
        guard !busy else { return }
        amount = ""; recipient = ""; quote = nil; review = nil; actionError = nil
        if let token { fromID = token.id }
        if fromID == toID { toID = tokens.first(where: { $0.id != fromID })?.id ?? "" }
        action = next
    }

    func invalidateQuote() { quote = nil; review = nil; actionError = nil }

    func prepare() async {
        guard !busy, !unresolved else { return }
        busy = true; actionError = nil; phase = "Checking your balance…"
        defer { busy = false; phase = "" }
        do {
            snapshot = try await wallet.load(session: session)
            let permissions = try await wallet.capabilities()
            capabilities = permissions
            guard let from else { throw SocketFiNativeError.invalidResponse }
            if action == .withdraw {
                review = try SocketFiWalletTransactions.withdrawal(session: session, token: from, recipient: recipient, amount: amount, capabilities: permissions)
            } else if action == .swap {
                guard let to else { throw SocketFiNativeError.configuration("Choose a different token to receive.") }
                phase = "Finding your swap quote…"
                let fresh = try await wallet.quote(session: session, from: from, to: to, amount: amount, slippageBps: slippageBps)
                quote = fresh
                review = try SocketFiWalletTransactions.swap(session: session, from: from, to: to, amount: amount, slippageBps: slippageBps, quote: fresh, capabilities: permissions)
            }
        } catch is CancellationError { }
        catch { actionError = error.localizedDescription }
    }

    func approve() async {
        guard !busy, !unresolved, let request = review else { return }
        busy = true; actionError = nil; phase = "Approve with your passkey…"
        defer { busy = false; phase = "" }
        do {
            let result = try await signer.authorizePasskeyTransaction(request, onSubmission: { [self] in
                markUnresolved(true)
                phase = "Waiting for network confirmation…"
                receipt = Receipt(title: request.review.title, hash: nil, confirmed: false)
            }, confirmReview: { _ in true })
            markUnresolved(false)
            receipt = Receipt(title: request.review.title, hash: result.id, confirmed: true)
            review = nil; action = nil
            await refresh()
        } catch SocketFiNativeError.authenticationCancelled {
            actionError = "Approval cancelled. Nothing was submitted."
            review = nil
        } catch SocketFiNativeError.transactionFailed(let hash) {
            markUnresolved(false)
            receipt = Receipt(title: "Transaction failed", hash: hash, confirmed: false)
            actionError = "The network reported a failed transaction. Refresh your balance before trying again."
            review = nil
        } catch SocketFiNativeError.submissionUncertain(let hash) {
            markUnresolved(true)
            receipt = Receipt(title: "Confirmation unavailable", hash: hash, confirmed: false)
            review = nil; action = nil
        } catch {
            actionError = error.localizedDescription
            review = nil
        }
    }

    func acknowledgeCheckedActivity() {
        markUnresolved(false)
        receipt = nil
        Task { await refresh() }
    }

    private func markUnresolved(_ value: Bool) {
        unresolved = value
        UserDefaults.standard.set(value, forKey: Self.pendingKey(configuration, session))
    }
    private static func pendingKey(_ config: SocketFiConfiguration, _ session: SocketFiSession) -> String {
        "socketfi.pending.\(config.clientID).\(session.account.network.rawValue).\(session.account.address)"
    }
}
