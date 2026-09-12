import SwiftUI
import SocketFiNativeKit
import CryptoKit

/// Add-guardian follows the web client's own-account invocation. The index is
/// observational: a failed confirm-add must never cause a second transaction.
@MainActor
final class SocketFiGuardianModel: ObservableObject {
    struct Pending: Codable {
        let guardian: String
        var hash: String?
        var confirmed: Bool
    }
    @Published var address = ""
    @Published var review: SocketFiTransactionRequest?
    @Published var pending: Pending?
    @Published var error: String?
    @Published var syncing = false
    @Published var indexed = false
    @Published var storageFailed = false
    let wallet: SocketFiWalletModel
    private let file: URL
    private let api: SocketFiAPIClient

    init(wallet: SocketFiWalletModel, storageURL: URL? = nil) {
        self.wallet = wallet
        api = SocketFiAPIClient(configuration: wallet.configuration)
        let scope = "\(wallet.configuration.apiBaseURL.absoluteString):\(wallet.configuration.applicationID):\(wallet.configuration.clientID):\(wallet.session.account.network.rawValue):\(wallet.session.account.address)"
        let key = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        file = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GuardianUpdates/\(key).json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let saved = try JSONDecoder().decode(Pending.self, from: Data(contentsOf: file))
                guard SocketFiXDR.isAddress(saved.guardian), saved.guardian != wallet.session.account.address,
                      !saved.confirmed || saved.hash?.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else {
                    throw SocketFiNativeError.invalidResponse
                }
                pending = saved
            } catch { storageFailed = true; self.error = "The saved guardian update could not be read. Do not submit it again until its status is checked." }
        }
    }

    func prepare() {
        guard !wallet.busy, !wallet.unresolved, pending == nil, !storageFailed else { return }
        error = nil
        do {
            let candidate = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard SocketFiXDR.isAddress(candidate), candidate != wallet.session.account.address else {
                throw SocketFiNativeError.configuration("Enter a valid Stellar guardian address different from your wallet.")
            }
            guard let caps = wallet.capabilities else { throw SocketFiNativeError.configuration("Refresh wallet settings to check guardian availability.") }
            review = try SocketFiWalletTransactions.addGuardian(session: wallet.session, guardian: address, capabilities: caps)
        } catch { self.error = error.localizedDescription }
    }

    private func save(_ next: Pending) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        pending = next
    }

    func approve() async {
        guard let request = review, !wallet.busy, !wallet.unresolved, pending == nil, !storageFailed else { return }
        do {
            // Persist before opening the external signing surface. On relaunch,
            // an interrupted request is conservatively retained, never resent.
            try save(.init(guardian: request.review.destination, hash: nil, confirmed: false))
            wallet.actionResult = nil; wallet.review = request
            await wallet.approve()
            review = nil
            if let result = wallet.actionResult, result.confirmed, let hash = result.hash {
                try save(.init(guardian: request.review.destination, hash: hash, confirmed: true))
                wallet.dismissActionResult()
                await syncIndex()
            } else if wallet.unresolved {
                error = "Confirmation is unavailable. Check your account’s transaction history before taking another guardian action."
            } else {
                try FileManager.default.removeItem(at: file)
                pending = nil
                error = wallet.actionError ?? "The guardian update was not completed."
            }
        } catch { self.error = error.localizedDescription }
    }

    func syncIndex() async {
        guard !syncing, let saved = pending, saved.confirmed, let hash = saved.hash else { return }
        syncing = true; defer { syncing = false }
        struct Confirmation: Encodable {
            let network: String; let walletAddress: String; let guardianAddress: String; let transactionHash: String
        }
        // The web client accepts any successful JSON response from this endpoint.
        struct ConfirmationResponse: Decodable {}
        do {
            let _: ConfirmationResponse = try await api.post("api/account-guardians/confirm-add", body: Confirmation(
                network: wallet.session.account.network.rawValue, walletAddress: wallet.session.account.address,
                guardianAddress: saved.guardian, transactionHash: hash), bearerToken: wallet.session.accessToken,
                response: ConfirmationResponse.self)
            indexed = true; error = nil
        } catch {
            self.error = "Guardian added on the network. The guardian list could not be updated yet. Retry updates the list only; it will not request another signature."
        }
    }

    func finish() -> Bool {
        guard pending?.confirmed == true, !syncing else { return false }
        // Keep unsynchronized confirmations for a later index-only retry.
        if !indexed { return true }
        do { try FileManager.default.removeItem(at: file); pending = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

struct SocketFiGuardianView: View {
    @StateObject private var model: SocketFiGuardianModel
    @ObservedObject private var wallet: SocketFiWalletModel
    @Environment(\.dismiss) private var dismiss

    init(wallet: SocketFiWalletModel) {
        self.wallet = wallet
        _model = StateObject(wrappedValue: SocketFiGuardianModel(wallet: wallet))
    }

    var body: some View {
        List {
            if let saved = model.pending {
                Section {
                    Label(saved.confirmed ? "Guardian added" : "Check guardian update", systemImage: saved.confirmed ? "checkmark.circle" : "clock")
                        .font(.headline)
                    Text(saved.guardian).font(.footnote.monospaced()).textSelection(.enabled)
                    if let hash = saved.hash {
                        Link("View transaction", destination: wallet.transactionURL(hash))
                    } else {
                        Link("View account activity", destination: wallet.explorerURL)
                    }
                }
                if saved.confirmed {
                    Section {
                        if !model.indexed { Button("Refresh guardian list") { Task { await model.syncIndex() } }.disabled(model.syncing) }
                        Button("Done") { if model.finish() { dismiss() } }.disabled(model.syncing)
                    }
                }
            } else if let request = model.review {
                Section("Review guardian") {
                    LabeledContent("Network", value: request.review.network.rawValue)
                    Text(request.review.destination).font(.body.monospaced()).textSelection(.enabled)
                    Text("This address will join your recovery guardians. Only add an address you trust.").font(.subheadline)
                }
                Section {
                    Button(wallet.approvalTitle) { Task { await model.approve() } }.disabled(wallet.busy)
                    Button("Cancel", role: .cancel) { model.review = nil }.disabled(wallet.busy)
                }
            } else {
                Section {
                    Text("Add a trusted address to help recover your wallet.").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        TextField("Guardian address · G… or C…", text: $model.address)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("guardian.address")
                        PasteButton(payloadType: String.self) { model.address = $0.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                            .labelStyle(.iconOnly).accessibilityLabel("Paste guardian address")
                    }
                    LabeledContent("Network", value: wallet.networkLabel)
                    Button("Review guardian", action: model.prepare)
                        .disabled(wallet.busy || wallet.unresolved || model.storageFailed || model.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("guardian.review")
                }
                Section {
                    Link("View guardians on SocketFi", destination: URL(string: "https://\(wallet.session.account.network == .testnet ? "testnet.socketfi.app" : "socketfi.app")/settings/guardians")!)
                }
            }
            if wallet.busy { Section { ProgressView(wallet.phase) } }
            if wallet.unresolved && model.pending == nil {
                Section { Text("Check your previous transaction before adding a guardian.").foregroundStyle(.secondary) }
            }
            if let error = model.error { Section { Text(error).font(.subheadline).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Add guardian").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(wallet.busy).interactiveDismissDisabled(wallet.busy)
        .task { if wallet.capabilities == nil { await wallet.refresh() } }
    }
}
