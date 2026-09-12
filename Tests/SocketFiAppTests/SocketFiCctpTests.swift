import XCTest
@testable import SocketFi
import SocketFiNativeKit
import CryptoSwift
@preconcurrency import ReownAppKit

@MainActor
final class SocketFiCctpTests: XCTestCase {
    // Independent reference: viem 2.37.3 encodeFunctionData using the web app ABI.
    static let fixture = #"{"sessionId":"77777777-7777-4777-8777-777777777777","expiresAt":"2100-01-01T00:00:00.000Z","source":{"chainId":84532,"domain":6,"label":"Base Sepolia","network":"TESTNET","nativeSymbol":"ETH","usdc":"0x036CbD53842c5426634e7929541eC2318f3dCF7e","tokenMessengerV2":"0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA","explorerTxUrl":"https://sepolia.basescan.org/tx/"},"network":"TESTNET","sender":"0x1111111111111111111111111111111111111111","recipient":"CCFBZEUCDA4XT5TBSIHO6SH72P5NNQSUGFHAZTPS7YWMNXFS7KXAM5ZV","amount":"123456789","maxFee":"12346","minFinalityThreshold":1000,"destinationDomain":27,"mintRecipient":"0x3de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e","destinationCaller":"0x3de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e","hookData":"0x0000000000000000000000000000000000000000000000000000000000000038434346425a45554344413458543554425349484f365348373250354e4e515355474648415a5450533759574d4e584653374b58414d355a56","stellarForwarder":"CA66Q2WFBND6V4UEB7RD4SAXSVIWMD6RA4X3U32ELVFGXV5PJK4T4VSZ","eta":"Usually under 30 seconds"}"#
    static let expectedBurn = "0x779b432d00000000000000000000000000000000000000000000000000000000075bcd15000000000000000000000000000000000000000000000000000000000000001b3de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e000000000000000000000000036cbd53842c5426634e7929541ec2318f3dcf7e3de86ac50b47eaf2840fe23e48179551660fd1072fba6f445d4a6bd7af4ab93e000000000000000000000000000000000000000000000000000000000000303a00000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000580000000000000000000000000000000000000000000000000000000000000038434346425a45554344413458543554425349484f365348373250354e4e515355474648415a5450533759574d4e584653374b58414d355a560000000000000000"
    static let expectedApproval = "0x095ea7b30000000000000000000000008fe6b999dc680ccfdd5bf7eb0974218be2542daa00000000000000000000000000000000000000000000000000000000075bcd15"
    static func prepared() throws -> SocketFiCctpPrepared { try JSONDecoder().decode(SocketFiCctpPrepared.self, from: Data(fixture.utf8)) }

    func testCalldataMatchesViemAndExactApprovalNeverUsesUnlimitedAllowance() throws {
        let p = try Self.prepared()
        try p.validate(chain: p.source, sender: p.sender, recipient: p.recipient, amount: "123.456789", speed: "FAST")
        XCTAssertEqual(try SocketFiCctpABI.approve(p), Self.expectedApproval)
        XCTAssertEqual(try SocketFiCctpABI.burn(p), Self.expectedBurn)
        XCTAssertEqual(try SocketFiCctpABI.word("9007199254740993").suffix(14), "20000000000001")
    }

    func testPreparationRejectsChangedRecipientNetworkTokenFeeExpiryAndHook() throws {
        let p = try Self.prepared()
        let source = try JSONSerialization.jsonObject(with: Data(Self.fixture.utf8)) as! [String: Any]
        let invalid: [(String, Any)] = [("amount", "123456788"), ("maxFee", "123456789"), ("maxFee", "-1"),
            ("destinationDomain", 0), ("minFinalityThreshold", 2000), ("network", "PUBLIC"),
            ("sender", "0x2222222222222222222222222222222222222222"), ("recipient", p.stellarForwarder),
            ("hookData", "0x" + String(repeating: "00", count: 88)), ("mintRecipient", "0x" + String(repeating: "00", count: 32)),
            ("expiresAt", "2020-01-01T00:00:00.000Z")]
        for (key, value) in invalid {
            var changed = source; changed[key] = value
            let decoded = try JSONDecoder().decode(SocketFiCctpPrepared.self, from: JSONSerialization.data(withJSONObject: changed))
            XCTAssertThrowsError(try decoded.validate(chain: p.source, sender: p.sender, recipient: p.recipient, amount: "123.456789", speed: "FAST"), key)
        }
        var changed = source; var chain = source["source"] as! [String: Any]
        chain["usdc"] = "0x2222222222222222222222222222222222222222"; changed["source"] = chain
        let decoded = try JSONDecoder().decode(SocketFiCctpPrepared.self, from: JSONSerialization.data(withJSONObject: changed))
        XCTAssertThrowsError(try decoded.validate(chain: p.source, sender: p.sender, recipient: p.recipient, amount: "123.456789", speed: "FAST"))
    }

    func testFundingPermissionCannotBeUsedForLoginAndRequiresExactChainAndOwner() throws {
        let p = try Self.prepared()
        let session = Session(topic: "funding", pairingTopic: "pairing", peer: AppMetadata(name: "Fixture", description: "Fixture", url: "https://example.invalid", icons: [], redirect: try AppMetadata.Redirect(native: "fixture-wallet://", universal: nil)),
            requiredNamespaces: [:], namespaces: ["eip155": SessionNamespace(accounts: [Account("eip155:84532:" + p.sender)!], methods: ["eth_sendTransaction"], events: [])],
            sessionProperties: nil, scopedProperties: nil, expiryDate: Date().addingTimeInterval(60))
        XCTAssertEqual(try SocketFiWalletConnect.fundingAccount(session: session, chainID: 84532, owner: p.sender).address, p.sender)
        XCTAssertThrowsError(try SocketFiWalletConnect.fundingAccount(session: session, chainID: 1, owner: p.sender))
        XCTAssertThrowsError(try SocketFiWalletConnect.fundingAccount(session: session, chainID: 84532, owner: "0x2222222222222222222222222222222222222222"))
        XCTAssertThrowsError(try SocketFiWalletConnect.resolveAccount(session: session, displayedAddress: nil, boundAddress: p.sender))
    }

    func testLostBurnResponsePersistsBeforeWalletCallAndNeverResendsAfterRelaunch() async throws {
        let setup = try setup(phase: .approved)
        defer { try? FileManager.default.removeItem(at: setup.file) }
        setup.funding.outcome = .failure(URLError(.timedOut))
        setup.funding.onSend = {
            let record = try! JSONDecoder().decode(SocketFiCctpPending.self, from: Data(contentsOf: setup.file))
            XCTAssertEqual(record.phase, .burnRequested, "Persist before crossing the external wallet boundary")
        }
        setup.model.deposit(); setup.model.deposit()
        await idle(setup.model)
        XCTAssertEqual(setup.funding.sends, 1)
        XCTAssertEqual(setup.model.pending?.phase, .burnRequested)
        let restored = SocketFiCctpDepositModel(session: setup.session, configuration: setup.configuration, client: setup.client, funding: setup.funding, storageURL: setup.file)
        await restored.refresh()
        restored.deposit(); restored.discard()
        XCTAssertEqual(restored.pending?.phase, .burnRequested)
        XCTAssertEqual(setup.funding.sends, 1)
    }

    func testReturnedHashSurvivesSettlementNetworkFailure() async throws {
        let setup = try setup(phase: .approved)
        defer { try? FileManager.default.removeItem(at: setup.file) }
        setup.client.failStatus = true
        setup.model.deposit()
        await idle(setup.model)
        let saved = try JSONDecoder().decode(SocketFiCctpPending.self, from: Data(contentsOf: setup.file))
        XCTAssertEqual(saved.burnHash, "0x" + String(repeating: "a", count: 64))
        XCTAssertEqual(saved.phase, .tracking)
        setup.model.deposit()
        XCTAssertEqual(setup.funding.sends, 1)
    }

    func testExplicitWalletRejectionAllowsReviewButInsufficientFundsNeverOpensWallet() async throws {
        let setup = try setup(phase: .approved)
        defer { try? FileManager.default.removeItem(at: setup.file) }
        setup.funding.outcome = .failure(SocketFiNativeError.authenticationCancelled)
        setup.model.deposit(); await idle(setup.model)
        XCTAssertEqual(setup.model.pending?.phase, .approved)
        XCTAssertEqual(setup.funding.sends, 1)
        setup.client.insufficient = true
        setup.model.deposit(); await idle(setup.model)
        XCTAssertEqual(setup.funding.sends, 1)
    }

    func testCorruptRecoveryRecordBlocksNewDepositAndKeepsFile() async throws {
        let setup = try setup(phase: .approved)
        defer { try? FileManager.default.removeItem(at: setup.file) }
        try Data("invalid".utf8).write(to: setup.file)
        let restored = SocketFiCctpDepositModel(session: setup.session, configuration: setup.configuration, client: setup.client, funding: setup.funding, storageURL: setup.file)
        XCTAssertTrue(restored.storageFailed)
        restored.start(); restored.deposit(); restored.discard()
        XCTAssertEqual(setup.funding.sends, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: setup.file.path))
    }

    func testCompletedDepositNeverRefreshesOrRequestsAnotherSignature() async throws {
        let setup = try setup(phase: .complete)
        defer { try? FileManager.default.removeItem(at: setup.file) }
        setup.client.failStatus = true
        await setup.model.refresh()
        setup.model.approveUSDC(); setup.model.deposit(); setup.model.reconnect()
        XCTAssertEqual(setup.model.pending?.phase, .complete)
        XCTAssertFalse(setup.model.busy)
        XCTAssertNil(setup.model.error)
        XCTAssertEqual(setup.funding.sends, 0)
        XCTAssertTrue(setup.model.finish())
        XCTAssertNil(setup.model.pending)
    }

    private func idle(_ model: SocketFiCctpDepositModel) async {
        for _ in 0..<100 where model.busy { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.busy)
    }
    private func setup(phase: SocketFiCctpPending.Phase) throws -> (model: SocketFiCctpDepositModel, file: URL, client: CctpClientStub, funding: CctpFundingStub, session: SocketFiSession, configuration: SocketFiConfiguration) {
        let p = try Self.prepared()
        let configuration = SocketFiConfiguration(apiBaseURL: URL(string: "https://fixture.invalid")!, clientID: "fixture", applicationID: "fixture", network: .testnet, relyingPartyID: "fixture.invalid")
        let session = SocketFiSession(account: .init(address: p.recipient, network: .testnet, signer: .passkey), accessToken: "fixture", expiresAt: Date().addingTimeInterval(3600))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let saved = SocketFiCctpPending(chain: p.source, sender: p.sender, topic: "funding", recipient: p.recipient, amount: "123.456789", speed: "FAST", idempotencyKey: UUID().uuidString, prepared: p, phase: phase)
        try JSONEncoder().encode(saved).write(to: file)
        let client = CctpClientStub(prepared: p), funding = CctpFundingStub(sender: p.sender)
        return (SocketFiCctpDepositModel(session: session, configuration: configuration, client: client, funding: funding, storageURL: file), file, client, funding, session, configuration)
    }
}

@MainActor
private final class CctpClientStub: SocketFiCctpServicing {
    let prepared: SocketFiCctpPrepared
    var failStatus = false
    var insufficient = false
    init(prepared: SocketFiCctpPrepared) { self.prepared = prepared }
    func chains() async throws -> [SocketFiCctpChain] { [prepared.source] }
    func prepare(chain: SocketFiCctpChain, sender: String, amount: String, speed: String, idempotencyKey: String) async throws -> SocketFiCctpPrepared { prepared }
    func readiness(_ prepared: SocketFiCctpPrepared) async throws -> SocketFiCctpReadiness {
        .init(sessionId: prepared.sessionId, network: .testnet, chainId: prepared.source.chainId, sender: prepared.sender, balance: insufficient ? "0" : "1000000000", allowance: prepared.amount, gasBalance: "1000000000000000000", gasRequired: "1000000000000")
    }
    func status(_ prepared: SocketFiCctpPrepared, burnHash: String?) async throws -> SocketFiCctpStatus {
        if failStatus { throw URLError(.notConnectedToInternet) }
        return .init(sessionId: prepared.sessionId, network: .testnet, chainId: prepared.source.chainId, sender: prepared.sender, recipient: prepared.recipient, status: "PREPARED", burnTxHash: nil, stellarTxHash: nil)
    }
}
@MainActor
private final class CctpFundingStub: SocketFiCctpFunding {
    let sender: String
    var sends = 0
    var onSend: (() -> Void)?
    var outcome: Result<String, Error> = .success("0x" + String(repeating: "a", count: 64))
    init(sender: String) { self.sender = sender }
    func connectFunding(chainID: Int) async throws -> (topic: String, address: String) { ("funding", sender) }
    func fundingTransaction(topic: String, owner: String, chainID: Int, to: String, data: String) async throws -> String {
        sends += 1; onSend?(); await Task.yield(); return try outcome.get()
    }
    func finishAttempt() {}
}
