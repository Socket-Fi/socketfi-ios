import XCTest
@testable import SocketFi
import SocketFiNativeKit

@MainActor
final class SocketFiGuardianTests: XCTestCase {
    let account = "CCFBZEUCDA4XT5TBSIHO6SH72P5NNQSUGFHAZTPS7YWMNXFS7KXAM5ZV"
    let guardian = "GBARGJH4BTODPXFAK6UJGUR37LMUG4N7V46GIH4AD57VLO3ZH4LYHHD3"
    func capabilities() throws -> SocketFiProjectCapabilities {
        try JSONDecoder().decode(SocketFiProjectCapabilities.self, from: Data("""
        {"clientId":"fixture","networks":["TESTNET"],"allowedInvocations":[{"network":"TESTNET","contractId":"$account","functions":["add_guardian"]}]}
        """.utf8))
    }
    func session(expired: Bool = false) -> SocketFiSession {
        SocketFiSession(account: SocketFiAccount(address: account, network: .testnet, signer: .passkey), accessToken: "fixture", expiresAt: Date().addingTimeInterval(expired ? -60 : 3600))
    }
    func testGuardianRequestBindsOwnAccountNetworkAndExactAddressXdr() throws {
        let request = try SocketFiWalletTransactions.addGuardian(session: session(), guardian: guardian, capabilities: capabilities())
        XCTAssertEqual(request.contractID, account)
        XCTAssertEqual(request.functionName, "add_guardian")
        XCTAssertEqual(request.argsXDR, [try SocketFiXDR.address(guardian)])
        XCTAssertEqual(request.review.source, account)
        XCTAssertEqual(request.review.destination, guardian)
        XCTAssertEqual(request.review.network, .testnet)
    }
    func testGuardianPolicyCannotAuthorizeAnotherAccountOrFunction() throws {
        let caps = try capabilities()
        XCTAssertFalse(caps.allows(network: .testnet, contract: account, function: "add_guardian"))
        XCTAssertFalse(caps.allows(network: .public, contract: account, function: "add_guardian", account: account))
        XCTAssertFalse(caps.allows(network: .testnet, contract: account, function: "upgrade", account: account))
        XCTAssertFalse(caps.allows(network: .testnet, contract: account, function: "add_guardian", account: guardian))
        for value in [account, "invalid", "0x1111111111111111111111111111111111111111"] {
            XCTAssertThrowsError(try SocketFiWalletTransactions.addGuardian(session: session(), guardian: value, capabilities: caps))
        }
        XCTAssertThrowsError(try SocketFiWalletTransactions.addGuardian(session: session(expired: true), guardian: guardian, capabilities: caps))
    }
    func testPersistedGuardianUpdateBlocksAnotherSigningAttemptAfterRelaunch() async throws {
        let config = SocketFiConfiguration(apiBaseURL: URL(string: "https://fixture.invalid")!, clientID: "guardian-fixture", applicationID: "fixture", network: .testnet, relyingPartyID: "fixture.invalid")
        let wallet = SocketFiWalletModel(session: session(), configuration: config, signer: .init(configuration: config))
        wallet.unresolved = false; wallet.capabilities = try capabilities()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        for confirmed in [false, true] {
            let saved = SocketFiGuardianModel.Pending(guardian: guardian, hash: confirmed ? String(repeating: "a", count: 64) : nil, confirmed: confirmed)
            try JSONEncoder().encode(saved).write(to: file)
            let model = SocketFiGuardianModel(wallet: wallet, storageURL: file)
            model.address = guardian
            model.prepare(); await model.approve()
            XCTAssertNil(model.review)
            XCTAssertFalse(wallet.busy)
            XCTAssertEqual(model.pending?.confirmed, confirmed)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
        try Data("invalid".utf8).write(to: file)
        let corrupt = SocketFiGuardianModel(wallet: wallet, storageURL: file)
        corrupt.address = guardian; corrupt.prepare(); await corrupt.approve()
        XCTAssertTrue(corrupt.storageFailed)
        XCTAssertNil(corrupt.review)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

}
