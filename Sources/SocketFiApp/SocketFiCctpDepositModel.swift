import Foundation
import Combine
import CryptoSwift
import SocketFiNativeKit

@MainActor
protocol SocketFiCctpFunding {
    func connectFunding(chainID: Int) async throws -> (topic: String, address: String)
    func fundingTransaction(topic: String, owner: String, chainID: Int, to: String, data: String) async throws -> String
    func finishAttempt()
}
extension SocketFiWalletConnect: SocketFiCctpFunding {}

struct SocketFiCctpPending: Codable {
    enum Phase: String, Codable { case draft, review, approvalRequested, approved, burnRequested, tracking, complete }
    let chain: SocketFiCctpChain
    let sender: String
    var topic: String
    let recipient: String
    let amount: String
    let speed: String
    let idempotencyKey: String
    var prepared: SocketFiCctpPrepared?
    var phase: Phase = .draft
    var approvalHash: String?
    var burnHash: String?
    var stellarHash: String?
    var status: String?
    var burnMayHaveBeenSent: Bool { [.burnRequested, .tracking, .complete].contains(phase) }
}

@MainActor
final class SocketFiCctpDepositModel: ObservableObject {
    @Published var chains: [SocketFiCctpChain] = []
    @Published var chainID = 0
    @Published var amount = ""
    @Published var speed = "STANDARD"
    @Published private(set) var pending: SocketFiCctpPending?
    @Published private(set) var busy = false
    @Published private(set) var loadingChains = false
    @Published private(set) var message = ""
    @Published private(set) var error: String?
    @Published private(set) var storageFailed = false
    @Published private(set) var readiness: SocketFiCctpReadiness?
    let session: SocketFiSession
    let connection = SocketFiWalletConnect.shared
    private let client: any SocketFiCctpServicing
    private let funding: any SocketFiCctpFunding
    private let file: URL
    private var operation: Task<Void, Never>?

    init(session: SocketFiSession, configuration: SocketFiConfiguration, client: (any SocketFiCctpServicing)? = nil,
         funding: (any SocketFiCctpFunding)? = nil, storageURL: URL? = nil) {
        self.session = session
        self.client = client ?? SocketFiCctpClient(configuration: configuration, session: session)
        self.funding = funding ?? SocketFiWalletConnect.shared
        let key = [configuration.applicationID, configuration.clientID, session.account.network.rawValue, session.account.address].joined(separator: ":")
        let name = SHA2(variant: .sha256).calculate(for: Array(key.utf8)).toHexString()
        file = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CctpDeposits", isDirectory: true).appendingPathComponent(name + ".json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let saved = try JSONDecoder().decode(SocketFiCctpPending.self, from: Data(contentsOf: file))
                guard saved.recipient == session.account.address, saved.chain.network == session.account.network,
                      UUID(uuidString: saved.idempotencyKey) != nil, SocketFiCctpABI.isAddress(saved.sender) else { throw SocketFiNativeError.invalidResponse }
                pending = saved
            } catch {
                storageFailed = true
                self.error = "Saved deposit progress could not be opened. Check SocketFi’s explorer before starting another deposit. Your saved record has been retained."
            }
        }
    }

    var selectedChain: SocketFiCctpChain? { chains.first { $0.chainId == chainID } }
    var explorerURL: URL {
        var url = URLComponents(string: session.account.network == .testnet ? "https://testnet.socketfi.app/explorer" : "https://socketfi.app/explorer")!
        url.queryItems = [.init(name: "network", value: session.account.network.rawValue),
                          .init(name: "q", value: pending?.burnHash ?? session.account.address)]
        return url.url!
    }
    var canStart: Bool { !busy && !storageFailed && pending == nil && selectedChain != nil && (try? SocketFiAmount.atomic(amount, decimals: 6)) != nil && (try? SocketFiAmount.atomic(amount, decimals: 6)) != "0" }

    private func save(_ value: SocketFiCctpPending) throws {
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        pending = value
    }

    func load() async {
        guard !storageFailed, !loadingChains else { return }
        if pending != nil { await refresh(); return }
        loadingChains = true
        error = nil
        defer { loadingChains = false }
        do {
            chains = try await client.chains()
            try Task.checkCancellation()
            if selectedChain == nil { chainID = chains.first?.chainId ?? 0 }
            error = nil
        } catch is CancellationError { }
        catch { show(error) }
    }

    func start() {
        guard canStart, let chain = selectedChain else { return }
        let value = amount.trimmingCharacters(in: .whitespacesAndNewlines), selectedSpeed = speed
        run("Connect your funding wallet") {
            let wallet = try await self.funding.connectFunding(chainID: chain.chainId)
            try self.save(.init(chain: chain, sender: wallet.address, topic: wallet.topic, recipient: self.session.account.address,
                                amount: value, speed: selectedSpeed, idempotencyKey: UUID().uuidString))
            try await self.prepareSaved()
        }
    }

    func retryPreparation() { run("Preparing your deposit", action: { try await self.prepareSaved() }) }
    private func prepareSaved() async throws {
        guard var saved = pending, saved.phase == .draft else { return }
        message = "Getting the route and bridge fee"
        saved.prepared = try await client.prepare(chain: saved.chain, sender: saved.sender, amount: saved.amount,
                                                  speed: saved.speed, idempotencyKey: saved.idempotencyKey)
        saved.phase = .review
        try save(saved)
        if let prepared = saved.prepared { readiness = try await client.readiness(prepared) }
    }

    /// A separate tap approves the burn after the exact allowance is confirmed.
    func approveUSDC() {
        guard pending?.phase == .review else { return }
        run("Checking USDC and gas") {
            guard var saved = self.pending, let prepared = saved.prepared else { return }
            try self.validate(saved)
            let ready = try await self.client.readiness(prepared)
            self.readiness = ready
            try self.checkFunds(ready, prepared: prepared)
            if !SocketFiAmount.greater(prepared.amount, than: ready.allowance) {
                saved.phase = .approved; try self.save(saved); return
            }
            let calldata = try SocketFiCctpABI.approve(prepared)
            saved.phase = .approvalRequested
            try self.save(saved) // Must be durable before handing a transaction to a wallet.
            self.message = "Approve the USDC spending limit in your wallet"
            do {
                saved.approvalHash = try await self.funding.fundingTransaction(topic: saved.topic, owner: saved.sender,
                    chainID: saved.chain.chainId, to: saved.chain.usdc, data: calldata)
                try self.save(saved)
            } catch SocketFiNativeError.authenticationCancelled {
                saved.phase = .review; try self.save(saved)
                throw SocketFiNativeError.authenticationCancelled
            }
            self.message = "Waiting for USDC approval to confirm"
            for _ in 0..<36 {
                try await Task.sleep(for: .seconds(5))
                let updated = try await self.client.readiness(prepared)
                self.readiness = updated
                if !SocketFiAmount.greater(prepared.amount, than: updated.allowance) {
                    saved.phase = .approved; try self.save(saved); return
                }
            }
            throw SocketFiNativeError.configuration("USDC approval is still pending. Refresh its status; a second approval has not been sent.")
        }
    }

    func deposit() {
        guard pending?.phase == .approved else { return }
        run("Checking your deposit") {
            guard var saved = self.pending, let prepared = saved.prepared else { return }
            try self.validate(saved)
            let ready = try await self.client.readiness(prepared)
            try self.checkFunds(ready, prepared: prepared)
            guard !SocketFiAmount.greater(prepared.amount, than: ready.allowance) else {
                throw SocketFiNativeError.configuration("The USDC spending approval changed. Refresh before continuing.")
            }
            let calldata = try SocketFiCctpABI.burn(prepared)
            saved.phase = .burnRequested
            try self.save(saved)
            self.message = "Confirm the deposit in your EVM wallet"
            do {
                saved.burnHash = try await self.funding.fundingTransaction(topic: saved.topic, owner: saved.sender,
                    chainID: saved.chain.chainId, to: saved.chain.tokenMessengerV2, data: calldata)
                saved.phase = .tracking
                try self.save(saved)
            } catch SocketFiNativeError.authenticationCancelled {
                saved.phase = .approved; try self.save(saved)
                throw SocketFiNativeError.authenticationCancelled
            }
            try await self.updateStatus()
        }
    }

    func refresh() async {
        guard !busy, !storageFailed, pending?.phase != .complete else { return }
        busy = true
        message = "Checking deposit status"
        defer { busy = false }
        do {
            error = nil
            guard var saved = pending, let prepared = saved.prepared else { return }
            if saved.burnMayHaveBeenSent { try await updateStatus(); return }
            let status = try await client.status(prepared, burnHash: nil)
            if status.burnTxHash != nil || status.status != "PREPARED" {
                try accept(status, saved: saved); return
            }
            readiness = try await client.readiness(prepared)
            if let readiness, !SocketFiAmount.greater(prepared.amount, than: readiness.allowance) {
                saved.phase = .approved; try save(saved)
            } else if saved.phase == .approved {
                saved.phase = .review; try save(saved)
            }
        } catch { show(error) }
    }

    private func updateStatus() async throws {
        guard let saved = pending, let prepared = saved.prepared else { return }
        let state = try await client.status(prepared, burnHash: saved.burnHash)
        try accept(state, saved: saved)
    }

    private func accept(_ status: SocketFiCctpStatus, saved: SocketFiCctpPending) throws {
        var updated = saved
        updated.status = status.status
        updated.burnHash = status.burnTxHash ?? saved.burnHash
        updated.stellarHash = status.stellarTxHash
        if status.status == "SUCCESS" { updated.phase = .complete }
        else if status.burnTxHash != nil { updated.phase = .tracking }
        try save(updated)
    }

    func recover(hash: String) {
        guard SocketFiCctpABI.isHash(hash), pending?.burnMayHaveBeenSent == true else { return }
        run("Checking the burn transaction") {
            guard var saved = self.pending, let prepared = saved.prepared else { return }
            let state = try await self.client.status(prepared, burnHash: hash)
            saved.burnHash = hash
            try self.accept(state, saved: saved)
        }
    }

    func reconnect() {
        guard let saved = pending, !saved.burnMayHaveBeenSent, saved.phase != .approvalRequested else { return }
        run("Reconnect the same funding account") {
            let wallet = try await self.funding.connectFunding(chainID: saved.chain.chainId)
            guard wallet.address.lowercased() == saved.sender.lowercased() else {
                throw SocketFiNativeError.configuration("That is a different account. Reconnect the funding account shown in this deposit.")
            }
            var updated = saved; updated.topic = wallet.topic
            try self.save(updated)
        }
    }

    func discard() {
        guard !busy, let saved = pending, !saved.burnMayHaveBeenSent else { return }
        do { try FileManager.default.removeItem(at: file); pending = nil; readiness = nil; error = nil }
        catch { show(error) }
    }

    func finish() -> Bool {
        guard !busy, pending?.phase == .complete else { return false }
        do {
            try FileManager.default.removeItem(at: file)
            pending = nil; readiness = nil; error = nil
            return true
        } catch { show(error); return false }
    }

    func cancelConnection() { operation?.cancel(); funding.finishAttempt() }

    private func validate(_ saved: SocketFiCctpPending) throws {
        guard let prepared = saved.prepared else { throw SocketFiNativeError.invalidResponse }
        try prepared.validate(chain: saved.chain, sender: saved.sender, recipient: session.account.address, amount: saved.amount, speed: saved.speed)
    }
    private func checkFunds(_ ready: SocketFiCctpReadiness, prepared: SocketFiCctpPrepared) throws {
        guard !SocketFiAmount.greater(prepared.amount, than: ready.balance) else { throw SocketFiNativeError.configuration("Your funding wallet needs more USDC on the selected source network.") }
        guard ready.gasBalance != "0" else { throw SocketFiNativeError.configuration("Add the source network’s native token to your funding wallet for gas. Your wallet will show the exact gas fee before signing.") }
        guard !SocketFiAmount.greater(ready.gasRequired, than: ready.gasBalance) else { throw SocketFiNativeError.configuration("Your funding wallet needs more of the source network’s native token to cover the estimated gas fee.") }
    }
    private func run(_ message: String, action: @escaping @MainActor () async throws -> Void) {
        guard !busy, !storageFailed else { return }
        busy = true; error = nil; self.message = message
        operation = Task {
            defer { busy = false; operation = nil }
            do { try await action() }
            catch { show(error) }
        }
    }
    private func show(_ error: Error) {
        if error is CancellationError { self.error = "Connection cancelled. You can choose a wallet again." }
        else if case SocketFiNativeError.authenticationCancelled = error { self.error = "Request declined in your wallet. No new transaction was submitted by this request." }
        else if case SocketFiNativeError.requestFailed(let status, _, _) = error, status == 404, pending == nil {
            self.error = "In-app EVM deposits are not available on this API deployment yet. You can still receive Stellar deposits."
        } else { self.error = error.localizedDescription }
    }
}
